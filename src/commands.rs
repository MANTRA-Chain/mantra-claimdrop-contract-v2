use std::collections::HashMap;

use cosmwasm_std::{ensure, BankMsg, Coin, DepsMut, Env, Event, MessageInfo, Response, Uint128};

use crate::helpers::{self, validate_raw_address};
use crate::state::{
    assert_authorized, get_allocation, get_claims_for_address, is_authorized, is_blacklisted,
    Claim, DistributionSlot, ALLOCATIONS, AUTHORIZED_WALLETS, BLACKLIST, CAMPAIGN, CLAIMS,
};
use mantra_claimdrop_std::error::ContractError;
use mantra_claimdrop_std::msg::{Campaign, CampaignAction, CampaignParams, DistributionType};

/// Maximum number of allocations that can be added in a single batch
pub const MAX_ALLOCATION_BATCH_SIZE: usize = 3000;

/// Maximum number of authorized wallets that can be managed in a single batch operation
pub const MAX_AUTHORIZED_WALLETS_BATCH_SIZE: usize = 1000;

/// Manages a campaign
pub(crate) fn manage_campaign(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    campaign_action: CampaignAction,
) -> Result<Response, ContractError> {
    assert_authorized(deps.as_ref(), &info.sender)?;

    match campaign_action {
        CampaignAction::CreateCampaign { params } => create_campaign(deps, env, info, *params),
        CampaignAction::CloseCampaign {} => {
            cw_utils::nonpayable(&info)?;
            close_campaign(deps, env)
        }
    }
}

/// Creates a new airdrop campaign.
fn create_campaign(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    campaign_params: CampaignParams,
) -> Result<Response, ContractError> {
    cw_utils::nonpayable(&info)?;
    let campaign: Option<Campaign> = CAMPAIGN.may_load(deps.storage)?;

    ensure!(
        campaign.is_none(),
        ContractError::CampaignError {
            reason: "existing campaign".to_string()
        }
    );

    helpers::validate_campaign_params(env.block.time, &campaign_params)?;

    let campaign = Campaign::from_params(campaign_params);
    CAMPAIGN.save(deps.storage, &campaign)?;

    Ok(Response::default().add_attributes(vec![
        ("action", "create_campaign".to_string()),
        ("campaign", campaign.to_string()),
    ]))
}

/// Closes the existing airdrop campaign. Only the owner can end the campaign.
/// The remaining funds in the campaign are refunded to the owner.
fn close_campaign(deps: DepsMut, env: Env) -> Result<Response, ContractError> {
    let mut campaign = CAMPAIGN
        .may_load(deps.storage)?
        .ok_or(ContractError::CampaignError {
            reason: "there's not an active campaign".to_string(),
        })?;

    ensure!(
        campaign.closed.is_none(),
        ContractError::CampaignError {
            reason: "campaign has already been closed".to_string()
        }
    );

    let refund: Coin = deps
        .querier
        .query_balance(env.contract.address, &campaign.total_reward.denom)?;

    let mut messages = vec![];

    if !refund.amount.is_zero() {
        let owner = cw_ownable::get_ownership(deps.storage)?.owner.unwrap();

        messages.push(BankMsg::Send {
            to_address: owner.to_string(),
            amount: vec![refund.clone()],
        });
    }

    campaign.closed = Some(env.block.time.seconds());

    CAMPAIGN.save(deps.storage, &campaign)?;

    Ok(Response::default()
        .add_messages(messages)
        .add_attributes(vec![
            ("action", "close_campaign".to_string()),
            ("campaign", campaign.to_string()),
            ("refund", refund.to_string()),
        ]))
}

/// Sweep recovers non-reward tokens accidentally sent to the contract.
/// This prevents permanent loss of user funds while protecting campaign assets.
///
/// # Security
/// - Owner-only operation via `cw_ownable::assert_owner`
/// - Cannot sweep campaign reward tokens (must use CloseCampaign instead)
/// - Validates amounts and balances before sweeping
/// - Works whether campaign exists or not
///
/// # Arguments
/// * `deps` - Dependencies for storage and querier access
/// * `env` - Environment information including contract address
/// * `info` - Message info containing sender (must be owner)
/// * `denom` - The token denomination to sweep
/// * `amount` - Optional amount to sweep (None = sweep entire balance)
pub(crate) fn sweep(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    denom: String,
    amount: Option<Uint128>,
) -> Result<Response, ContractError> {
    // Only owner can sweep tokens
    cw_ownable::assert_owner(deps.storage, &info.sender)?;

    // Get the campaign if it exists to check reward denom
    let campaign = CAMPAIGN.may_load(deps.storage)?;

    // Prevent sweeping the reward denom if a campaign exists
    if let Some(campaign) = campaign {
        ensure!(
            denom != campaign.total_reward.denom,
            ContractError::CampaignError {
                reason: format!(
                    "Cannot sweep reward denom '{}'. Use CloseCampaign instead",
                    campaign.total_reward.denom
                )
            }
        );
    }

    // Query the balance of the specified denom
    let balance = deps.querier.query_balance(&env.contract.address, &denom)?;

    // Determine the amount to sweep
    let sweep_amount = match amount {
        Some(amt) => {
            ensure!(
                amt <= balance.amount,
                ContractError::InvalidCampaignParam {
                    param: "amount".to_string(),
                    reason: format!(
                        "Requested amount {} exceeds available balance {}",
                        amt, balance.amount
                    )
                }
            );
            amt
        }
        None => balance.amount,
    };

    // Check if there's anything to sweep
    ensure!(
        !sweep_amount.is_zero(),
        ContractError::CampaignError {
            reason: format!("No {denom} tokens to sweep")
        }
    );

    // Get the owner address
    let owner = cw_ownable::get_ownership(deps.storage)?.owner.unwrap();

    // Create the bank send message
    let send_msg = BankMsg::Send {
        to_address: owner.to_string(),
        amount: vec![Coin {
            denom: denom.clone(),
            amount: sweep_amount,
        }],
    };

    // Create a custom event for better indexing
    let sweep_event = Event::new("sweep_tokens")
        .add_attribute("denom", &denom)
        .add_attribute("amount", sweep_amount.to_string())
        .add_attribute("recipient", owner.as_ref());

    Ok(Response::new()
        .add_message(send_msg)
        .add_event(sweep_event)
        .add_attributes(vec![
            ("action", "sweep"),
            ("denom", &denom),
            ("amount", &sweep_amount.to_string()),
            ("recipient", owner.as_ref()),
        ]))
}

pub(crate) fn claim(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    receiver: Option<String>,
    amount: Option<Uint128>,
) -> Result<Response, ContractError> {
    let mut campaign = CAMPAIGN
        .may_load(deps.storage)?
        .ok_or(ContractError::CampaignError {
            reason: "there's not an active campaign".to_string(),
        })?;

    ensure!(
        campaign.has_started(&env.block.time),
        ContractError::CampaignError {
            reason: "not started".to_string()
        }
    );

    ensure!(
        campaign.closed.is_none(),
        ContractError::CampaignError {
            reason: "has been closed, cannot claim".to_string()
        }
    );

    // Note: Campaign end_time is intentionally not checked here.
    // Users should be able to claim their allocated tokens even after the campaign end_time has passed,
    // as long as the campaign has not been manually closed by the owner.

    let receiver = receiver
        .map(|addr| deps.api.addr_validate(&addr))
        .transpose()?
        .unwrap_or_else(|| info.sender.clone());

    // Check if the caller is authorized to claim:
    // Owner, authorized wallet, OR the wallet with the allocation can claim
    let is_authorized_user = is_authorized(deps.as_ref(), &info.sender)?;

    ensure!(
        is_authorized_user || info.sender == receiver,
        ContractError::Unauthorized
    );

    ensure!(
        !is_blacklisted(deps.as_ref(), receiver.as_ref())?,
        ContractError::AddressBlacklisted
    );

    // Get allocation for the address
    let total_user_allocation = get_allocation(deps.as_ref(), receiver.as_ref())?.ok_or(
        ContractError::NoAllocationFound {
            address: receiver.to_string(),
        },
    )?;

    // new_claims is HashMap<DistributionSlot, Claim=(amount, timestamp)> representing newly available amounts per slot
    let (max_claimable_amount_coin, new_claims, previous_claims) =
        helpers::compute_claimable_amount(
            deps.as_ref(),
            &campaign,
            &env.block.time,
            receiver.as_ref(),
            total_user_allocation,
        )?;

    let actual_claim_amount_coin = match amount {
        Some(requested_amount) => {
            ensure!(
                requested_amount > Uint128::zero(),
                ContractError::InvalidClaimAmount {
                    reason: "amount must be greater than zero".to_string()
                }
            );
            ensure!(
                requested_amount <= max_claimable_amount_coin.amount,
                ContractError::InvalidClaimAmount {
                    reason: format!(
                        "requested amount {} exceeds available claimable amount {}",
                        requested_amount, max_claimable_amount_coin.amount
                    )
                }
            );
            Coin {
                denom: campaign.total_reward.denom.clone(),
                amount: requested_amount,
            }
        }
        None => max_claimable_amount_coin,
    };

    ensure!(
        actual_claim_amount_coin.amount > Uint128::zero(),
        ContractError::NothingToClaim
    );

    let available_funds = deps
        .querier
        .query_balance(env.contract.address, &campaign.total_reward.denom)?;

    ensure!(
        actual_claim_amount_coin.amount <= available_funds.amount,
        ContractError::CampaignError {
            reason: "no funds available to claim".to_string()
        }
    );

    let mut claims_to_record: HashMap<DistributionSlot, Claim> = HashMap::new();
    let mut remaining_to_distribute = actual_claim_amount_coin.amount;

    // remaining_to_distribute is guaranteed to be > 0 from earlier validation
    let mut lump_sum_slots_with_new_claims: Vec<DistributionSlot> = vec![];
    let mut linear_vesting_slots_with_new_claims: Vec<DistributionSlot> = vec![];

    for (idx, dist_type) in campaign.distribution_type.iter().enumerate() {
        if new_claims.contains_key(&idx) {
            // Only consider slots that have new claimable amounts
            match dist_type {
                DistributionType::LumpSum { .. } => lump_sum_slots_with_new_claims.push(idx),
                DistributionType::LinearVesting { .. } => {
                    linear_vesting_slots_with_new_claims.push(idx)
                }
            }
        }
    }

    lump_sum_slots_with_new_claims.sort();
    linear_vesting_slots_with_new_claims.sort();

    // Helper function to distribute tokens to a list of slots
    let distribute_to_slots =
        |slots: Vec<DistributionSlot>,
         remaining: &mut Uint128,
         claims: &mut HashMap<DistributionSlot, Claim>| {
            for slot_idx in slots {
                if *remaining == Uint128::zero() {
                    break;
                }
                // new_claims.get(&slot_idx) is guaranteed to return Some since slot_idx comes from slots with new claims
                let (available_from_slot, _) = new_claims
                    .get(&slot_idx)
                    .expect("slot_idx must exist in new_claims");
                let take_from_slot = std::cmp::min(*remaining, *available_from_slot);
                if take_from_slot > Uint128::zero() {
                    claims.insert(slot_idx, (take_from_slot, env.block.time.seconds()));
                    *remaining = remaining.saturating_sub(take_from_slot);
                }
            }
        };

    // Phase 1: Distribute to LumpSum slots from new_claims
    distribute_to_slots(
        lump_sum_slots_with_new_claims,
        &mut remaining_to_distribute,
        &mut claims_to_record,
    );

    // Phase 2: Distribute remaining to LinearVesting slots from new_claims
    distribute_to_slots(
        linear_vesting_slots_with_new_claims,
        &mut remaining_to_distribute,
        &mut claims_to_record,
    );

    // Enforce the invariant that all requested tokens have been distributed
    ensure!(
        remaining_to_distribute == Uint128::zero(),
        ContractError::CampaignError {
            reason: format!(
                "Distribution error: {remaining_to_distribute} tokens remain undistributed. This indicates a bug in the claimable amount calculation."
            )
        }
    );

    let updated_claims = helpers::aggregate_claims(&previous_claims, &claims_to_record)?;

    campaign.claimed.amount = campaign
        .claimed
        .amount
        .checked_add(actual_claim_amount_coin.amount)?;

    CAMPAIGN.save(deps.storage, &campaign)?;
    CLAIMS.save(deps.storage, receiver.to_string(), &updated_claims)?;

    // Calculate total claims from updated_claims instead of making another storage call
    let total_claimed = updated_claims
        .iter()
        .fold(Uint128::zero(), |acc, (_, (amount, _))| {
            acc.checked_add(*amount).unwrap()
        });

    ensure!(
        total_user_allocation >= total_claimed,
        ContractError::ExceededMaxClaimAmount
    );

    Ok(Response::default()
        .add_message(BankMsg::Send {
            to_address: receiver.to_string(),
            amount: vec![actual_claim_amount_coin.clone()],
        })
        .add_attributes(vec![
            ("action", "claim".to_string()),
            ("receiver", receiver.to_string()),
            ("claimed_amount", actual_claim_amount_coin.to_string()),
        ]))
}

/// Adds a batch of addresses and their allocations. This can only be done before the campaign has started.
///
/// # Arguments
/// * `deps` - The dependencies
/// * `env`  - The env context
/// * `info` - The message info
/// * `allocations` - Vector of (address, amount) pairs
///
/// # Returns
/// * `Result<Response, ContractError>` - The response with attributes
pub fn add_allocations(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    allocations: Vec<(String, Uint128)>,
) -> Result<Response, ContractError> {
    assert_authorized(deps.as_ref(), &info.sender)?;

    // Check batch size limit
    ensure!(
        allocations.len() <= MAX_ALLOCATION_BATCH_SIZE,
        ContractError::BatchSizeLimitExceeded {
            actual: allocations.len(),
            max: MAX_ALLOCATION_BATCH_SIZE,
        }
    );

    // Check if campaign has started
    let campaign = CAMPAIGN.may_load(deps.storage)?;

    if let Some(campaign) = campaign {
        ensure!(
            !campaign.has_started(&env.block.time),
            ContractError::CampaignError {
                reason: "cannot upload allocations after campaign has started".to_string(),
            }
        );
    }

    let allocations_len = allocations.len().to_string();

    for (address_raw, amount) in allocations.into_iter() {
        let validated_receiver_string = validate_raw_address(deps.as_ref(), &address_raw)?;

        ensure!(
            !ALLOCATIONS.has(deps.storage, validated_receiver_string.as_str()),
            ContractError::AllocationAlreadyExists {
                address: validated_receiver_string.clone(),
            }
        );
        ALLOCATIONS.save(deps.storage, validated_receiver_string.as_str(), &amount)?;
    }

    Ok(Response::default()
        .add_attribute("action", "add_allocations")
        .add_attribute("count", allocations_len))
}

/// Replaces an address in the allocation list. This can be done at any time during the campaign.
///
/// # Arguments
/// * `deps` - The dependencies
/// * `info` - The message info
/// * `old_address` - The old address to replace
/// * `new_address` - The new address to use
///
/// # Returns
/// * `Result<Response, ContractError>` - The response with attributes
pub fn replace_address(
    deps: DepsMut,
    info: MessageInfo,
    old_address_raw: String,
    new_address_raw: String,
) -> Result<Response, ContractError> {
    assert_authorized(deps.as_ref(), &info.sender)?;

    let old_address_canonical = validate_raw_address(deps.as_ref(), &old_address_raw)?;
    // New address should be a valid cosmos address
    let new_address_validated = deps.api.addr_validate(&new_address_raw)?;

    let old_allocation = ALLOCATIONS
        .may_load(deps.storage, old_address_canonical.as_str())?
        .ok_or(ContractError::NoAllocationFound {
            address: old_address_raw.clone(),
        })?;

    // Ensure the new address doesn't have an allocation already
    ensure!(
        !ALLOCATIONS.has(deps.storage, new_address_validated.as_str()),
        ContractError::AllocationAlreadyExists {
            address: new_address_raw.clone()
        }
    );
    ALLOCATIONS.remove(deps.storage, old_address_canonical.as_str());
    ALLOCATIONS.save(
        deps.storage,
        new_address_validated.as_str(),
        &old_allocation,
    )?;

    // Update claims and blacklist if the address has claimed rewards or is blacklisted
    let claims = get_claims_for_address(deps.as_ref(), old_address_canonical.clone())?;
    if !claims.is_empty() {
        CLAIMS.remove(deps.storage, old_address_canonical.clone());
        CLAIMS.save(deps.storage, new_address_validated.to_string(), &claims)?;
    }

    if is_blacklisted(deps.as_ref(), old_address_canonical.as_str())? {
        BLACKLIST.remove(deps.storage, old_address_canonical.as_str());
        BLACKLIST.save(deps.storage, new_address_validated.as_str(), &())?;
    }

    Ok(Response::default().add_attributes(vec![
        ("action", "replace_address".to_string()),
        ("old_address", old_address_raw),
        ("new_address", new_address_raw),
    ]))
}

/// Removes an address from the allocation list. This can only be done before the campaign has started.
/// Trying to remove an address that doesn't exist in the list won't result in an error.
///
/// # Arguments
/// * `deps` - The dependencies
/// * `env`  - The env context
/// * `info` - The message info
/// * `address` - The address to remove
///
/// # Returns
/// * `Result<Response, ContractError>` - The response with attributes
pub fn remove_address(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    address: String,
) -> Result<Response, ContractError> {
    assert_authorized(deps.as_ref(), &info.sender)?;

    // Check if campaign has started
    let campaign = CAMPAIGN.may_load(deps.storage)?;

    if let Some(campaign) = campaign {
        ensure!(
            !campaign.has_started(&env.block.time),
            ContractError::CampaignError {
                reason: "cannot remove an address allocation after campaign has started"
                    .to_string(),
            }
        );
    }

    let address = validate_raw_address(deps.as_ref(), &address)?;

    ALLOCATIONS.remove(deps.storage, address.as_str());

    // Also remove the blacklist entry when removing the address to maintain consistency
    // This ensures blacklist doesn't persist for addresses that are no longer in the protocol
    BLACKLIST.remove(deps.storage, address.as_str());

    Ok(Response::default()
        .add_attribute("action", "remove_address")
        .add_attribute("removed", address))
}

/// Blacklists or unblacklists an address. This can be done at any time.
///
/// # Arguments
/// * `deps` - The dependencies
/// * `info` - The message info
/// * `address` - The address to blacklist/unblacklist
/// * `blacklist` - Whether to blacklist or unblacklist
///
/// # Returns
/// * `Result<Response, ContractError>` - The response with attributes
pub fn blacklist_address(
    deps: DepsMut,
    info: MessageInfo,
    address: String,
    blacklist: bool,
) -> Result<Response, ContractError> {
    assert_authorized(deps.as_ref(), &info.sender)?;

    let address = validate_raw_address(deps.as_ref(), &address)?;

    // Prevent blacklisting the owner
    let ownership = cw_ownable::get_ownership(deps.storage)?;
    if let Some(owner) = ownership.owner {
        ensure!(
            owner.to_string() != address,
            ContractError::CampaignError {
                reason: "Cannot blacklist the campaign owner".to_string(),
            }
        );
    }

    if blacklist {
        BLACKLIST.save(deps.storage, address.as_str(), &())?;
    } else {
        BLACKLIST.remove(deps.storage, address.as_str());
    }

    Ok(Response::default()
        .add_attribute("action", "blacklist_address".to_string())
        .add_attribute("address", address)
        .add_attribute("blacklisted", blacklist.to_string()))
}

/// Manages authorized wallets that can perform admin actions. Only the owner can manage the authorized wallets list.
///
/// # Arguments
/// * `deps` - The dependencies
/// * `info` - The message info
/// * `addresses` - Vector of addresses to authorize/unauthorize
/// * `authorized` - Whether to authorize or unauthorize the addresses
///
/// # Returns
/// * `Result<Response, ContractError>` - The response with attributes
pub fn manage_authorized_wallets(
    deps: DepsMut,
    info: MessageInfo,
    addresses: Vec<String>,
    authorized: bool,
) -> Result<Response, ContractError> {
    // Only owner can manage authorized wallets
    cw_ownable::assert_owner(deps.storage, &info.sender)?;

    // Check batch size limit
    ensure!(
        addresses.len() <= MAX_AUTHORIZED_WALLETS_BATCH_SIZE,
        ContractError::BatchSizeLimitExceeded {
            actual: addresses.len(),
            max: MAX_AUTHORIZED_WALLETS_BATCH_SIZE,
        }
    );

    ensure!(
        !addresses.is_empty(),
        ContractError::InvalidInput {
            reason: "addresses cannot be empty".to_string(),
        }
    );

    for address in addresses.iter() {
        let validated_address = deps.api.addr_validate(address)?;

        if authorized {
            AUTHORIZED_WALLETS.save(deps.storage, validated_address.as_str(), &())?;
        } else {
            AUTHORIZED_WALLETS.remove(deps.storage, validated_address.as_str());
        }
    }

    Ok(Response::default().add_attributes(vec![
        ("action", "manage_authorized_wallets".to_string()),
        ("count", addresses.len().to_string()),
        ("authorized", authorized.to_string()),
    ]))
}
