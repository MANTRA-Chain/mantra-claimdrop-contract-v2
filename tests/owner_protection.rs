use cosmwasm_std::{coin, Decimal, Uint128};
use mantra_claimdrop_std::error::ContractError;
use mantra_claimdrop_std::msg::{CampaignAction, CampaignParams, DistributionType};

mod suite;
use suite::TestingSuite;

#[test]
fn test_cannot_blacklist_owner() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let owner = &suite.senders[0].clone();
    let authorized_wallet = &suite.senders[1].clone();
    let other_user = &suite.senders[2].clone();
    let current_time = &suite.get_time();

    // Create a campaign with the owner
    suite
        .instantiate_claimdrop_contract(Some(owner.to_string()))
        .manage_campaign(
            owner,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Campaign".to_string(),
                    description: "Test campaign".to_string(),
                    ty: "airdrop".to_string(),
                    reward_denom: "uom".to_string(),
                    total_reward: coin(10_000_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 86400,
                    }],
                    start_time: current_time.seconds() + 86400,
                    end_time: current_time.seconds() + 86400 * 7,
                }),
            },
            &[],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        )
        // Add authorized wallet
        .manage_authorized_wallets(
            owner,
            vec![authorized_wallet.to_string()],
            true,
            &[],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            owner,
            &[coin(10_000_000, "uom")],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Try to blacklist the owner with authorized wallet - should fail
    suite.blacklist_address(
        authorized_wallet,
        owner,
        true,
        |result: Result<_, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::CampaignError { reason } => {
                    assert_eq!(reason, "Cannot blacklist the campaign owner");
                }
                _ => panic!("Wrong error type, should return ContractError::CampaignError"),
            }
        },
    );

    // Try to blacklist the owner as owner itself - should also fail
    suite.blacklist_address(owner, owner, true, |result: Result<_, anyhow::Error>| {
        let err = result.unwrap_err().downcast::<ContractError>().unwrap();
        match err {
            ContractError::CampaignError { reason } => {
                assert_eq!(reason, "Cannot blacklist the campaign owner");
            }
            _ => panic!("Wrong error type, should return ContractError::CampaignError"),
        }
    });

    // Verify owner is not blacklisted
    suite.query_is_blacklisted(owner, |result| {
        let blacklist_status = result.unwrap();
        assert!(
            !blacklist_status.is_blacklisted,
            "Owner should not be blacklisted"
        );
    });

    // Should be able to blacklist other addresses
    suite.blacklist_address(
        authorized_wallet,
        other_user,
        true,
        |result: Result<_, anyhow::Error>| {
            result.unwrap();
        },
    );

    suite.query_is_blacklisted(other_user, |result| {
        let blacklist_status = result.unwrap();
        assert!(
            blacklist_status.is_blacklisted,
            "Other user should be blacklisted"
        );
    });
}

#[test]
fn test_owner_can_have_allocations_but_cannot_be_blacklisted() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let owner = &suite.senders[0].clone();
    let authorized_wallet = &suite.senders[1].clone();
    let user1 = &suite.senders[2].clone();
    let current_time = &suite.get_time();

    // Create a campaign with the owner
    suite
        .instantiate_claimdrop_contract(Some(owner.to_string()))
        .manage_campaign(
            owner,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Campaign".to_string(),
                    description: "Test campaign".to_string(),
                    ty: "airdrop".to_string(),
                    reward_denom: "uom".to_string(),
                    total_reward: coin(10_000_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 86400,
                    }],
                    start_time: current_time.seconds() + 86400,
                    end_time: current_time.seconds() + 86400 * 7,
                }),
            },
            &[],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        )
        // Add authorized wallet
        .manage_authorized_wallets(
            owner,
            vec![authorized_wallet.to_string()],
            true,
            &[],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            owner,
            &[coin(10_000_000, "uom")],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Owner CAN have allocations (this is allowed)
    suite.add_allocations(
        authorized_wallet,
        &vec![(owner.to_string(), Uint128::from(1000u128))],
        |result: Result<_, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Add allocations for other users too
    suite.add_allocations(
        authorized_wallet,
        &vec![(user1.to_string(), Uint128::from(2000u128))],
        |result: Result<_, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify owner HAS allocation (this is allowed)
    suite.query_allocations(Some(owner), None, None, |result| {
        let allocations = result.unwrap();
        assert_eq!(
            allocations.allocations.len(),
            1,
            "Owner should have allocation"
        );
        assert_eq!(allocations.allocations[0].0, owner.to_string());
        assert_eq!(allocations.allocations[0].1.amount.u128(), 1000);
    });

    // Verify other user has allocation
    suite.query_allocations(Some(user1), None, None, |result| {
        let allocations = result.unwrap();
        assert_eq!(
            allocations.allocations.len(),
            1,
            "User1 should have allocation"
        );
        assert_eq!(allocations.allocations[0].0, user1.to_string());
        assert_eq!(allocations.allocations[0].1.amount.u128(), 2000);
    });

    // The key protection is that the owner CANNOT be blacklisted
    // This ensures they can always claim their allocations
    suite.blacklist_address(
        authorized_wallet,
        owner,
        true,
        |result: Result<_, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::CampaignError { reason } => {
                    assert_eq!(reason, "Cannot blacklist the campaign owner");
                }
                _ => panic!("Wrong error type, should return ContractError::CampaignError"),
            }
        },
    );
}

#[test]
fn test_owner_protection_ensures_owner_can_claim() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let owner = &suite.senders[0].clone();
    let authorized_wallet = &suite.senders[1].clone();
    let user1 = &suite.senders[2].clone();
    let user2 = &suite.senders[3].clone();
    let current_time = &suite.get_time();

    // Create a campaign with the owner
    suite
        .instantiate_claimdrop_contract(Some(owner.to_string()))
        .manage_campaign(
            owner,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Campaign".to_string(),
                    description: "Test campaign".to_string(),
                    ty: "airdrop".to_string(),
                    reward_denom: "uom".to_string(),
                    total_reward: coin(10_000_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 86400,
                    }],
                    start_time: current_time.seconds() + 86400,
                    end_time: current_time.seconds() + 86400 * 7,
                }),
            },
            &[],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        )
        // Add authorized wallet
        .manage_authorized_wallets(
            owner,
            vec![authorized_wallet.to_string()],
            true,
            &[],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            owner,
            &[coin(10_000_000, "uom")],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Add batch allocations that includes the owner - this SHOULD work
    // The protection is that owner cannot be blacklisted, not that they can't have allocations
    suite.add_allocations(
        authorized_wallet,
        &vec![
            (user1.to_string(), Uint128::from(1000u128)),
            (owner.to_string(), Uint128::from(2000u128)), // Owner CAN have allocations
            (user2.to_string(), Uint128::from(1500u128)),
        ],
        |result: Result<_, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify all allocations were added correctly including owner's
    suite.query_allocations(Some(user1), None, None, |result| {
        let allocations = result.unwrap();
        assert_eq!(allocations.allocations.len(), 1);
        assert_eq!(allocations.allocations[0].1.amount.u128(), 1000);
    });

    suite.query_allocations(Some(owner), None, None, |result| {
        let allocations = result.unwrap();
        assert_eq!(allocations.allocations.len(), 1);
        assert_eq!(allocations.allocations[0].1.amount.u128(), 2000);
    });

    suite.query_allocations(Some(user2), None, None, |result| {
        let allocations = result.unwrap();
        assert_eq!(allocations.allocations.len(), 1);
        assert_eq!(allocations.allocations[0].1.amount.u128(), 1500);
    });

    // The protection: even if authorized wallets try to blacklist the owner, they cannot
    // This ensures the owner can always claim their allocation
    suite.blacklist_address(
        authorized_wallet,
        owner,
        true,
        |result: Result<_, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::CampaignError { reason } => {
                    assert_eq!(reason, "Cannot blacklist the campaign owner");
                }
                _ => panic!("Wrong error type"),
            }
        },
    );

    // Other users CAN be blacklisted
    suite.blacklist_address(
        authorized_wallet,
        user1,
        true,
        |result: Result<_, anyhow::Error>| {
            result.unwrap();
        },
    );
}

#[test]
fn test_owner_protection_with_multiple_authorized_wallets() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let owner = &suite.senders[0].clone();
    let authorized1 = &suite.senders[1].clone();
    let authorized2 = &suite.senders[2].clone();
    let user = &suite.senders[3].clone();
    let current_time = &suite.get_time();

    // Create a campaign with the owner
    suite
        .instantiate_claimdrop_contract(Some(owner.to_string()))
        .manage_campaign(
            owner,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Campaign".to_string(),
                    description: "Test campaign".to_string(),
                    ty: "airdrop".to_string(),
                    reward_denom: "uom".to_string(),
                    total_reward: coin(10_000_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 86400,
                    }],
                    start_time: current_time.seconds() + 86400,
                    end_time: current_time.seconds() + 86400 * 7,
                }),
            },
            &[],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        )
        // Add multiple authorized wallets
        .manage_authorized_wallets(
            owner,
            vec![authorized1.to_string(), authorized2.to_string()],
            true,
            &[],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            owner,
            &[coin(10_000_000, "uom")],
            |result: Result<_, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Neither authorized wallet should be able to blacklist the owner
    suite.blacklist_address(
        authorized1,
        owner,
        true,
        |result: Result<_, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::CampaignError { reason } => {
                    assert_eq!(reason, "Cannot blacklist the campaign owner");
                }
                _ => panic!("Wrong error type"),
            }
        },
    );

    suite.blacklist_address(
        authorized2,
        owner,
        true,
        |result: Result<_, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::CampaignError { reason } => {
                    assert_eq!(reason, "Cannot blacklist the campaign owner");
                }
                _ => panic!("Wrong error type"),
            }
        },
    );

    // Authorized wallets CAN add allocations for the owner (this is allowed)
    suite.add_allocations(
        authorized1,
        &vec![(owner.to_string(), Uint128::from(1000u128))],
        |result: Result<_, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify owner is not blacklisted and HAS allocations
    suite.query_is_blacklisted(owner, |result| {
        let blacklist_status = result.unwrap();
        assert!(
            !blacklist_status.is_blacklisted,
            "Owner should not be blacklisted"
        );
    });

    suite.query_allocations(Some(owner), None, None, |result| {
        let allocations = result.unwrap();
        assert_eq!(
            allocations.allocations.len(),
            1,
            "Owner should have allocations"
        );
        assert_eq!(allocations.allocations[0].1.amount.u128(), 1000);
    });

    // Authorized wallets should still be able to perform these actions on other users
    suite.blacklist_address(
        authorized1,
        user,
        true,
        |result: Result<_, anyhow::Error>| {
            result.unwrap();
        },
    );

    suite.add_allocations(
        authorized2,
        &vec![(user.to_string(), Uint128::from(3000u128))],
        |result: Result<_, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Even though user is blacklisted, they should still have the allocation
    // (blacklist prevents claiming, not allocation)
    suite.query_allocations(Some(user), None, None, |result| {
        let allocations = result.unwrap();
        assert_eq!(allocations.allocations.len(), 1);
        assert_eq!(allocations.allocations[0].1.amount.u128(), 3000);
    });
}
