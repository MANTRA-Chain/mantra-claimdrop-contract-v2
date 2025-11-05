use cosmwasm_std::{coin, coins, Decimal, Uint128};
use cw_multi_test::AppResponse;

use crate::suite::TestingSuite;
use mantra_claimdrop_std::msg::{CampaignAction, CampaignParams, DistributionType};

mod suite;

#[test]
fn test_sweep_non_reward_tokens() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
        coin(1_000_000_000, "utest"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    // Instantiate contract and create a campaign with uom as reward token
    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Campaign".to_string(),
                    description: "Test campaign for sweep testing".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[],
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &[coin(100_000, "uom")],
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        );

    // Send some non-reward tokens to the contract (simulating accidental transfers)
    suite
        .top_up_campaign(
            alice,
            &coins(50_000, "uusdc"),
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(30_000, "utest"),
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        );

    // Check initial balances
    suite.query_balance("uusdc", alice, |balance| {
        assert_eq!(balance, Uint128::new(999_950_000));
    });

    // Sweep uusdc tokens (full amount)
    suite.sweep(
        alice,
        "uusdc".to_string(),
        None,
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );

    // Check that uusdc was swept back to owner
    suite.query_balance("uusdc", alice, |balance| {
        assert_eq!(balance, Uint128::new(1_000_000_000));
    });

    // Check contract no longer has uusdc
    suite.query_balance("uusdc", &suite.claimdrop_contract_addr.clone(), |balance| {
        assert_eq!(balance, Uint128::zero());
    });

    // Sweep partial amount of utest tokens
    suite.sweep(
        alice,
        "utest".to_string(),
        Some(Uint128::new(20_000)),
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );

    // Check that only partial utest was swept
    suite.query_balance("utest", alice, |balance| {
        assert_eq!(balance, Uint128::new(999_990_000));
    });

    // Contract should still have 10_000 utest
    suite.query_balance("utest", &suite.claimdrop_contract_addr.clone(), |balance| {
        assert_eq!(balance, Uint128::new(10_000));
    });
}

#[test]
fn test_sweep_cannot_sweep_reward_denom() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    // Create a campaign with uom as reward token
    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Campaign".to_string(),
                    description: "Test campaign".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[],
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &[coin(100_000, "uom")],
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        );

    // Try to sweep reward denom (should fail)
    suite.sweep(
        alice,
        "uom".to_string(),
        None,
        |res: Result<AppResponse, anyhow::Error>| {
            assert!(
                res.is_err(),
                "Should fail when trying to sweep reward denom"
            );
        },
    );
}

#[test]
fn test_sweep_only_owner_can_sweep() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();

    // Instantiate with alice as owner
    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Send some tokens to the contract
    suite.top_up_campaign(
        alice,
        &coins(50_000, "uusdc"),
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );

    // Bob (non-owner) tries to sweep - should fail
    suite.sweep(
        bob,
        "uusdc".to_string(),
        None,
        |res: Result<AppResponse, anyhow::Error>| {
            assert!(res.is_err(), "Non-owner should not be able to sweep");
        },
    );

    // Alice (owner) can sweep successfully
    suite.sweep(
        alice,
        "uusdc".to_string(),
        None,
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );
}

#[test]
fn test_sweep_with_no_balance() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let alice = &suite.senders[0].clone();

    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Try to sweep a token that doesn't exist in the contract
    suite.sweep(
        alice,
        "unonexistent".to_string(),
        None,
        |res: Result<AppResponse, anyhow::Error>| {
            assert!(
                res.is_err(),
                "Should fail when trying to sweep non-existent tokens"
            );
        },
    );
}

#[test]
fn test_sweep_amount_exceeds_balance() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();

    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Send some tokens to the contract
    suite.top_up_campaign(
        alice,
        &coins(50_000, "uusdc"),
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );

    // Try to sweep more than available
    suite.sweep(
        alice,
        "uusdc".to_string(),
        Some(Uint128::new(100_000)),
        |res: Result<AppResponse, anyhow::Error>| {
            assert!(
                res.is_err(),
                "Should fail when trying to sweep more than available"
            );
        },
    );
}

#[test]
fn test_sweep_after_campaign_closed() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    // Create and close a campaign
    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Campaign".to_string(),
                    description: "Test campaign".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[],
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &[coin(100_000, "uom")],
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        )
        .add_day()
        .manage_campaign(
            alice,
            CampaignAction::CloseCampaign {},
            &[],
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        );

    // Send non-reward tokens after campaign is closed
    suite.top_up_campaign(
        alice,
        &coins(50_000, "uusdc"),
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );

    // Should still be able to sweep non-reward tokens
    suite.sweep(
        alice,
        "uusdc".to_string(),
        None,
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );

    // But still cannot sweep reward denom
    suite.sweep(
        alice,
        "uom".to_string(),
        None,
        |res: Result<AppResponse, anyhow::Error>| {
            assert!(
                res.is_err(),
                "Should fail when trying to sweep reward denom even after campaign closed"
            );
        },
    );
}

#[test]
fn test_sweep_no_campaign_exists() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();

    // Instantiate without creating a campaign
    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Send tokens to the contract
    suite
        .top_up_campaign(
            alice,
            &coins(50_000, "uusdc"),
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(30_000, "uom"),
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        );

    // When no campaign exists, should be able to sweep any token
    suite.sweep(
        alice,
        "uusdc".to_string(),
        None,
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );
    suite.sweep(
        alice,
        "uom".to_string(),
        None,
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );

    // Verify balances
    suite.query_balance("uusdc", alice, |balance| {
        assert_eq!(balance, Uint128::new(1_000_000_000));
    });

    suite.query_balance("uom", alice, |balance| {
        assert_eq!(balance, Uint128::new(1_000_000_000));
    });
}
