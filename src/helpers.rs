use std::collections::HashMap;

use cosmwasm_std::{ensure, Coin, Decimal256, Deps, Timestamp, Uint128, Uint256};

use crate::state::{get_claims_for_address, Claim, DistributionSlot};
use mantra_claimdrop_std::error::ContractError;
use mantra_claimdrop_std::msg::{Campaign, CampaignParams, DistributionType};

/// Validates the provided campaign parameters are valid.
pub(crate) fn validate_campaign_params(
    current_time: Timestamp,
    campaign_params: &CampaignParams,
) -> Result<(), ContractError> {
    campaign_params.validate_campaign_name_description()?;
    campaign_params.validate_campaign_type()?;
    campaign_params.validate_campaign_times(current_time)?;
    campaign_params.validate_campaign_distribution()?;
    campaign_params.validate_rewards()?;

    // Additional validation for Lump Sum distributions
    // The external validate_campaign_distribution incorrectly allows Lump Sum distributions
    // to be scheduled after campaign end. We need to ensure all Lump Sum distributions
    // have their start_time <= campaign end_time
    for distribution in &campaign_params.distribution_type {
        if let DistributionType::LumpSum { start_time, .. } = distribution {
            if *start_time > campaign_params.end_time {
                return Err(ContractError::InvalidInput {
                    reason: format!(
                        "Lump Sum distribution start time ({}) cannot be after campaign end time ({})",
                        start_time, campaign_params.end_time
                    ),
                });
            }
        }
    }

    Ok(())
}

/// Constant used for the fallback distribution slot
const FALLBACK_DISTRIBUTION_SLOT: usize = 0usize;

/// Calculates the amount a user can claim at this point in time
pub(crate) fn compute_claimable_amount(
    deps: Deps,
    campaign: &Campaign,
    current_time: &Timestamp,
    address: &str,
    total_claimable_amount: Uint128,
) -> Result<
    (
        Coin,
        HashMap<DistributionSlot, Claim>,
        HashMap<DistributionSlot, Claim>,
    ),
    ContractError,
> {
    let mut claimable_amount = Uint128::zero();
    let mut new_claims = HashMap::new();
    let previous_claims_for_address = get_claims_for_address(deps, address.to_string())?;

    if campaign.has_started(current_time) {
        for (distribution_slot, distribution) in
            campaign.distribution_type.iter().enumerate().clone()
        {
            // skip distributions that have not started yet
            if !distribution.has_started(current_time) {
                continue;
            }

            // check if the cliff period has passed for linear vesting distributions
            if let DistributionType::LinearVesting {
                cliff_duration: Some(cliff_duration),
                start_time,
                ..
            } = distribution
            {
                let cliff_end_time = start_time + cliff_duration;

                // if the cliff period has not passed yet, skip
                if current_time.seconds() < cliff_end_time {
                    continue;
                }
            }

            let previous_claim_for_address_for_distribution =
                previous_claims_for_address.get(&distribution_slot);

            let claim_amount = calculate_claim_amount_for_distribution(
                &current_time,
                total_claimable_amount,
                &distribution,
                &previous_claim_for_address_for_distribution,
            )?;

            // nothing to claim for the current distribution, skip
            if claim_amount == Uint128::zero() {
                continue;
            }

            claimable_amount = claimable_amount.checked_add(claim_amount)?;

            new_claims.insert(distribution_slot, (claim_amount, current_time.seconds()));
        }

        let (rounding_error_compensation_amount, slot) = get_compensation_for_rounding_errors(
            campaign,
            current_time,
            total_claimable_amount,
            previous_claims_for_address.clone(),
            &new_claims,
        )?;

        if rounding_error_compensation_amount > Uint128::zero() {
            claimable_amount = claimable_amount.checked_add(rounding_error_compensation_amount)?;

            let (amount, _) = match new_claims.get_mut(&slot) {
                Some(existing_claim) => existing_claim,
                None => {
                    let new_claim = (Uint128::zero(), current_time.seconds());
                    new_claims.insert(slot, new_claim);
                    new_claims.get_mut(&slot).unwrap()
                }
            };

            *amount = amount.checked_add(rounding_error_compensation_amount)?;
        }
    } else {
        return Err(ContractError::CampaignError {
            reason: "not started".to_string(),
        });
    }

    Ok((
        Coin {
            denom: campaign.reward_denom.clone(),
            amount: claimable_amount,
        },
        new_claims,
        previous_claims_for_address,
    ))
}

/// Calculates the claimable amount for a given distribution, total amount and previous claim.
fn calculate_claim_amount_for_distribution(
    current_time: &&Timestamp,
    total_user_allocation: Uint128,
    distribution_type: &&DistributionType,
    previous_claim_for_this_slot: &Option<&Claim>,
) -> Result<Uint128, ContractError> {
    match distribution_type {
        DistributionType::LinearVesting {
            percentage,
            start_time,
            end_time,
            ..
        } => {
            let amount_allocated_to_this_slot = Uint128::try_from(
                Decimal256::from(*percentage)
                    .checked_mul(Decimal256::from_ratio(
                        Uint256::from_uint128(total_user_allocation),
                        Uint256::one(),
                    ))?
                    .to_uint_floor(),
            )?;

            let already_claimed =
                previous_claim_for_this_slot.map_or(Uint128::zero(), |(amount, _)| *amount);

            let distribution_duration = end_time.saturating_sub(*start_time);

            // sanity check to ensure we don't get division by zero
            // this should never happen since `validate_campaign_times` ensures that the start time is less than the end time
            ensure!(
                distribution_duration > 0u64,
                ContractError::CampaignError {
                    reason: "distribution duration is 0".to_string(),
                }
            );

            let time_passed_since_start = current_time.seconds().saturating_sub(*start_time);
            let effective_time_passed =
                std::cmp::min(time_passed_since_start, distribution_duration);

            let vesting_progress = Decimal256::from_ratio(
                Uint256::from(effective_time_passed),
                Uint256::from(distribution_duration),
            );

            let total_vested_for_slot_at_current_time = Uint128::try_from(
                Decimal256::from_ratio(
                    Uint256::from_uint128(amount_allocated_to_this_slot),
                    Uint256::one(),
                )
                .checked_mul(vesting_progress)?
                .to_uint_floor(),
            )?;

            Ok(total_vested_for_slot_at_current_time.saturating_sub(already_claimed))
        }
        DistributionType::LumpSum { percentage, .. } => {
            let total_entitlement_for_lumpsum_slot = Uint128::try_from(
                Decimal256::from(*percentage)
                    .checked_mul(Decimal256::from_ratio(
                        Uint256::from_uint128(total_user_allocation),
                        Uint256::one(),
                    ))?
                    .to_uint_floor(),
            )?;

            let already_claimed_for_this_slot =
                previous_claim_for_this_slot.map_or(Uint128::zero(), |(amount, _)| *amount);

            let newly_claimable =
                total_entitlement_for_lumpsum_slot.saturating_sub(already_claimed_for_this_slot);
            Ok(newly_claimable)
        }
    }
}

/// Returns the compensation for rounding errors if the distribution types have ended. This is to claim
/// the potential remaining dust in the campaign for the user due to rounding errors.
fn get_compensation_for_rounding_errors(
    campaign: &Campaign,
    current_time: &Timestamp,
    total_claimable_amount: Uint128,
    previous_claims_for_address: HashMap<DistributionSlot, Claim>,
    new_claims: &HashMap<DistributionSlot, Claim>,
) -> Result<(Uint128, DistributionSlot), ContractError> {
    if distribution_types_ended(campaign, current_time) {
        let updated_claims = aggregate_claims(&previous_claims_for_address, new_claims)?;

        let total_claimed = updated_claims
            .iter()
            .fold(Uint128::zero(), |acc, (_, (amount, _))| {
                acc.checked_add(*amount).unwrap()
            });

        // get user dust to claim
        let (slot, _) = new_claims
            .iter()
            .find(|(_, (_, timestamp))| *timestamp == current_time.seconds())
            .unwrap_or((
                &FALLBACK_DISTRIBUTION_SLOT,
                &(Uint128::zero(), Default::default()),
            ));

        return Ok((
            total_claimable_amount.saturating_sub(total_claimed),
            slot.to_owned(),
        ));
    }

    Ok((Uint128::zero(), FALLBACK_DISTRIBUTION_SLOT))
}

/// Checks if all distribution types have ended
fn distribution_types_ended(campaign: &Campaign, current_time: &Timestamp) -> bool {
    for distribution_type in campaign.distribution_type.iter() {
        match distribution_type {
            DistributionType::LinearVesting { end_time, .. } => {
                if *end_time > current_time.seconds() {
                    return false;
                }
            }
            DistributionType::LumpSum { start_time, .. } => {
                // Lump Sum distributions are considered "ended" once their start_time has passed
                // since they pay out all tokens at once. However, if the start_time hasn't
                // occurred yet, the distribution hasn't ended.
                if *start_time > current_time.seconds() {
                    return false;
                }
            }
        }
    }

    true
}

/// Validates the raw address string.
pub fn validate_raw_address(deps: Deps, address_raw: &str) -> Result<String, ContractError> {
    if let Ok(addr) = deps.api.addr_validate(address_raw) {
        Ok(addr.to_string())
    } else {
        Ok(validate_address_placeholder(address_raw)?)
    }
}

// Maximum allowed length for a placeholder address string.
pub const MAX_PLACEHOLDER_ADDRESS_LEN: usize = 256;

/// Validates the placeholder address string.
pub fn validate_address_placeholder(placeholder: &str) -> Result<String, ContractError> {
    let address = placeholder.to_lowercase();

    // Ensure address length is between 1 and MAX_PLACEHOLDER_ADDRESS_LEN
    ensure!(
        !address.is_empty() && address.len() <= MAX_PLACEHOLDER_ADDRESS_LEN,
        ContractError::InvalidInput {
            reason: format!(
                "address '{}' must be between 1 and {} characters long (got {})",
                placeholder,
                MAX_PLACEHOLDER_ADDRESS_LEN,
                address.len()
            ),
        }
    );

    // Very permissive validation to support various placeholder types:
    // ENS domains (with emoji, international characters), email addresses, social handles, etc.
    // Only block control characters which could cause parsing/display issues
    if address.chars().any(|c| c.is_control()) {
        return Err(ContractError::InvalidInput {
            reason: format!("placeholder address '{placeholder}' contains control characters"),
        });
    }

    Ok(address)
}

/// Aggregates the new claims with the existing claims
pub fn aggregate_claims(
    previous_claims: &HashMap<DistributionSlot, Claim>,
    new_claims: &HashMap<DistributionSlot, Claim>,
) -> Result<HashMap<DistributionSlot, Claim>, ContractError> {
    let mut updated_claims = previous_claims.clone();

    for (slot, claim) in new_claims.iter() {
        let default_claim = (Uint128::zero(), 0u64);
        let previous_claim = updated_claims.get(slot).unwrap_or(&default_claim);
        let total_claimed_for_distribution_slot = previous_claim.0.checked_add(claim.0)?;
        let new_timestamp = std::cmp::max(previous_claim.1, claim.1);

        updated_claims.insert(*slot, (total_claimed_for_distribution_slot, new_timestamp));
    }
    Ok(updated_claims)
}

/// Validates the contract version and name. To be taken from mantra-std in the future, for now,
/// it's duplicated from MANTRA-dex.
#[macro_export]
macro_rules! validate_contract {
    ($deps:expr, $contract_name:expr, $contract_version:expr) => {{
        let stored_contract_name = cw2::CONTRACT.load($deps.storage)?.contract;
        cosmwasm_std::ensure!(
            stored_contract_name == $contract_name,
            cosmwasm_std::StdError::generic_err("Contract name mismatch")
        );

        let version: semver::Version = $contract_version.parse()?;
        let storage_version: semver::Version =
            cw2::get_contract_version($deps.storage)?.version.parse()?;

        cosmwasm_std::ensure!(
            storage_version < version,
            ContractError::MigrateInvalidVersion {
                current_version: storage_version,
                new_version: version,
            }
        );
    }};
}
