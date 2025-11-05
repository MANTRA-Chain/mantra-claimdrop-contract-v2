use claimdrop_contract::commands::{add_allocations, blacklist_address, manage_authorized_wallets};
use claimdrop_contract::queries::{query_authorized_wallets, query_is_authorized};
use claimdrop_contract::state::{assert_authorized, is_authorized};
use cosmwasm_std::{
    coins,
    testing::{mock_dependencies, mock_env},
    MessageInfo, Uint128,
};

use mantra_claimdrop_std::error::ContractError;

/// Test that the owner can add authorized wallets
#[test]
fn owner_can_add_authorized_wallet() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");
    let authorized_addr = deps.api.addr_make("authorized");

    // Initialize owner in storage
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let info = MessageInfo {
        sender: owner.clone(),
        funds: vec![],
    };

    // Test adding authorized wallet
    let result =
        manage_authorized_wallets(deps.as_mut(), info, vec![authorized_addr.to_string()], true);

    assert!(result.is_ok());
    let response = result.unwrap();

    // Check attributes
    let attributes = response.attributes;
    assert_eq!(attributes[0].key, "action");
    assert_eq!(attributes[0].value, "manage_authorized_wallets");
    assert_eq!(attributes[1].key, "count");
    assert_eq!(attributes[1].value, "1");
    assert_eq!(attributes[2].key, "authorized");
    assert_eq!(attributes[2].value, "true");

    // Verify the wallet is now authorized
    let is_authorized_result = is_authorized(deps.as_ref(), &authorized_addr);
    assert!(is_authorized_result.is_ok());
    assert!(is_authorized_result.unwrap());
}

/// Test that the owner can remove authorized wallets
#[test]
fn owner_can_remove_authorized_wallet() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");
    let authorized_addr = deps.api.addr_make("authorized");

    // Initialize owner in storage
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let info = MessageInfo {
        sender: owner.clone(),
        funds: vec![],
    };

    // First add the wallet
    let result = manage_authorized_wallets(
        deps.as_mut(),
        info.clone(),
        vec![authorized_addr.to_string()],
        true,
    );
    assert!(result.is_ok());

    // Verify it's authorized
    assert!(is_authorized(deps.as_ref(), &authorized_addr).unwrap());

    // Now remove it
    let result = manage_authorized_wallets(
        deps.as_mut(),
        info,
        vec![authorized_addr.to_string()],
        false,
    );
    assert!(result.is_ok());

    let response = result.unwrap();
    assert_eq!(response.attributes[2].value, "false");

    // Verify it's no longer authorized (but owner still is)
    assert!(!is_authorized(deps.as_ref(), &authorized_addr).unwrap());
    assert!(is_authorized(deps.as_ref(), &owner).unwrap());
}

/// Test that non-owners cannot manage authorized wallets
#[test]
fn unauthorized_cannot_manage_wallets() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");
    let unauthorized = deps.api.addr_make("unauthorized");
    let target_addr = deps.api.addr_make("target");

    // Initialize owner in storage
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let info = MessageInfo {
        sender: unauthorized,
        funds: vec![],
    };

    // Try to add authorized wallet as non-owner
    let result =
        manage_authorized_wallets(deps.as_mut(), info, vec![target_addr.to_string()], true);

    // Should fail with owner check error
    assert!(result.is_err());
}

/// Test that authorized wallets can perform admin actions
#[test]
fn authorized_wallet_can_perform_admin_actions() {
    let mut deps = mock_dependencies();
    let env = mock_env();
    let owner = deps.api.addr_make("owner");
    let authorized_addr = deps.api.addr_make("authorized");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    // Add authorized wallet
    let owner_info = MessageInfo {
        sender: owner,
        funds: vec![],
    };
    manage_authorized_wallets(
        deps.as_mut(),
        owner_info,
        vec![authorized_addr.to_string()],
        true,
    )
    .unwrap();

    // Test that authorized wallet can add allocations
    let authorized_info = MessageInfo {
        sender: authorized_addr.clone(),
        funds: vec![],
    };
    let allocations = vec![("mantra1test123".to_string(), Uint128::new(1000))];

    let result = add_allocations(deps.as_mut(), env, authorized_info.clone(), allocations);
    assert!(result.is_ok());

    // Test that authorized wallet can blacklist addresses
    let result = blacklist_address(
        deps.as_mut(),
        authorized_info,
        "mantra1test456".to_string(),
        true,
    );
    assert!(result.is_ok());
}

/// Test that unauthorized wallets cannot perform admin actions
#[test]
fn unauthorized_wallet_cannot_perform_admin_actions() {
    let mut deps = mock_dependencies();
    let env = mock_env();
    let owner = deps.api.addr_make("owner");
    let unauthorized_addr = deps.api.addr_make("unauthorized");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    // Test that unauthorized wallet cannot add allocations
    let unauthorized_info = MessageInfo {
        sender: unauthorized_addr.clone(),
        funds: vec![],
    };
    let allocations = vec![("mantra1test123".to_string(), Uint128::new(1000))];

    let result = add_allocations(deps.as_mut(), env, unauthorized_info.clone(), allocations);
    assert!(result.is_err());
    // Should fail with ownership error (since assert_authorized uses cw_ownable)
    assert!(result.is_err());

    // Test that unauthorized wallet cannot blacklist addresses
    let result = blacklist_address(
        deps.as_mut(),
        unauthorized_info,
        "mantra1test456".to_string(),
        true,
    );
    assert!(result.is_err());
    // Should fail with ownership error (since assert_authorized uses cw_ownable)
    assert!(result.is_err());
}

/// Test the assert_authorized helper function
#[test]
fn test_assert_authorized_function() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");
    let authorized_addr = deps.api.addr_make("authorized");
    let unauthorized_addr = deps.api.addr_make("unauthorized");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    // Add authorized wallet
    let owner_info = MessageInfo {
        sender: owner.clone(),
        funds: vec![],
    };
    manage_authorized_wallets(
        deps.as_mut(),
        owner_info,
        vec![authorized_addr.to_string()],
        true,
    )
    .unwrap();

    // Owner should pass
    let result = assert_authorized(deps.as_ref(), &owner);
    assert!(result.is_ok());

    // Authorized wallet should pass
    let result = assert_authorized(deps.as_ref(), &authorized_addr);
    assert!(result.is_ok());

    // Unauthorized wallet should fail
    let result = assert_authorized(deps.as_ref(), &unauthorized_addr);
    assert!(result.is_err());
    // Should fail with ownership error (since assert_authorized uses cw_ownable)
    assert!(result.is_err());
}

/// Test the query functions for authorized wallets
#[test]
fn test_query_authorized_functions() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");
    let authorized_addr1 = deps.api.addr_make("authorized1");
    let authorized_addr2 = deps.api.addr_make("authorized2");
    let unauthorized_addr = deps.api.addr_make("unauthorized");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let owner_info = MessageInfo {
        sender: owner.clone(),
        funds: vec![],
    };

    // Add two authorized wallets
    manage_authorized_wallets(
        deps.as_mut(),
        owner_info.clone(),
        vec![authorized_addr1.to_string()],
        true,
    )
    .unwrap();

    manage_authorized_wallets(
        deps.as_mut(),
        owner_info,
        vec![authorized_addr2.to_string()],
        true,
    )
    .unwrap();

    // Test query_is_authorized
    let result = query_is_authorized(deps.as_ref(), owner.to_string());
    assert!(result.is_ok());
    assert!(result.unwrap().is_authorized);

    let result = query_is_authorized(deps.as_ref(), authorized_addr1.to_string());
    assert!(result.is_ok());
    assert!(result.unwrap().is_authorized);

    let result = query_is_authorized(deps.as_ref(), unauthorized_addr.to_string());
    assert!(result.is_ok());
    assert!(!result.unwrap().is_authorized);

    // Test query_authorized_wallets
    let result = query_authorized_wallets(deps.as_ref(), None, None);
    assert!(result.is_ok());
    let wallets = result.unwrap().wallets;
    assert_eq!(wallets.len(), 2);
    assert!(wallets.contains(&authorized_addr1.to_string()));
    assert!(wallets.contains(&authorized_addr2.to_string()));

    // Test with limit
    let result = query_authorized_wallets(deps.as_ref(), None, Some(1));
    assert!(result.is_ok());
    let wallets = result.unwrap().wallets;
    assert_eq!(wallets.len(), 1);
}

/// Test that the contract owner remains an admin even without being in authorized wallets
#[test]
fn owner_always_admin() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    // Owner should be admin even without being explicitly added to authorized wallets
    assert!(is_authorized(deps.as_ref(), &owner).unwrap());

    // Owner should pass assert_authorized
    assert!(assert_authorized(deps.as_ref(), &owner).is_ok());

    // Owner should appear as authorized in query
    let result = query_is_authorized(deps.as_ref(), owner.to_string());
    assert!(result.is_ok());
    assert!(result.unwrap().is_authorized);
}

/// Test edge cases for managing authorized wallets
#[test]
fn test_edge_cases() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");
    let target_addr = deps.api.addr_make("target");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();
    let owner_info = MessageInfo {
        sender: owner,
        funds: vec![],
    };

    // Test adding the same wallet twice
    manage_authorized_wallets(
        deps.as_mut(),
        owner_info.clone(),
        vec![target_addr.to_string()],
        true,
    )
    .unwrap();

    let result = manage_authorized_wallets(
        deps.as_mut(),
        owner_info.clone(),
        vec![target_addr.to_string()],
        true,
    );
    assert!(result.is_ok()); // Should not error

    // Test removing non-existent wallet
    let nonexistent_addr = deps.api.addr_make("nonexistent");
    let result = manage_authorized_wallets(
        deps.as_mut(),
        owner_info,
        vec![nonexistent_addr.to_string()],
        false,
    );
    assert!(result.is_ok()); // Should not error

    // Verify original wallet is still authorized
    assert!(is_authorized(deps.as_ref(), &target_addr).unwrap());
}

/// Test that ExecuteMsg rejects payments correctly (should reject payments)
#[test]
fn test_nonpayable_enforcement() {
    use claimdrop_contract::contract::execute;
    use mantra_claimdrop_std::msg::ExecuteMsg;

    let mut deps = mock_dependencies();
    let env = mock_env();
    let owner = deps.api.addr_make("owner");
    let target_addr = deps.api.addr_make("target");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    // Try to send funds with the ExecuteMsg::ManageAuthorizedWallets call
    let owner_info = MessageInfo {
        sender: owner,
        funds: coins(100, "uom"),
    };

    let msg = ExecuteMsg::ManageAuthorizedWallets {
        addresses: vec![target_addr.to_string()],
        authorized: true,
    };

    let result = execute(deps.as_mut(), env, owner_info, msg);

    // Should fail due to nonpayable check in contract.rs
    assert!(result.is_err());
}

/// Test batch authorization of multiple wallets
#[test]
fn test_batch_authorize_multiple_wallets() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");
    let addr1 = deps.api.addr_make("addr1");
    let addr2 = deps.api.addr_make("addr2");
    let addr3 = deps.api.addr_make("addr3");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let owner_info = MessageInfo {
        sender: owner.clone(),
        funds: vec![],
    };

    // Authorize multiple wallets in one batch
    let result = manage_authorized_wallets(
        deps.as_mut(),
        owner_info,
        vec![addr1.to_string(), addr2.to_string(), addr3.to_string()],
        true,
    );
    assert!(result.is_ok());

    let response = result.unwrap();
    assert_eq!(response.attributes[1].value, "3"); // Count should be 3
    assert_eq!(response.attributes[2].value, "true");

    // Verify all wallets are authorized
    assert!(is_authorized(deps.as_ref(), &addr1).unwrap());
    assert!(is_authorized(deps.as_ref(), &addr2).unwrap());
    assert!(is_authorized(deps.as_ref(), &addr3).unwrap());
}

/// Test batch unauthorized removal of multiple wallets
#[test]
fn test_batch_unauthorize_multiple_wallets() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");
    let addr1 = deps.api.addr_make("addr1");
    let addr2 = deps.api.addr_make("addr2");
    let addr3 = deps.api.addr_make("addr3");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let owner_info = MessageInfo {
        sender: owner.clone(),
        funds: vec![],
    };

    // First authorize all wallets
    manage_authorized_wallets(
        deps.as_mut(),
        owner_info.clone(),
        vec![addr1.to_string(), addr2.to_string(), addr3.to_string()],
        true,
    )
    .unwrap();

    // Then remove them all in one batch
    let result = manage_authorized_wallets(
        deps.as_mut(),
        owner_info,
        vec![addr1.to_string(), addr2.to_string(), addr3.to_string()],
        false,
    );
    assert!(result.is_ok());

    let response = result.unwrap();
    assert_eq!(response.attributes[1].value, "3");
    assert_eq!(response.attributes[2].value, "false");

    // Verify all wallets are no longer authorized
    assert!(!is_authorized(deps.as_ref(), &addr1).unwrap());
    assert!(!is_authorized(deps.as_ref(), &addr2).unwrap());
    assert!(!is_authorized(deps.as_ref(), &addr3).unwrap());
}

/// Test that batch operation fails if any address is invalid
#[test]
fn test_batch_fails_with_invalid_address() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let owner_info = MessageInfo {
        sender: owner,
        funds: vec![],
    };

    // Try to authorize addresses with one invalid address
    let valid_addr1 = deps.api.addr_make("validaddr1");
    let valid_addr3 = deps.api.addr_make("validaddr3");

    assert!(!is_authorized(deps.as_ref(), &valid_addr1).unwrap());
    assert!(!is_authorized(deps.as_ref(), &valid_addr3).unwrap());

    let result = manage_authorized_wallets(
        deps.as_mut(),
        owner_info,
        vec![
            valid_addr1.to_string(),
            "".to_string(), // Empty address should fail validation
            valid_addr3.to_string(),
        ],
        true,
    );

    assert!(result.is_err());
}

/// Test empty address list fails
#[test]
fn test_empty_address_list_fails() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let owner_info = MessageInfo {
        sender: owner,
        funds: vec![],
    };

    // Try to authorize empty list
    let result = manage_authorized_wallets(deps.as_mut(), owner_info, vec![], true);

    // Should fail with InvalidInput error
    assert!(result.is_err());
    match result.unwrap_err() {
        ContractError::InvalidInput { .. } => {}
        err => panic!("Expected ContractError::InvalidInput, got: {err:?}"),
    }
}

/// Test batch size limit
#[test]
fn test_batch_size_limit() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let owner_info = MessageInfo {
        sender: owner,
        funds: vec![],
    };

    // Create a batch that exceeds the limit (1000)
    let large_batch: Vec<String> = (0..1001)
        .map(|i| deps.api.addr_make(&format!("addr{i:04}")).to_string())
        .collect();

    let result = manage_authorized_wallets(deps.as_mut(), owner_info, large_batch, true);

    // Should fail with BatchSizeLimitExceeded error
    assert!(result.is_err());
    match result.unwrap_err() {
        ContractError::BatchSizeLimitExceeded { actual, max } => {
            assert_eq!(actual, 1001);
            assert_eq!(max, 1000);
        }
        err => panic!("Expected ContractError::BatchSizeLimitExceeded, got: {err:?}"),
    }
}

/// Test pagination for authorized wallets query
#[test]
fn test_authorized_wallets_pagination() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let owner_info = MessageInfo {
        sender: owner.clone(),
        funds: vec![],
    };

    // Authorize 5 wallets
    let addresses: Vec<String> = (1..=5)
        .map(|i| deps.api.addr_make(&format!("addr{i:03}")).to_string())
        .collect();

    manage_authorized_wallets(deps.as_mut(), owner_info, addresses.clone(), true).unwrap();

    // Test query without pagination (should return all)
    let result = query_authorized_wallets(deps.as_ref(), None, None);
    assert!(result.is_ok());
    let response = result.unwrap();
    assert_eq!(response.wallets.len(), 5);

    // Test query with limit
    let result = query_authorized_wallets(deps.as_ref(), None, Some(3));
    assert!(result.is_ok());
    let response = result.unwrap();
    assert_eq!(response.wallets.len(), 3);

    // Test query with start_after (pagination)
    let start_after_addr = deps.api.addr_make("addr002").to_string();
    let result = query_authorized_wallets(deps.as_ref(), Some(start_after_addr), Some(2));
    assert!(result.is_ok());
    let response = result.unwrap();
    assert_eq!(response.wallets.len(), 2);

    // Test query with start_after beyond last element
    // Use a string that will definitely be after all other addresses when sorted
    let beyond_addr = "zzz9999";
    let result = query_authorized_wallets(deps.as_ref(), Some(beyond_addr.to_string()), None);
    assert!(result.is_ok());
    let response = result.unwrap();
    assert_eq!(response.wallets.len(), 0);
}

/// Test pagination with large limit
#[test]
fn test_authorized_wallets_pagination_large_limit() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let owner_info = MessageInfo {
        sender: owner.clone(),
        funds: vec![],
    };

    // Authorize 10 wallets
    let addresses: Vec<String> = (1..=10)
        .map(|i| deps.api.addr_make(&format!("addr{i:03}")).to_string())
        .collect();

    manage_authorized_wallets(deps.as_mut(), owner_info, addresses, true).unwrap();

    // Test query with limit larger than MAX_LIMIT (should be capped)
    let result = query_authorized_wallets(deps.as_ref(), None, Some(10000));
    assert!(result.is_ok());
    let response = result.unwrap();
    assert_eq!(response.wallets.len(), 10); // Should return all 10 wallets
}

/// Test query individual authorization status
#[test]
fn test_query_is_authorized_comprehensive() {
    let mut deps = mock_dependencies();
    let owner = deps.api.addr_make("owner");
    let authorized_addr = deps.api.addr_make("authorized");
    let unauthorized_addr = deps.api.addr_make("unauthorized");

    // Initialize owner
    let deps_api = deps.api;
    cw_ownable::initialize_owner(deps.as_mut().storage, &deps_api, Some(owner.as_str())).unwrap();

    let owner_info = MessageInfo {
        sender: owner.clone(),
        funds: vec![],
    };

    // Authorize one wallet
    manage_authorized_wallets(
        deps.as_mut(),
        owner_info,
        vec![authorized_addr.to_string()],
        true,
    )
    .unwrap();

    // Test owner is authorized
    let result = query_is_authorized(deps.as_ref(), owner.to_string());
    assert!(result.is_ok());
    assert!(result.unwrap().is_authorized);

    // Test authorized wallet is authorized
    let result = query_is_authorized(deps.as_ref(), authorized_addr.to_string());
    assert!(result.is_ok());
    assert!(result.unwrap().is_authorized);

    // Test unauthorized wallet is not authorized
    let result = query_is_authorized(deps.as_ref(), unauthorized_addr.to_string());
    assert!(result.is_ok());
    assert!(!result.unwrap().is_authorized);
}
