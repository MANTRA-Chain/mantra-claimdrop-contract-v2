use cosmwasm_std::{entry_point, to_json_binary};
use cosmwasm_std::{Binary, Deps, DepsMut, Env, MessageInfo, Response};
use cw2::set_contract_version;

use crate::{commands, queries, validate_contract};
use mantra_claimdrop_std::error::ContractError;
use mantra_claimdrop_std::msg::{ExecuteMsg, InstantiateMsg, MigrateMsg, QueryMsg};

// version info for migration info
const CONTRACT_NAME: &str = "mantra_claimdrop-contract";
const CONTRACT_VERSION: &str = env!("CARGO_PKG_VERSION");

#[entry_point]
pub fn instantiate(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    msg: InstantiateMsg,
) -> Result<Response, ContractError> {
    set_contract_version(deps.storage, CONTRACT_NAME, CONTRACT_VERSION)?;

    let owner = match msg.owner {
        Some(owner_str) => deps.api.addr_validate(&owner_str)?,
        None => info.sender.clone(),
    };
    cw_ownable::initialize_owner(deps.storage, deps.api, Some(owner.as_str()))?;

    let mut info = info.clone();
    info.sender = owner.clone();
    let mut response = Response::default()
        .add_attribute("action", "instantiate")
        .add_attribute("owner", owner);

    if let Some(action) = msg.action {
        let campaign_res = commands::manage_campaign(deps, env, info, action)?;
        // Merge the campaign response with the instantiate response
        response = response
            .add_attributes(campaign_res.attributes)
            .add_submessages(campaign_res.messages)
            .add_events(campaign_res.events);

        // Merge data if present (later data overwrites earlier)
        if let Some(data) = campaign_res.data {
            response = response.set_data(data);
        }
    }

    Ok(response)
}

#[entry_point]
pub fn execute(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    msg: ExecuteMsg,
) -> Result<Response, ContractError> {
    match msg {
        ExecuteMsg::ManageCampaign { action } => commands::manage_campaign(deps, env, info, action),
        ExecuteMsg::Claim { receiver, amount } => {
            cw_utils::nonpayable(&info)?;
            commands::claim(deps, env, info, receiver, amount)
        }
        ExecuteMsg::AddAllocations { allocations } => {
            cw_utils::nonpayable(&info)?;
            commands::add_allocations(deps, env, info, allocations)
        }
        ExecuteMsg::ReplaceAddress {
            old_address,
            new_address,
        } => {
            cw_utils::nonpayable(&info)?;
            commands::replace_address(deps, info, old_address, new_address)
        }
        ExecuteMsg::RemoveAddress { address } => {
            cw_utils::nonpayable(&info)?;
            commands::remove_address(deps, env, info, address)
        }
        ExecuteMsg::BlacklistAddress { address, blacklist } => {
            cw_utils::nonpayable(&info)?;
            commands::blacklist_address(deps, info, address, blacklist)
        }
        ExecuteMsg::ManageAuthorizedWallets {
            addresses,
            authorized,
        } => {
            cw_utils::nonpayable(&info)?;
            commands::manage_authorized_wallets(deps, info, addresses, authorized)
        }
        ExecuteMsg::UpdateOwnership(action) => {
            cw_utils::nonpayable(&info)?;
            Ok(
                cw_ownable::update_ownership(deps, &env.block, &info.sender, action).map(
                    |ownership| {
                        Response::default()
                            .add_attribute("action", "update_ownership")
                            .add_attributes(ownership.into_attributes())
                    },
                )?,
            )
        }
    }
}

#[entry_point]
pub fn query(deps: Deps, env: Env, msg: QueryMsg) -> Result<Binary, ContractError> {
    match msg {
        QueryMsg::Campaign {} => Ok(to_json_binary(&queries::query_campaign(deps)?)?),
        QueryMsg::Rewards { receiver } => Ok(to_json_binary(&queries::query_rewards(
            deps, env, receiver,
        )?)?),
        QueryMsg::Ownership {} => Ok(to_json_binary(&cw_ownable::get_ownership(deps.storage)?)?),
        QueryMsg::Claimed {
            address,
            start_from,
            limit,
        } => Ok(to_json_binary(&queries::query_claimed(
            deps, address, start_from, limit,
        )?)?),
        QueryMsg::Allocations {
            address,
            start_after,
            limit,
        } => Ok(to_json_binary(&queries::query_allocation(
            deps,
            address,
            start_after,
            limit,
        )?)?),
        QueryMsg::IsBlacklisted { address } => Ok(to_json_binary(&queries::query_is_blacklisted(
            deps, address,
        )?)?),
        QueryMsg::IsAuthorized { address } => Ok(to_json_binary(&queries::query_is_authorized(
            deps, address,
        )?)?),
        QueryMsg::AuthorizedWallets { start_after, limit } => Ok(to_json_binary(
            &queries::query_authorized_wallets(deps, start_after, limit)?,
        )?),
    }
}

#[entry_point]
pub fn migrate(deps: DepsMut, _env: Env, _msg: MigrateMsg) -> Result<Response, ContractError> {
    validate_contract!(deps, CONTRACT_NAME, CONTRACT_VERSION);
    set_contract_version(deps.storage, CONTRACT_NAME, CONTRACT_VERSION)?;
    Ok(Response::default())
}
