use std::str::FromStr;

use claimdrop_contract::commands::MAX_ALLOCATION_BATCH_SIZE;
use claimdrop_contract::helpers::MAX_PLACEHOLDER_ADDRESS_LEN;
use cosmwasm_std::{coin, coins, Addr, Decimal, StdError, StdResult, Uint128};
use cw_multi_test::AppResponse;
use cw_ownable::OwnershipError;

use crate::suite::TestingSuite;
use mantra_claimdrop_std::error::ContractError;
use mantra_claimdrop_std::msg::{
    CampaignAction, CampaignParams, ClaimedResponse, DistributionType, RewardsResponse,
};
mod suite;

#[test]
fn instantiate_claimdrop_contract() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);
    suite.instantiate_claimdrop_contract(None);
}

#[test]
fn create_multiple_campaigns_fails() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::CampaignError { reason } => {
                        assert_eq!(reason, "existing campaign");
                    }
                    _ => panic!("Wrong error type, should return ContractError::CampaignError"),
                }
            },
        )
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.name, "Test Airdrop I".to_string());
            assert_eq!(campaign.ty, "airdrop".to_string());
        })
        .manage_campaign(
            alice,
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop II".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::CampaignError { reason } => {
                        assert_eq!(reason, "existing campaign");
                    }
                    _ => panic!("Wrong error type, should return ContractError::CampaignError"),
                };
            },
        );
}

#[test]
fn cant_create_campaign_if_not_owner() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let current_time = &suite.get_time();

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .manage_campaign(
            bob,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError(e) => match e {
                        OwnershipError::NotOwner => {}
                        _ => panic!("Wrong error type, should return OwnershipError::NotOwner"),
                    },
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        );
}

#[test]
fn validate_campaign_params() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        // name & description
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { param, reason, } => {
                        assert_eq!(param, "name");
                        assert_eq!(reason, "cannot be empty");
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
                }
            },
        ).manage_campaign(
        alice,
        CampaignAction::CreateCampaign {
            params: Box::new(CampaignParams {
                name: "a".repeat(201),
                description: "This is an airdrop, 土金, ك".to_string(),
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
        &[], // No funds during campaign creation
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::InvalidCampaignParam { param, reason } => {
                    assert_eq!(param, "name");
                    assert_eq!(reason, "cannot be longer than 200 characters");
                }
                _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
            }
        },
    )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "".to_string(),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { param, reason } => {
                        assert_eq!(param, "description");
                        assert_eq!(reason, "cannot be empty");
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
                }
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "a".repeat(2001),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { param, reason } => {
                        assert_eq!(param, "description");
                        assert_eq!(reason, "cannot be longer than 2000 characters");
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
                }
            },
        )
        // campaign type - empty type
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { param, reason } => {
                        assert_eq!(param, "type");
                        assert_eq!(reason, "cannot be empty");
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
                }
            },
        )
        // campaign type - too long type
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "a".repeat(201),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { param, reason } => {
                        assert_eq!(param, "type");
                        assert_eq!(reason, "cannot be longer than 200 characters");
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
                }
            },
        )
        // campaign times
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() + 172_800,
                    end_time: current_time.seconds() + 1,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { param, reason } => {
                        assert_eq!(param, "start_time");
                        assert_eq!(reason, "cannot be greater or equal than end_time");
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
                }
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() - 100,
                    end_time: current_time.seconds() + 1,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { param, reason, } => {
                        assert_eq!(param, "start_time");
                        assert_eq!(reason, "cannot be less than the current time");
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
                }
            },
        )
        // distribution types
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { param, reason } => {
                        assert_eq!(param, "distribution_type");
                        assert_eq!(reason, "invalid number of distribution types, should be at least 1, maximum 2");
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
                }
            },
        ).manage_campaign(
        alice,
        CampaignAction::CreateCampaign {
            params: Box::new(CampaignParams {
                name: "Test Airdrop I".to_string(),
                description: "This is an airdrop, 土金, ك".to_string(),
                ty: "airdrop".to_string(),
                total_reward: coin(100_000, "uom"),
                distribution_type: vec![
                    DistributionType::LumpSum {
                        percentage: Decimal::from_str("2").unwrap(),
                        start_time: current_time.seconds() + 1,
                    },
                    DistributionType::LumpSum {
                        percentage: Decimal::from_str("2").unwrap(),
                        start_time: current_time.seconds() + 1,
                    },
                    DistributionType::LumpSum {
                        percentage: Decimal::from_str("2").unwrap(),
                        start_time: current_time.seconds() + 1,
                    },
                ],
                start_time: current_time.seconds() + 1,
                end_time: current_time.seconds() + 172_800,
            }),
        },
        &[], // No funds during campaign creation
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::InvalidCampaignParam { param, reason } => {
                    assert_eq!(param, "distribution_type");
                    assert_eq!(reason, "invalid number of distribution types, should be at least 1, maximum 2");
                }
                _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
            }
        },
    )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::from_str("2").unwrap(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidDistributionPercentage { expected, actual } => {
                        assert_eq!(expected, Decimal::one());
                        assert_eq!(actual, Decimal::from_str("2").unwrap());
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidDistributionPercentage"),
                }
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::from_str("0.2").unwrap(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidDistributionPercentage { expected, actual } => {
                        assert_eq!(expected, Decimal::one());
                        assert_eq!(actual, Decimal::from_str("0.2").unwrap());
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidDistributionPercentage"),
                }
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::zero(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::ZeroDistributionPercentage => {}
                    _ => panic!("Wrong error type, should return ContractError::ZeroDistributionPercentage"),
                }
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() - 1,
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidStartDistributionTime { .. } => {}
                    _ => panic!("Wrong error type, should return ContractError::InvalidStartDistributionTime"),
                }
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds(),
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidStartDistributionTime { .. } => {}
                    _ => panic!("Wrong error type, should return ContractError::InvalidStartDistributionTime"),
                }
            },
        )

        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::from_str("0.5").unwrap(),
                            start_time: current_time.seconds() + 1,
                        },
                        DistributionType::LumpSum {
                            percentage: Decimal::one(),
                            start_time: current_time.seconds() + 1,
                        }
                    ],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,

                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidDistributionPercentage { .. } => {}
                    _ => panic!("Wrong error type, should return ContractError::InvalidDistributionPercentage"),
                }
            },
        )
        //cliff
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LinearVesting {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 1,
                        end_time: current_time.seconds() + 172_800,
                        cliff_duration: Some(0u64),
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,

                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { param, reason } => {
                        assert_eq!(param, "cliff_duration");
                        assert_eq!(reason, "cannot be zero");
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
                }
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LinearVesting {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds(),
                        end_time: current_time.plus_days(7).seconds(),
                        cliff_duration: Some(7 * 86_400u64),
                    }],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(7).seconds(),

                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { param, reason } => {
                        assert_eq!(param, "cliff_duration");
                        assert_eq!(reason, "cannot be greater or equal than the distribution duration");
                    }
                    _ => panic!("Wrong error type, should return ContractError::InvalidCampaignParam"),
                }
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop II".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(0, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::one(),
                        start_time: current_time.seconds() + 1,
                    }],
                    start_time: current_time.seconds() + 1,
                    end_time: current_time.seconds() + 172_800,
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidCampaignParam { reason, param } => {
                        assert_eq!(param, "total_reward");
                        assert_eq!(reason, "cannot be zero");
                    }
                    _ => panic!("Wrong error type, should return ContractError::CampaignError"),
                };
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )

    ;
}

#[test]
fn cannot_start_distribution_in_past() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LinearVesting {
                        percentage: Decimal::percent(100),
                        start_time: current_time.minus_days(10).seconds(),
                        end_time: current_time.plus_days(60).seconds(),
                        cliff_duration: None,
                    }],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(60).seconds(),
                }),
            },
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidStartDistributionTime { .. } => {}
                    _ => panic!("Wrong error type, should return ContractError::InvalidStartDistributionTime"),
                }
            },
        );
}

#[test]
fn cant_claim_without_campaign() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();

                match err {
                    ContractError::CampaignError { reason } => {
                        assert_eq!(reason, "there's not an active campaign");
                    }
                    _ => panic!("Wrong error type, should return ContractError::CampaignError"),
                }
            },
        );
}

#[test]
fn create_campaign_and_claim_single_distribution_type() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (bob.to_string(), Uint128::new(10_000)),
        (carol.to_string(), Uint128::new(20_000)),
    ];

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // claim
    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();

            match err {
                ContractError::CampaignError { reason } => {
                    assert_eq!(reason, "not started");
                }
                _ => panic!("Wrong error type, should return ContractError::CampaignError"),
            }
        },
    );

    suite.add_day();

    suite
        .query_balance("uom", alice, |balance| {
            assert_eq!(balance, Uint128::new(999_900_000));
        })
        .query_balance("uom", bob, |balance| {
            assert_eq!(balance, Uint128::new(1_000_000_000));
        })
        // bob tries to claim for alice (should fail - unauthorized)
        .claim(
            bob,
            Some(alice.to_string()),
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::Unauthorized => {}
                    _ => panic!("Wrong error type, should return ContractError::Unauthorized"),
                }
            },
        )
        // alice claims for herself
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance("uom", alice, |balance| {
            assert_eq!(balance, Uint128::new(999_910_000));
        })
        .query_balance("uom", bob, |balance| {
            assert_eq!(balance, Uint128::new(1_000_000_000));
        })
        .claim(
            bob,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance("uom", bob, |balance| {
            assert_eq!(balance, Uint128::new(1_000_010_000));
        })
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.claimed, coin(20_000u128, "uom"));
        });

    suite
        .add_week()
        .add_week()
        .add_week()
        .query_balance("uom", carol, |balance| {
            assert_eq!(balance, Uint128::new(1_000_000_000));
        })
        .claim(
            carol,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance("uom", carol, |balance| {
            assert_eq!(balance, Uint128::new(1_000_020_000));
        });
}

#[test]
fn cant_claim_unfunded_campaign() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (bob.to_string(), Uint128::new(10_000)),
        (carol.to_string(), Uint128::new(20_000)),
    ];

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.manage_campaign(
        alice,
        CampaignAction::CreateCampaign {
            params: Box::new(CampaignParams {
                name: "Test Airdrop I".to_string(),
                description: "This is an airdrop, 土金, ك".to_string(),
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
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    suite.add_day();

    suite
        .query_balance("uom", alice, |balance| {
            assert_eq!(balance, Uint128::new(1_000_000_000));
        })
        .query_balance("uom", bob, |balance| {
            assert_eq!(balance, Uint128::new(1_000_000_000));
        })
        // bob claims for alice
        .claim(
            bob,
            Some(alice.to_string()),
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();

                match err {
                    ContractError::Unauthorized => {}
                    _ => panic!("Wrong error type, should return ContractError::Unauthorized"),
                }
            },
        )
        .top_up_campaign(
            alice,
            &coins(50_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance("uom", alice, |balance| {
            assert_eq!(balance, Uint128::new(1_000_000_000 - 50_000 + 10_000));
        });
}

#[test]
fn claim_ended_campaign() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let dan = &suite.senders[3].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (bob.to_string(), Uint128::new(10_000)),
        (carol.to_string(), Uint128::new(20_000)),
    ];

    suite
        .instantiate_claimdrop_contract(Some(dan.to_string()))
        .add_allocations(
            dan,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            dan,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            dan,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.name, "Test Airdrop I");
        });

    // claim
    suite
        .add_day()
        .claim(
            bob,
            Some(alice.to_string()),
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::Unauthorized => {}
                    _ => panic!("Wrong error type, should return ContractError::Unauthorized"),
                }
            },
        )
        // alice claims for herself
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance("uom", bob, |balance| {
            assert_eq!(balance, Uint128::new(1_000_000_000));
        })
        .query_balance("uom", alice, |balance| {
            assert_eq!(balance, Uint128::new(1_000_010_000));
        })
        .claim(
            bob,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance("uom", bob, |balance| {
            assert_eq!(balance, Uint128::new(1_000_010_000));
        })
        .query_balance("uom", alice, |balance| {
            assert_eq!(balance, Uint128::new(1_000_010_000));
        });

    suite
        .manage_campaign(
            // bob tries to end the campaign
            bob,
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError { .. } => {}
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        )
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.claimed, coin(20_000u128, "uom"));
        })
        .query_balance("uom", dan, |balance| {
            assert_eq!(balance, Uint128::new(999_900_000));
        })
        // change ownership of the campaign
        .update_ownership(
            dan,
            cw_ownable::Action::TransferOwnership {
                new_owner: alice.to_string(),
                expiry: None,
            },
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .update_ownership(
            alice,
            cw_ownable::Action::AcceptOwnership {},
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            // alice should be able to, since she is the owner of the contract now
            alice,
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        // Since dan gave ownership to alice, he doesn't get the remaining tokens back.
        .query_balance("uom", dan, |balance| {
            assert_eq!(balance, Uint128::new(999_900_000));
        })
        // alice got the remaining tokens back, which were 80k as 20k as were claimed by bob and herself
        .query_balance("uom", alice, |balance| {
            assert_eq!(balance, Uint128::new(1_000_090_000));
        });

    // now carol tries to claim but it's too late
    suite.claim(
        carol,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();

            match err {
                ContractError::CampaignError { reason } => {
                    assert_eq!(reason, "has been closed, cannot claim");
                }
                _ => panic!("Wrong error type, should return ContractError::CampaignError"),
            }
        },
    );
}

#[test]
fn query_claimed() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let dan = &suite.senders[3].clone();
    let eva = &suite.senders[4].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (bob.to_string(), Uint128::new(10_000)),
        (carol.to_string(), Uint128::new(20_000)),
        (dan.to_string(), Uint128::new(35_000)),
        (eva.to_string(), Uint128::new(25_000)),
    ];

    suite
        .instantiate_claimdrop_contract(Some(dan.to_string()))
        .add_allocations(
            dan,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            dan,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.plus_days(7).seconds(),
                            end_time: current_time.plus_days(14).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.name, "Test Airdrop I");
        });

    suite.add_week();

    // claim
    // alice gets 2500 in lump sump and 7500 linearly.
    // of those 7500 linear tokens, she gets 1071 per day as the distribution lasts 7 days

    suite
        .claim(
            bob, //bob tries to claim for alice (should fail)
            Some(alice.to_string()),
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::Unauthorized => {}
                    _ => panic!("Wrong error type, should return ContractError::Unauthorized"),
                }
            },
        )
        // alice claims for herself
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_claimed(Some(alice), None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize);
            assert_eq!(
                claimed_response.claimed[0],
                (alice.to_string(), coin(2_500u128, "uom"))
            );
        })
        .query_claimed(Some(bob), None, None, |result| {
            let claimed_response = result.unwrap();
            assert!(claimed_response.claimed.is_empty());
        });

    suite
        .add_day()
        .add_day()
        .claim(
            alice,
            Some(alice.to_string()),
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_claimed(Some(alice), None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize);
            assert_eq!(
                claimed_response.claimed[0],
                (alice.to_string(), coin(2_500u128 + 1071u128 * 2, "uom"))
            );
        })
        .claim(
            bob,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_claimed(Some(bob), None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize);
            assert_eq!(
                claimed_response.claimed[0],
                (bob.to_string(), coin(2_500u128 + 1071u128 * 2, "uom"))
            );
        });

    // move a week, the campaign should be over by now and everybody who claims will get the full amount
    // they were entitled to
    suite.add_week();

    suite
        .claim(
            alice,
            Some(alice.to_string()),
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_claimed(Some(alice), None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize);
            assert_eq!(
                claimed_response.claimed[0],
                (alice.to_string(), coin(10_000u128, "uom"))
            );
        })
        .claim(
            bob,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .claim(
            carol,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .claim(
            dan,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .claim(
            eva,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_claimed(Some(eva), None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize);
            assert_eq!(
                claimed_response.claimed[0],
                (eva.to_string(), coin(25_000u128, "uom"))
            );
        });

    // test pagination

    suite
        .query_claimed(None, None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 5usize);
            // Note: Order might vary based on internal HashMap iteration order before sorting in query if not explicitly sorted by address string
            // For robust test, sort here or ensure query always sorts. Assuming query_claimed sorts by address for pagination.
            // Let's assume the test had this order before, if it fails, it's due to HashMap iter order.
            let mut actual_claims = claimed_response.claimed;
            actual_claims.sort_by(|a, b| a.0.cmp(&b.0)); // Sort by address for consistent comparison

            let mut expected_claims = vec![
                (alice.to_string(), coin(10_000u128, "uom")),
                (bob.to_string(), coin(10_000u128, "uom")),
                (carol.to_string(), coin(20_000u128, "uom")),
                (dan.to_string(), coin(35_000u128, "uom")),
                (eva.to_string(), coin(25_000u128, "uom")),
            ];
            expected_claims.sort_by(|a, b| a.0.cmp(&b.0));
            assert_eq!(actual_claims, expected_claims);
        })
        .query_claimed(None, Some(carol), None, |result| {
            // start_from carol
            let claimed_response = result.unwrap();
            let mut actual_claims = claimed_response.claimed;
            actual_claims.sort_by(|a, b| a.0.cmp(&b.0));

            // Expected: addresses alphabetically after carol
            let mut expected_after_carol = vec![
                (bob.to_string(), coin(10_000u128, "uom")),
                (dan.to_string(), coin(35_000u128, "uom")),
                (eva.to_string(), coin(25_000u128, "uom")),
            ];
            expected_after_carol.sort_by(|a, b| a.0.cmp(&b.0));

            assert_eq!(actual_claims.len(), 3usize);
            assert_eq!(actual_claims, expected_after_carol);
        })
        .query_claimed(None, None, Some(2), |result| {
            let claimed_response = result.unwrap();
            // Expects first 2 alphabetically: alice, bob
            assert_eq!(claimed_response.claimed.len(), 2usize);
            assert_eq!(
                claimed_response.claimed,
                vec![
                    (alice.to_string(), coin(10_000u128, "uom")),
                    (carol.to_string(), coin(20_000u128, "uom")),
                ]
            );
        })
        .query_claimed(None, Some(alice), Some(2), |result| {
            // After alice, limit 2: bob, carol
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 2usize);
            assert_eq!(
                claimed_response.claimed,
                vec![
                    (carol.to_string(), coin(20_000u128, "uom")),
                    (eva.to_string(), coin(25_000u128, "uom")),
                ]
            );
        });
}

#[test]
fn create_campaign_and_claim_multiple_distribution_types() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let dan = &suite.senders[3].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (dan.to_string(), Uint128::new(35_000)),
    ];

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.plus_days(7).seconds(),
                            end_time: current_time.plus_days(14).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.add_day();

    suite
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.claimed, coin(2_500u128, "uom"));
        })
        // trying to claim again without moving time, should err
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(2_500u128, "uom"),
                    pending: coins(10_000u128 - 2_500u128, "uom"),
                    available_to_claim: vec![],
                }
            );
        })
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::NothingToClaim => {}
                    _ => panic!("Wrong error type, should return ContractError::NothingToClaim"),
                }
            },
        )
        .add_week()
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        // trying to claim again without moving time, should err
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::NothingToClaim => {}
                    _ => panic!("Wrong error type, should return ContractError::NothingToClaim"),
                }
            },
        )
        .add_day()
        .add_day()
        .add_day()
        .add_day()
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(3_571u128, "uom"), // 2500 + (7500 * 4/7 * 1/4) approx. This needs re-check based on actual vesting.
                    // Original test had 3_571. This is lump sum (2500) + 4 days of vesting of (7500 over 7 days)
                    // 2500 + (7500 * 4/7) = 2500 + 4285.71 = 6785.
                    // Let's re-evaluate the original test's numbers.
                    // After 1 day: claim 2500 (lump sum). Available = 0.
                    // Add 7 days (total 8 days from start). Vesting started at day 7. So 1 day of vesting.
                    // Vesting is 7500 over 7 days = 1071.42 per day.
                    // So, at day 8, Alice claims 1071. Total claimed = 2500 + 1071 = 3571. OK.
                    // Available: 0 (claimed all current vesting)
                    // Add 4 more days (total 12 days from start). 4 more days of vesting.
                    // Available: 1071 * 4 = 4284
                    // Claimed: 3571. Pending: 10000 - 3571 = 6429
                    pending: coins(10_000u128 - 3_571u128, "uom"),
                    available_to_claim: coins(4_286u128, "uom"), // 4 days * (7500/7)
                }
            );
        })
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap(); // Claims 4285. Total claimed = 3571 + 4285 = 7856
            },
        )
        // add 2 more weeks and claim, the campaign should have finished by then
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(7_857u128, "uom"),
                    pending: coins(10_000u128 - 7_857u128, "uom"), // 2143
                    available_to_claim: vec![], // All currently vested is claimed.
                }
            );
        })
        .add_week() // total 12 days + 7 days = 19 days. Campaign ends day 14. Vesting ends day 14.
        .add_week() // total 19 days + 7 days = 26 days.
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                // Claims remaining 2144
                result.unwrap();
            },
        )
        // add a day and try claiming again, should err
        .add_day()
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::NothingToClaim => {}
                    _ => panic!("Wrong error type, should return ContractError::NothingToClaim"),
                }
            },
        )
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.claimed, coin(10_000u128, "uom"));
        })
        // dan claiming all at once
        .query_rewards(dan, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: vec![],
                    pending: coins(35_000u128, "uom"),
                    available_to_claim: coins(35_000u128, "uom"), // All available as campaign ended
                }
            );
        })
        .claim(
            dan,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_rewards(dan, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(35_000u128, "uom"),
                    pending: vec![],
                    available_to_claim: vec![],
                }
            );
        })
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.claimed, coin(45_000u128, "uom")); // 10000 (alice) + 35000 (dan)
        });
}

#[test]
fn claim_campaign_with_cliff() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(10_000))];

    suite
        .instantiate_claimdrop_contract(None)
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LinearVesting {
                        percentage: Decimal::percent(100),
                        start_time: current_time.seconds(),
                        end_time: current_time.plus_days(1460).seconds(), // 4 years
                        cliff_duration: Some(86_400 * 365),               // 1 year cliff
                    }],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(1460).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // can't claim before the cliff period is over
    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::NothingToClaim => {}
                _ => panic!("Wrong error type, should return ContractError::NothingToClaim"),
            }
        },
    );

    // move a few days to pass the cliff

    // move the remaining of the year - 1 day, 365 - 1 day
    for _ in 0..364 {
        suite.add_day();
    }

    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::NothingToClaim => {}
                _ => panic!("Wrong error type, should return ContractError::NothingToClaim"),
            }
        },
    );

    // add another day, total days passed 365, ready to claim some
    suite.add_day();

    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    suite
        .query_campaign(|result| {
            assert_eq!(result.unwrap().claimed, coin(10_000 / 4, "uom"));
        })
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(10_000 / 4, "uom"),
                    pending: coins(10_000u128 - (10_000 / 4), "uom"),
                    available_to_claim: vec![],
                }
            );
        });

    // advance another year
    for _ in 0..365 {
        suite.add_day();
    }

    suite
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_campaign(|result| {
            assert_eq!(result.unwrap().claimed, coin((10_000 / 4) * 2, "uom"));
        });

    // advance two more years, so the vesting period should be over
    for _ in 0..730 {
        suite.add_day();
    }

    suite
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins((10_000 / 4) * 2, "uom"),
                    pending: coins(10_000u128 - ((10_000 / 4) * 2), "uom"),
                    available_to_claim: coins((10_000 / 4) * 2, "uom"),
                }
            );
        })
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        // add a week and claim
        .query_campaign(|result| {
            assert_eq!(result.unwrap().claimed, coin(10_000u128, "uom"));
        })
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(10_000u128, "uom"),
                    pending: vec![],
                    available_to_claim: vec![],
                }
            );
        });
}

#[test]
fn claim_campaign_with_vesting_cliff_and_lump_sum() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(10_000))];

    suite
        .instantiate_claimdrop_contract(None)
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(50),
                            start_time: current_time.seconds(),
                            end_time: current_time.plus_days(1460).seconds(), // 4 years
                            cliff_duration: Some(86_400 * 365),               // 1 year cliff
                        },
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(50),
                            start_time: current_time.seconds(),
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(1460).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // The lump sum should be claimable right away, as it is not affected by the vesting cliff
    suite
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_claimed(Some(alice), None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize);
            assert_eq!(
                claimed_response.claimed[0],
                (alice.to_string(), coin(5_000u128, "uom"))
            );
        });

    // move a few days to pass the cliff

    // move the remaining of the year - 1 day, 365 - 1 day
    for _ in 0..364 {
        suite.add_day();
    }

    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::NothingToClaim => {}
                _ => panic!("Wrong error type, should return ContractError::NothingToClaim"),
            }
        },
    );

    // add another day, total days passed 365, ready to claim some
    suite.add_day();

    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    suite
        .query_campaign(|result| {
            assert_eq!(
                result.unwrap().claimed,
                coin(5_000u128 + 5_000u128 / 4, "uom")
            );
        })
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(5_000u128 + 5_000u128 / 4, "uom"),
                    pending: coins(10_000u128 - (5_000u128 + 5_000u128 / 4), "uom"),
                    available_to_claim: vec![],
                }
            );
        });

    // advance another year
    for _ in 0..365 {
        suite.add_day();
    }

    suite
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_campaign(|result| {
            assert_eq!(
                result.unwrap().claimed,
                coin(5_000u128 + (2 * 5_000u128 / 4), "uom")
            );
        });

    // advance two more years, so the vesting period should be over
    for _ in 0..730 {
        suite.add_day();
    }

    suite
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(5_000u128 + (2 * 5_000u128 / 4), "uom"),
                    pending: coins(10_000u128 - (5_000u128 + (2 * 5_000u128 / 4)), "uom"),
                    available_to_claim: coins(2 * 5_000u128 / 4, "uom"),
                }
            );
        })
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        // add a week and claim
        .query_campaign(|result| {
            assert_eq!(result.unwrap().claimed, coin(10_000u128, "uom"));
        })
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(10_000u128, "uom"),
                    pending: vec![],
                    available_to_claim: vec![],
                }
            );
        });
}
#[test]
fn claim_campaign_with_vesting_cliff_in_future_and_lump_sum() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(10_000))];

    suite
        .instantiate_claimdrop_contract(None)
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(50),
                            start_time: current_time.plus_days(30).seconds(),
                            end_time: current_time.plus_days(60).seconds(), // 30 days duration
                            cliff_duration: Some(86_400 * 7),               // 7 days cliff
                        },
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(50),
                            start_time: current_time.seconds(),
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(90).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // The lump sum should be claimable right away, as it is not affected by the vesting cliff
    suite
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_claimed(Some(alice), None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize);
            assert_eq!(
                claimed_response.claimed[0],
                (alice.to_string(), coin(5_000u128, "uom"))
            );
        });

    // move a few days to pass the cliff

    // move the remaining of the 30 days - 1 day
    for _ in 0..29 {
        suite.add_day();
    }

    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::NothingToClaim => {}
                _ => panic!("Wrong error type, should return ContractError::NothingToClaim"),
            }
        },
    );

    // add another day, total days passed 30, now the cliff starts ticking
    suite.add_day();

    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::NothingToClaim => {}
                _ => panic!("Wrong error type, should return ContractError::NothingToClaim"),
            }
        },
    );

    // move mid-way the cliff, there should be nothing to claim yet
    for _ in 0..6 {
        suite.add_day();
    }

    suite.query_rewards(alice, |result| {
        assert_eq!(
            result.unwrap(),
            RewardsResponse {
                claimed: coins(5_000u128, "uom"),
                pending: coins(10_000u128 - 5_000u128, "uom"),
                available_to_claim: vec![],
            }
        );
    });

    // move a day to pass the cliff
    suite.add_day();

    suite.query_rewards(alice, |result| {
        assert_eq!(
            result.unwrap(),
            RewardsResponse {
                claimed: coins(5_000u128, "uom"),
                pending: coins(10_000u128 - 5_000u128, "uom"),
                available_to_claim: coins(7 * 5_000u128 / 30u128, "uom"), // 7 days (cliff) out of 30 day vesting period of 5000 tokens = 1166
            }
        );
    });

    // advance another week
    for _ in 0..7 {
        suite.add_day();
    }

    suite
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                // Claims available 1166 + 7 more days = 1166 + 1166 = 2332. Total claimed = 5000 + 2332 = 7332
                result.unwrap();
            },
        )
        .query_campaign(|result| {
            assert_eq!(
                result.unwrap().claimed, // Lump sum + ( (cliff_duration + 7 days) / total_vesting_duration_for_slot ) * slot_total_reward
                // 5000 + ( (7+7) / 30 ) * 5000 = 5000 + (14/30)*5000 = 5000 + 2333 = 7333. Close enough to 7332 due to previous rounding.
                coin(5_000u128 + (2 * 7 * 5_000u128 / 30u128), "uom") // Original: 5000 + 2332 = 7332
            );
        });

    // advance two more weeks, so the linear vesting should be over (14 more days. Total days passed cliff = 7+7+14 = 28. Vesting duration = 30 days)
    // Remaining 2 days of vesting will be claimable.
    for _ in 0..16 {
        // cliff (7) + 7 + 16 = 30 days from vesting start. Vesting ends.
        suite.add_day();
    }

    suite
        .query_rewards(alice, |result| {
            let previous_total_claimed = 5_000u128 + (2 * 7 * 5_000u128 / 30u128); // 7332
            let total_vesting_slot_amount = 5_000u128;
            let already_claimed_from_vesting = 2 * 7 * 5_000u128 / 30u128; // 2332
            let remaining_to_claim_from_vesting =
                total_vesting_slot_amount.saturating_sub(already_claimed_from_vesting); // 5000 - 2332 = 2668

            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(previous_total_claimed, "uom"),
                    pending: coins(10_000u128 - previous_total_claimed, "uom"),
                    available_to_claim: coins(remaining_to_claim_from_vesting, "uom"),
                }
            );
        })
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        // add a week and claim
        .query_campaign(|result| {
            assert_eq!(result.unwrap().claimed, coin(10_000u128, "uom"));
        })
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(10_000u128, "uom"),
                    pending: vec![],
                    available_to_claim: vec![],
                }
            );
        });
}

#[test]
fn topup_campaigns_with_and_without_cliff() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let dan = &suite.senders[3].clone();
    let eva = &suite.senders[4].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (bob.to_string(), Uint128::new(10_000)),
        (carol.to_string(), Uint128::new(20_000)),
        (dan.to_string(), Uint128::new(35_000)),
        (eva.to_string(), Uint128::new(25_000)),
    ];

    suite
        .instantiate_claimdrop_contract(None)
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LinearVesting {
                        percentage: Decimal::percent(100),
                        start_time: current_time.seconds(),
                        end_time: current_time.plus_days(30).seconds(), // a month
                        cliff_duration: Some(86_400 * 7),               // 7 days cliff
                    }],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(30).seconds(),
                }),
            },
            &[], // No funds during campaign creation // Initial funding less than total_reward
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(30_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.query_campaign(|result| {
        let campaign = result.unwrap();
        assert_eq!(campaign.total_reward, coin(100_000, "uom"));
    });

    for _ in 0..7 {
        // Pass cliff
        suite.add_day();
    }

    // everybody claims
    // Total allocation = 10k+10k+20k+35k+25k = 100k
    // At 7 days (cliff end) into 30-day vesting: 7/30 of total is claimable.
    // 100_000 * 7 / 30 = 23333.33. Rounded down.
    // Alice: 10000 * 7/30 = 2333
    // Bob: 10000 * 7/30 = 2333
    // Carol: 20000 * 7/30 = 4666
    // Dan: 35000 * 7/30 = 8166
    // Eva: 25000 * 7/30 = 5833
    // Total claimed = 2333+2333+4666+8166+5833 = 23331 (Matches original test)
    suite
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .claim(
            bob,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .claim(
            carol,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .claim(
            dan,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .claim(
            eva,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.query_campaign(|result| {
        let campaign = result.unwrap();
        assert_eq!(campaign.claimed, coin(23_331u128, "uom"));
    });

    let contract = suite.claimdrop_contract_addr.clone();
    // topup campaign
    suite
        .top_up_campaign(
            alice,
            &coins(70_000, "uom"), // Top up to meet total_reward
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance("uom", &contract, |result| {
            // Initial 30k + 70k topup - 23331 claimed = 76669
            assert_eq!(result, Uint128::new(30_000u128 + 70_000u128 - 23_331u128));
        });

    // go to the time when the campaign already finished
    for _ in 0..23 {
        // 7 days passed + 23 days = 30 days. Campaign ends.
        suite.add_day();
    }

    let current_time_after_first_campaign = &suite.get_time(); // Save time for next campaign

    // create a new contract / campaign (by re-instantiating)
    suite.instantiate_claimdrop_contract(None); // New contract instance for Test Airdrop II

    let contract_2 = suite.claimdrop_contract_addr.clone(); // Get new contract address

    suite
        .manage_campaign(
            alice, // Alice is owner of this new contract instance by default if None passed to instantiate
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop II".to_string(),
                    description: "This is an airdrop without cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"), // Total intended for this campaign
                    distribution_type: vec![DistributionType::LinearVesting {
                        percentage: Decimal::percent(100),
                        start_time: current_time_after_first_campaign.seconds(),
                        end_time: current_time_after_first_campaign.plus_days(30).seconds(), // a month
                        cliff_duration: None, // no cliff
                    }],
                    start_time: current_time_after_first_campaign.seconds(),
                    end_time: current_time_after_first_campaign.plus_days(30).seconds(),
                }),
            },
            &[], // No funds during campaign creation // Initial funding
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(50_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance("uom", &contract_2, |result| {
            assert_eq!(result, Uint128::new(50_000u128));
        })
        .top_up_campaign(
            // Top up more funds
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance("uom", &contract_2, |result| {
            // Total funds in contract_2 = 50k + 100k = 150k
            assert_eq!(result, Uint128::new(150_000u128));
        });
}

#[test]
fn query_rewards() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(10_000))];

    suite
        .instantiate_claimdrop_contract(None)
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.plus_days(7).seconds(),
                            end_time: current_time.plus_days(14).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap(); // Claims 2500 (LumpSum)
            },
        )
        .query_rewards(alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: coins(2_500u128, "uom"),
                    pending: coins(10_000u128 - 2_500u128, "uom"), // 7500 pending from vesting
                    available_to_claim: vec![],                    // Vesting not started yet
                }
            );
        })
        .manage_campaign(
            alice,
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_rewards(alice, |result| {
            let rewards_response = result.unwrap();
            assert_eq!(rewards_response.claimed, coins(2_500u128, "uom"));
            assert!(rewards_response.pending.is_empty()); // Campaign closed, no more pending
            assert!(rewards_response.available_to_claim.is_empty()); // Campaign closed
        });
}

#[test]
fn query_rewards_single_user() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(100))];

    suite
        .instantiate_claimdrop_contract(None)
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"), // Contract has 100k, user allocated 100
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::percent(100),
                        start_time: current_time.seconds(),
                    }],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation // Fund with exact user allocation for simplicity here
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite
        .query_rewards(alice, |result| {
            let rewards_response = result.unwrap();
            // Expected before claim:
            assert_eq!(rewards_response.claimed, vec![]);
            assert_eq!(rewards_response.pending, coins(100, "uom"));
            assert_eq!(rewards_response.available_to_claim, coins(100, "uom"));
            println!("{rewards_response:?}");
        })
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_rewards(alice, |result| {
            let rewards_response = result.unwrap();
            // Expected after claim:
            assert_eq!(rewards_response.claimed, coins(100, "uom"));
            assert_eq!(rewards_response.pending, vec![]);
            assert_eq!(rewards_response.available_to_claim, vec![]);
            println!("{rewards_response:?}");
        });
}

#[test]
fn query_rewards_fails_when_campaign_has_not_started() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(10_000))];

    suite
        .instantiate_claimdrop_contract(None)
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.plus_days(1).seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.plus_days(8).seconds(),
                            end_time: current_time.plus_days(15).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.plus_days(1).seconds(), // Campaign starts in 1 day
                    end_time: current_time.plus_days(15).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();

                match err {
                    ContractError::CampaignError { reason } => {
                        assert_eq!(reason, "not started");
                    }
                    _ => panic!("Wrong error type, should return ContractError::CampaignError"),
                }
            },
        )
        .query_rewards(alice, |result| {
            let err = result.unwrap_err().to_string();
            assert!(err.contains("not started"));
        });

    // move some epochs to make campaign active
    suite.add_day(); // Advance 1 day, campaign starts
    suite.query_rewards(alice, |result| {
        // Now campaign has started
        let rewards = result.unwrap();
        // Lump sum (25% of 10k = 2500) should be available as its start time matches campaign start time
        assert_eq!(rewards.claimed, vec![]);
        assert_eq!(rewards.pending, coins(10_000, "uom"));
        assert_eq!(rewards.available_to_claim, coins(2500, "uom"));
    });
}

#[test]
fn close_campaigns() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let current_time = &suite.get_time();

    suite
        .instantiate_claimdrop_contract(None)
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.plus_days(7).seconds(),
                            end_time: current_time.plus_days(14).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    //end campaign
    suite
        .manage_campaign(
            bob,
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError { .. } => {}
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        )
        .manage_campaign(
            carol,
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError { .. } => {}
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        )
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert!(campaign.closed.is_none());
        })
        .manage_campaign(
            alice, // alice can end the campaign since it's the owner
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice, // alice tries closing the campaign again
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::CampaignError { reason } => {
                        assert_eq!(reason, "campaign has already been closed");
                    }
                    _ => panic!("Wrong error type, should return ContractError::CampaignError"),
                }
            },
        )
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert!(campaign.closed.is_some());
        });

    // let's create a new campaign
    suite
        .instantiate_claimdrop_contract(None)
        .manage_campaign(
            // Alice is owner of new contract
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(), // Name can be same as closed one
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(), // Use a fresh current_time if logic depends on it relative to now
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.plus_days(7).seconds(),
                            end_time: current_time.plus_days(14).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.manage_campaign(
        carol, // carol can't since it's not the owner of this new contract instance
        CampaignAction::CloseCampaign {},
        &[],
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::OwnershipError { .. } => {} // Should be NotOwner
                _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
            }
        },
    );

    // let's update the ownership of the contract
    suite
        .update_ownership(
            alice, // Current owner of the new contract
            cw_ownable::Action::TransferOwnership {
                new_owner: carol.to_string(),
                expiry: None,
            },
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .update_ownership(
            carol,
            cw_ownable::Action::AcceptOwnership {},
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // now only carol can end the new campaign.
    suite
        .manage_campaign(
            alice, // alice can't since it renounced the ownership for this instance
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError { .. } => {} // Should be NotOwner
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        )
        .manage_campaign(
            carol, // Carol is the new owner
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );
}

#[test]
fn can_query_claims_after_campaign_is_closed() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let dan = &suite.senders[3].clone(); // Dan is owner
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(10_000))];

    suite
        .instantiate_claimdrop_contract(Some(dan.to_string()))
        .add_allocations(
            dan,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            dan,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"), // Contract funded with 100k
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25), // Alice gets 2500 from this
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75), // Alice gets 7500 from this
                            start_time: current_time.plus_days(7).seconds(),
                            end_time: current_time.plus_days(14).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            dan,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.name, "Test Airdrop I");
        });

    // suite.add_week(); // Time passes, vesting might start if campaign start_time allows

    // claim
    // alice gets 2500 in lump sum if campaign started.
    // Here, campaign starts immediately (current_time.seconds())
    // Lump sum starts immediately.
    suite
        .claim(
            alice, //alice claims for herself
            Some(alice.to_string()),
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap(); // Alice claims 2500
            },
        )
        .query_claimed(Some(alice), None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize);
            assert_eq!(
                claimed_response.claimed[0],
                (alice.to_string(), coin(2_500u128, "uom"))
            );
        })
        .query_claimed(Some(bob), None, None, |result| {
            let claimed_response = result.unwrap();
            assert!(claimed_response.claimed.is_empty());
        });

    suite.add_week(); // Advance 7 days. Vesting starts. All of lump sum available.
                      // Vesting also starts if its start_time is <= current_time + 7 days.
                      // Vesting start_time is current_time + 7 days. So vesting just begins.
                      // Nothing from vesting available yet on day 7 itself, needs 1 sec more for 1st portion.
                      // Let's advance one more day to be sure some vesting happened.
    suite.add_day(); // Total 8 days passed. 1 day of vesting (7500/7 = 1071)

    suite.query_rewards(alice, |result| {
        // Claimed: 2500 (lump sum)
        // Available from vesting: 1 day = 1071 (approx)
        // Pending: 10000 - 2500 = 7500
        // Available to claim now = 1071 from vesting
        assert_eq!(
            result.unwrap(),
            RewardsResponse {
                claimed: coins(2_500u128, "uom"),
                pending: coins(7500, "uom"),
                available_to_claim: coins(1071, "uom"), // 7500 / 7 days for 1 day
            }
        );
    });

    // closing campaign by Dan (owner)
    suite
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.claimed, coin(2_500u128, "uom")); // Only Alice's initial claim
        })
        .query_balance("uom", dan, |result| {
            // Dan's balance before refund
            assert_eq!(result, Uint128::new(1_000_000_000 - 100_000)); // Initial funding
        })
        .manage_campaign(
            dan,
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance("uom", dan, |result| {
            // Dan gets refund of (100_000 initial_fund - 2_500 claimed_by_alice) = 97_500
            assert_eq!(result, Uint128::new(1_000_000_000 - 100_000 + 97_500));
        })
        .query_rewards(alice, |result| {
            // After campaign close
            let rewards_response = result.unwrap();
            assert_eq!(rewards_response.claimed, coins(2_500u128, "uom")); // What was claimed remains
            assert!(rewards_response.pending.is_empty()); // No more pending
            assert!(rewards_response.available_to_claim.is_empty()); // Nothing available
        })
        .query_claimed(None, None, None, |result| {
            // Query all claims
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize); // Only Alice claimed
            assert_eq!(
                claimed_response.claimed[0],
                (alice.to_string(), coin(2_500u128, "uom"))
            );
        });
}

#[test]
fn renouncing_contract_owner_makes_prevents_creating_campaigns() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone(); // Default owner
    let bob = &suite.senders[1].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (bob.to_string(), Uint128::new(10_000)),
    ];

    suite
        .instantiate_claimdrop_contract(None) // Alice is owner
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.plus_days(7).seconds(),
                            end_time: current_time.plus_days(14).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.add_week(); // Advance time

    // can claim
    suite.claim(
        bob,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    suite
        .update_ownership(
            bob, // Bob is not owner
            cw_ownable::Action::RenounceOwnership {},
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError(e) => match e {
                        OwnershipError::NotOwner => {}
                        _ => panic!("Wrong error type, should return OwnershipError::NotOwner"),
                    },
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        )
        .update_ownership(
            alice, // Alice is owner
            cw_ownable::Action::RenounceOwnership {},
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap(); // Alice renounces
            },
        )
        // can claim even if owner renounced
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        //end campaign fails as no owner
        .manage_campaign(
            alice, // Alice tries, but is no longer owner
            CampaignAction::CloseCampaign {},
            &[],
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError(e) => match e {
                        OwnershipError::NoOwner => {} // Correct: No owner to perform this action
                        _ => panic!(
                            "Wrong error type, should return OwnershipError::NoOwner but got {e:?}"
                        ),
                    },
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        )
        // Creating new campaign also fails
        .manage_campaign(
            alice, // Alice tries, but no owner
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop II".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![ /* ... */ ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError(e) => match e {
                        OwnershipError::NoOwner => {}
                        _ => panic!(
                            "Wrong error type, should return OwnershipError::NoOwner but got {e:?}"
                        ),
                    },
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        );
}

#[test]
fn can_claim_dust_without_new_claims() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(17))];

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(23, "uom"),
                    distribution_type: vec![DistributionType::LinearVesting {
                        percentage: Decimal::percent(100),
                        start_time: current_time.seconds(),
                        end_time: current_time.plus_days(60).seconds(),
                        cliff_duration: None,
                    }],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(60).seconds(), // Campaign ends when vesting ends
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_campaign(|result| {
            let campaign = result.unwrap();
            assert_eq!(campaign.name, "Test Airdrop I");
        });

    for _ in 0..59 {
        // Go to day 59 (0-indexed, so 59th day after start)
        suite.add_day();
    }
    // At day 59, 59/60 of 17 should be vested. 17 * 59 / 60 = 16.71 => 16
    suite
        .claim(
            alice,
            Some(alice.to_string()),
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_claimed(Some(alice), None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize);
            assert_eq!(
                claimed_response.claimed[0],
                (alice.to_string(), coin(16u128, "uom")) // Rounded down
            );
        });

    suite.add_day(); // Day 60. Vesting ends. Campaign ends.
                     // All 17 should be claimable. 16 already claimed. 1 remaining (dust).

    // executing the claiming here, will result on the compute_claimable_amount::new_claims being empty,
    // as the claim_amount will be zero, while the rounding_error_compensation_amount will be 1.
    // This relies on get_compensation_for_rounding_errors.
    suite
        .claim(
            alice,
            Some(alice.to_string()),
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_claimed(Some(alice), None, None, |result| {
            let claimed_response = result.unwrap();
            assert_eq!(claimed_response.claimed.len(), 1usize);
            assert_eq!(
                claimed_response.claimed[0],
                (alice.to_string(), coin(17u128, "uom")) // Total 17 claimed
            );
        });
}

#[test]
fn cant_end_distribution_type_after_campaign() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    suite
        .instantiate_claimdrop_contract(None)
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LinearVesting {
                        percentage: Decimal::percent(100),
                        start_time: current_time.seconds(),
                        end_time: current_time.plus_days(30).seconds(), // Dist ends after campaign
                        cliff_duration: None,
                    }],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(7).seconds(), // Campaign ends before dist
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::InvalidEndDistributionTime { .. } => {}
                    _ => panic!(
                        "Wrong error type, should return ContractError::InvalidEndDistributionTime"
                    ),
                }
            },
        )
        .manage_campaign(
            // Valid case: dist ends with campaign
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop II".to_string(), // Changed name
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LinearVesting {
                        percentage: Decimal::percent(100),
                        start_time: current_time.seconds(),
                        end_time: current_time.plus_days(7).seconds(),
                        cliff_duration: None,
                    }],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(7).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Must instantiate a new contract or close the previous one before creating another "Test Airdrop I"
    // Assuming we want a new contract for this next test case:
    suite.instantiate_claimdrop_contract(None);
    suite
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop III".to_string(), // Changed name
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LinearVesting {
                        percentage: Decimal::percent(100),
                        start_time: current_time.seconds(),
                        end_time: current_time.plus_days(6).seconds(), // Dist ends before campaign here, which is fine.
                        cliff_duration: None,
                    }],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(7).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );
}

#[test]
fn test_add_allocations() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let current_time = &suite.get_time();

    suite.instantiate_claimdrop_contract(None); // Alice is owner by default

    // Add allocations BEFORE creating campaign
    let allocations = &vec![
        (alice.to_string(), Uint128::new(100_000)),
        (bob.to_string(), Uint128::new(200_000)),
        (carol.to_string(), Uint128::new(300_000)),
    ];
    suite.add_allocations(
        // Owner adds allocations
        alice,
        allocations,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    suite
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(600_000, "uom"), // Sum of allocations
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.plus_days(1).seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.plus_days(8).seconds(),
                            end_time: current_time.plus_days(15).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.plus_days(1).seconds(),
                    end_time: current_time.plus_days(15).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite
        .query_allocations(Some(alice), None, None, |result| {
            let allocation = result.unwrap();
            assert_eq!(allocation.allocations.len(), 1);
            assert_eq!(
                allocation.allocations[0],
                (alice.to_string(), coin(100_000, "uom"))
            );
        })
        .query_allocations(Some(bob), None, None, |result| {
            let allocation = result.unwrap();
            assert_eq!(allocation.allocations.len(), 1);
            assert_eq!(
                allocation.allocations[0],
                (bob.to_string(), coin(200_000, "uom"))
            );
        })
        .query_allocations(Some(carol), None, None, |result| {
            let allocation = result.unwrap();
            assert_eq!(allocation.allocations.len(), 1);
            assert_eq!(
                allocation.allocations[0],
                (carol.to_string(), coin(300_000, "uom"))
            );
        })
        .add_allocations(
            // Try adding by non-owner
            bob,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError(e) => match e {
                        OwnershipError::NotOwner => {}
                        _ => panic!("Wrong error type, should return OwnershipError::NotOwner"),
                    },
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        );

    // test allocations pagination
    // Note: Map iteration order means we should sort for robust tests if order matters.
    // The addresses are alice, bob, carol.
    suite
        .query_allocations(None, None, Some(2u16), |result| {
            let allocation_resp = result.unwrap();
            let mut allocations_vec = allocation_resp.allocations;
            allocations_vec.sort_by(|a, b| a.0.cmp(&b.0)); // Sort by address
            assert_eq!(allocations_vec.len(), 2);
            assert_eq!(
                allocations_vec,
                vec![
                    (alice.to_string(), coin(100_000, "uom")),
                    (carol.to_string(), coin(300_000, "uom"))
                ]
            );
        })
        .query_allocations(None, Some(carol), None, |result| {
            // Start after bob
            let allocation_resp = result.unwrap();
            let mut allocations_vec = allocation_resp.allocations;
            allocations_vec.sort_by(|a, b| a.0.cmp(&b.0));
            assert_eq!(
                allocations_vec,
                vec![(bob.to_string(), coin(200_000, "uom"))]
            );
        });
}
#[test]
fn test_add_duplicated_allocation() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    // let carol = &suite.senders[2].clone(); // Carol not used here
    // let current_time = &suite.get_time(); // current_time not strictly needed if campaign creation is not the focus

    suite.instantiate_claimdrop_contract(None); // Alice is owner

    // add allocations first
    let allocations_initial = &vec![
        (alice.to_string(), Uint128::new(100_000)),
        (bob.to_string(), Uint128::new(200_000)),
    ];
    suite.add_allocations(
        alice,
        allocations_initial,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Try to add allocations with a duplicate
    let allocations_duplicate = &vec![
        (bob.to_string(), Uint128::new(50_000)), // Bob is a duplicate
        (suite.senders[2].clone().to_string(), Uint128::new(300_000)), // New address (Carol)
    ];

    suite.add_allocations(
        alice,
        allocations_duplicate,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::AllocationAlreadyExists { address } => {
                    assert_eq!(address, bob.to_string()); // Fails on Bob
                }
                _ => {
                    panic!("Wrong error type, should return ContractError::AllocationAlreadyExists")
                }
            }
        },
    );
}

#[test]
fn cant_add_allocations_with_invalid_placeholders() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone();

    let aave = "0x24a42fD28C976A61Df5D00D0599C34c4f90748c8";
    let valid_mantra_address = "mantra1w8e2wyzhrg3y5ghe9yg0xn0u7548e627zs7xahfvn5l63ry2x8zsqru7xd";
    let valid_mantra_address_uppercase =
        "MANTRA1W8E2WYZHRG3Y5GHE9YG0XN0U7548E627ZS7XAHFVN5L63RY2X8ZSQRU7XD";
    let invalid_chars = "invalid\x00address"; // control character should fail
    let invalid_too_long = "0x24a42fD28C976A61Df5D00D0599C34c4f90748c80x24a42fD28C976A61Df5D00D
    0599C34c4f90748c80x24a42fD28C976A61Df5D00D0599C34c4f90748c80x24a42fD28C976A61Df5D00D0599C34c4f9074
    8c80x24a42fD28C976A61Df5D00D0599C34c4f90748c80x24a42fD28C976A61Df5D00D0599C34c4f90748casuwsa";

    suite.instantiate_claimdrop_contract(None); // Alice is owner

    // add allocations first
    let allocations_initial = &vec![
        (aave.to_string(), Uint128::new(100_000)),
        (valid_mantra_address.to_string(), Uint128::new(200_000)),
    ];
    suite.add_allocations(
        alice,
        allocations_initial,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    let allocations = &vec![(
        valid_mantra_address_uppercase.to_string(),
        Uint128::new(100_000),
    )];

    suite.add_allocations(
        alice,
        allocations,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::AllocationAlreadyExists { address } => {
                    assert_eq!(address, valid_mantra_address.to_string());
                }
                _ => {
                    panic!("Wrong error type, should return ContractError::AllocationAlreadyExists")
                }
            }
        },
    );

    let allocations = &vec![(invalid_chars.to_string(), Uint128::new(100_000))];

    suite.add_allocations(
        alice,
        allocations,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::InvalidInput { reason } => {
                    assert_eq!(
                        reason,
                        format!(
                            "placeholder address '{invalid_chars}' contains control characters"
                        )
                        .to_string()
                    );
                }
                _ => {
                    panic!("Wrong error type, should return ContractError::InvalidInput")
                }
            }
        },
    );

    let allocations = &vec![(invalid_too_long.to_string(), Uint128::new(100_000))];

    suite.add_allocations(
        alice,
        allocations,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::InvalidInput { reason } => {
                    assert_eq!(
                        reason,
                        format!(
                            "address '{}' must be between 1 and {} characters long (got {})",
                            invalid_too_long,
                            MAX_PLACEHOLDER_ADDRESS_LEN,
                            invalid_too_long.len()
                        )
                        .to_string()
                    );
                }
                _ => {
                    panic!("Wrong error type, should return ContractError::InvalidInput")
                }
            }
        },
    );
}

#[test]
fn test_allocation_batch_size_limit() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone();

    suite.instantiate_claimdrop_contract(None);

    // Create a batch that exceeds the limit
    let mut large_batch = Vec::new();
    for i in 0..=MAX_ALLOCATION_BATCH_SIZE {
        large_batch.push((format!("address{i}"), Uint128::new(100)));
    }

    suite.add_allocations(
        alice,
        &large_batch,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::BatchSizeLimitExceeded { actual, max } => {
                    assert_eq!(actual, MAX_ALLOCATION_BATCH_SIZE + 1);
                    assert_eq!(max, MAX_ALLOCATION_BATCH_SIZE);
                }
                _ => {
                    panic!("Wrong error type, should return ContractError::BatchSizeLimitExceeded")
                }
            }
        },
    );

    // Test that exactly 3000 allocations work fine
    let mut max_batch = Vec::new();
    for i in 0..MAX_ALLOCATION_BATCH_SIZE {
        max_batch.push((format!("addr{i}"), Uint128::new(100)));
    }

    suite.add_allocations(
        alice,
        &max_batch,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );
}

#[test]
fn can_query_placeholder_allocation() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();

    let aave = "0x24a42fD28C976A61Df5D00D0599C34c4f90748c8".to_lowercase();

    suite.instantiate_claimdrop_contract(None); // Alice is owner

    // add allocations first
    let allocations_initial = &vec![
        (aave.to_string(), Uint128::new(100_000)),
        // saving bob valid address uppercase, but since it's a valid bech32
        (bob.to_string().to_uppercase(), Uint128::new(500_000)),
    ];

    suite
        .add_allocations(
            alice,
            allocations_initial,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_allocations(None, None, None, |result| {
            let response = result.unwrap();

            let allocations = response.allocations;
            assert_eq!(allocations.len(), 2);
            assert_eq!(allocations[0].0, aave);
            assert_eq!(allocations[0].1, coin(100_000, ""));

            assert_eq!(allocations[1].0, bob.to_string());
            assert_eq!(allocations[1].1, coin(500_000, ""));
        });
}

#[test]
fn test_cannot_add_allocations_after_campaign_start() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let current_time = &suite.get_time();

    suite.instantiate_claimdrop_contract(None); // Alice is owner

    suite
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::percent(100),
                        start_time: current_time.plus_days(1).seconds(),
                    }],
                    start_time: current_time.plus_days(1).seconds(), // Campaign starts in 1 day
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Upload allocations
    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)), // Reduced for test clarity
        (bob.to_string(), Uint128::new(20_000)),
        (carol.to_string(), Uint128::new(300_000)),
    ];

    suite.add_day(); // Advance 1 day, campaign is not yet started because start_time is current_time.plus_days(1)
                     // To make campaign started, we need to advance past its start_time.
                     // If campaign_start_time = current_time_at_setup.plus_days(1).seconds(),
                     // then suite.add_day() makes current_time = current_time_at_setup + 1 day.
                     // So, campaign has just started.

    //Let's add one more day to be sure campaign has started
    suite.add_day();

    suite.add_allocations(
        alice,
        allocations,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::CampaignError { reason } => {
                    assert_eq!(
                        reason,
                        "cannot upload allocations after campaign has started"
                    );
                }
                _ => panic!("Wrong error type, should return ContractError::CampaignError"),
            }
        },
    );
}

#[test]
fn test_replace_address() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone(); // Owner
    let bob = &suite.senders[1].clone(); // Old address
    let carol = &suite.senders[2].clone(); // New address
    let dan = &suite.senders[3].clone(); // New address
    let current_time = &suite.get_time();

    // Upload initial allocation for Bob
    let allocations = &vec![(bob.to_string(), Uint128::new(100_000))];

    suite
        .instantiate_claimdrop_contract(None) // Alice is owner
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );
    // Create campaign AFTER allocations are set, so replace_address can be tested before start
    suite
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "Test replace address".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"), // Matches Bob's allocation
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::percent(100),               // All at once
                        start_time: current_time.plus_days(1).seconds(), // Starts tomorrow
                    }],
                    start_time: current_time.plus_days(1).seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // At this point, campaign hasn't started. Bob has an allocation. Carol doesn't.
    // Bob has made no claims.

    // Replace Bob with Carol
    suite
        .replace_address(
            // Non-owner tries
            carol,
            bob,
            carol,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError(e) => match e {
                        OwnershipError::NotOwner => {}
                        _ => panic!("Wrong error type, should return OwnershipError::NotOwner"),
                    },
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        )
        .replace_address(
            // Owner replaces
            alice,
            bob,
            carol,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Verify Bob has no allocation or claims, Carol has Bob's original allocation
    suite
        .query_allocations(Some(bob), None, None, |result| {
            let allocation = result.unwrap();
            assert!(allocation.allocations.is_empty());
        })
        .query_claimed(Some(bob), None, None, |result| {
            let claimed_response = result.unwrap();
            assert!(claimed_response.claimed.is_empty());
        })
        .query_allocations(Some(carol), None, None, |result| {
            let allocation = result.unwrap();
            assert_eq!(allocation.allocations.len(), 1);
            assert_eq!(
                allocation.allocations[0],
                (carol.to_string(), coin(100_000, "uom"))
            );
        })
        .query_claimed(Some(carol), None, None, |result| {
            let claimed_response = result.unwrap();
            assert!(claimed_response.claimed.is_empty()); // Carol shouldn't have claims yet
        });

    // Now, let's test scenario where Bob *had* claims
    // Re-setup: New contract, Bob gets allocation, claims some, then replace.
    suite.instantiate_claimdrop_contract(None); // Alice is owner
    suite.add_allocations(
        alice,
        allocations,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    ); // Bob gets 100k again
    suite
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop II".to_string(),
                    description: "Test replace address with claims".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(50),   // 50% now
                            start_time: current_time.seconds(), // Starts now
                        },
                        DistributionType::LumpSum {
                            // Remaining 50% later
                            percentage: Decimal::percent(50),
                            start_time: current_time.plus_days(5).seconds(),
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Bob claims the first 50% (50_000)
    suite.claim(
        bob,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );
    suite.query_claimed(Some(bob), None, None, |res| {
        let claim = res.unwrap();
        assert_eq!(claim.claimed[0].1, coin(50_000, "uom"));
    });

    // Now replace Bob (who has claims) with Carol (who has no allocation yet in this campaign)
    // Before campaign starts for the *second* distribution type.
    suite.replace_address(
        alice,
        bob,
        carol,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Check states: Bob should have no allocation/claims. Carol should have Bob's allocation and his claims.
    suite.query_allocations(Some(bob), None, None, |result| {
        let allocation = result.unwrap();
        assert!(allocation.allocations.is_empty());
    });
    suite.query_claimed(Some(bob), None, None, |result| {
        let claimed_response = result.unwrap();
        assert!(claimed_response.claimed.is_empty());
    });

    suite.query_allocations(Some(carol), None, None, |result| {
        let allocation = result.unwrap();
        assert_eq!(allocation.allocations[0].1, coin(100_000, "uom"));
    });
    suite.query_claimed(Some(carol), None, None, |result| {
        let claim = result.unwrap();
        assert_eq!(claim.claimed[0].1, coin(50_000, "uom")); // Carol now has Bob's claim
    });

    // Advance time so Carol can claim the second part
    for _ in 0..6 {
        suite.add_day();
    }
    suite.claim(
        carol,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    ); // Carol claims the next 50k
    suite.query_claimed(Some(carol), None, None, |result| {
        let claim = result.unwrap();
        assert_eq!(claim.claimed[0].1, coin(100_000, "uom")); // Carol has total 100k
    });

    // try to replace the address of someone who didn't have an allocation, i.e. dan

    suite.replace_address(
        alice,
        dan,
        carol,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::NoAllocationFound { address } => {
                    assert_eq!(address, dan.to_string());
                }
                _ => panic!("Wrong error type, should return ContractError::NoAllocationFound"),
            }
        },
    );
}

#[test]
fn test_remove_address() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone(); // Owner
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let dan = &suite.senders[3].clone();
    let placeholder = &Addr::unchecked("vitalik.eth");
    let current_time = &suite.get_time();

    // Upload initial allocation for Bob
    let allocations = &vec![
        (bob.to_string(), Uint128::new(100_000)),
        (carol.to_string(), Uint128::new(100_000)),
        (placeholder.to_string(), Uint128::new(500_000)),
    ];

    suite
        .instantiate_claimdrop_contract(None) // Alice is owner
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "Test replace address".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"), // Matches Bob's allocation
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::percent(100),               // All at once
                        start_time: current_time.plus_days(1).seconds(), // Starts tomorrow
                    }],
                    start_time: current_time.plus_days(1).seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // At this point, campaign hasn't started. Bob and Carol have an allocation.
    //
    // The campaign manager notices Carol's allocation is incorrect. Removes it

    suite.remove_address(
        // Non-owner tries
        carol,
        bob,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::OwnershipError(e) => match e {
                    OwnershipError::NotOwner => {}
                    _ => panic!("Wrong error type, should return OwnershipError::NotOwner"),
                },
                _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
            }
        },
    );

    // tries to remove an address that doesn't even have an allocation
    suite
        .query_allocations(Some(dan), None, None, |result| {
            let allocation = result.unwrap();
            assert!(allocation.allocations.is_empty());
        })
        .remove_address(alice, dan, |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        });

    // remove carol
    suite
        .query_allocations(Some(carol), None, None, |result| {
            let allocation = result.unwrap();
            assert_eq!(allocation.allocations[0].1, coin(100_000, "uom"));
        })
        .remove_address(
            alice,
            carol,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_allocations(Some(carol), None, None, |result| {
            let allocation = result.unwrap();
            assert!(allocation.allocations.is_empty());
        });

    // once carol's allocation is removed, the corrected one can be added
    let allocations = &vec![(carol.to_string(), Uint128::new(50_000))];
    suite
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_allocations(Some(carol), None, None, |result| {
            let allocation = result.unwrap();
            assert_eq!(allocation.allocations[0].1, coin(50_000, "uom"));
        });

    suite
        .query_allocations(Some(placeholder), None, None, |result| {
            let allocation = result.unwrap();
            assert_eq!(allocation.allocations[0].1, coin(500_000, "uom"));
        })
        .remove_address(
            alice,
            placeholder,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_allocations(Some(placeholder), None, None, |result| {
            let allocation = result.unwrap();
            assert!(allocation.allocations.is_empty());
        });

    // start the campaign
    suite.add_week();
    suite.remove_address(
        alice,
        carol,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::CampaignError { reason } => {
                    assert_eq!(
                        reason,
                        "cannot remove an address allocation after campaign has started"
                    );
                }
                _ => panic!("Wrong error type, should return ContractError::CampaignError"),
            }
        },
    );
}

#[test]
fn test_replace_placeholder_address() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone(); // Owner
    let bob = &suite.senders[1].clone(); // Old address
    let carol = &suite.senders[2].clone(); // New address
    let placeholder = &Addr::unchecked("placeholder"); // Another new address
    let current_time = &suite.get_time();

    // Upload initial allocation for Vitalik, who has not bridged from Ethereum to MANTRA yet
    let allocations = &vec![("vitalik.eth".to_string(), Uint128::new(100_000))];

    suite
        .instantiate_claimdrop_contract(None) // Alice is owner
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );
    // Create campaign AFTER allocations are set, so replace_address can be tested before start
    suite
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "Test replace address".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"), // Matches Bob's allocation
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::percent(100),               // All at once
                        start_time: current_time.plus_days(1).seconds(), // Starts tomorrow
                    }],
                    start_time: current_time.plus_days(1).seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.add_day();

    // Try to claim on behalf of Vitalik, before the address in properly replaced
    suite.claim(
        bob,
        Some("vitalik.eth".to_string()),
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::Std(e) => {
                    assert!(e.to_string().contains("Invalid input"));
                }
                _ => panic!("Wrong error type, should return ContractError::Std"),
            }
        },
    );

    let vitalik_addr = &Addr::unchecked("vitalik.eth");

    suite
        .query_allocations(Some(vitalik_addr), None, None, |result| {
            let allocation = result.unwrap();
            assert!(allocation.allocations[0].1 == coin(100_000, "uom"));
        })
        // can't replace a placeholder with another placeholder
        .replace_address(
            alice,
            &Addr::unchecked("vitalik.eth"),
            placeholder,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::Std(e) => {
                        assert!(e.to_string().contains("Invalid input"));
                    }
                    _ => panic!("Wrong error type, should return ContractError::Std"),
                }
            },
        )
        .replace_address(
            alice,
            &Addr::unchecked("vitalik.eth"),
            carol,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Verify Vitalik has no allocation or claims, Carol has Vitalik's original allocation
    suite
        .query_allocations(Some(vitalik_addr), None, None, |result| {
            let allocation = result.unwrap();
            assert!(allocation.allocations.is_empty());
        })
        .query_claimed(
            Some(vitalik_addr),
            None,
            None,
            |result: StdResult<ClaimedResponse>| {
                let err: StdError = result.unwrap_err();
                assert!(err.to_string().contains("Invalid input"));
            },
        )
        .query_allocations(Some(carol), None, None, |result| {
            let allocation = result.unwrap();
            assert_eq!(allocation.allocations.len(), 1);
            assert_eq!(
                allocation.allocations[0],
                (carol.to_string(), coin(100_000, "uom"))
            );
        });
}

#[test]
fn test_cant_replace_address_with_existing_allocation() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone(); // Owner
    let bob = &suite.senders[1].clone(); // Old address
    let carol = &suite.senders[2].clone(); // New address
    let current_time = &suite.get_time();

    // Upload initial allocation for Vitalik, who has not bridged from Ethereum to MANTRA yet
    let allocations = &vec![
        (bob.to_string(), Uint128::new(100_000)),
        (carol.to_string(), Uint128::new(50_000)),
    ];

    suite
        .instantiate_claimdrop_contract(None) // Alice is owner
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "Test replace address".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"), // Matches Bob's allocation
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::percent(100),               // All at once
                        start_time: current_time.plus_days(1).seconds(), // Starts tomorrow
                    }],
                    start_time: current_time.plus_days(1).seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.add_day();

    suite
        .query_allocations(Some(bob), None, None, |result| {
            let allocation = result.unwrap();
            assert!(allocation.allocations[0].1 == coin(100_000, "uom"));
        })
        .query_allocations(Some(carol), None, None, |result| {
            let allocation = result.unwrap();
            assert!(allocation.allocations[0].1 == coin(50_000, "uom"));
        })
        .replace_address(
            alice,
            bob,
            carol,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::AllocationAlreadyExists { address } => {
                        assert_eq!(address, carol.to_string());
                    }
                    _ => panic!(
                        "Wrong error type, should return ContractError::AllocationAlreadyExists"
                    ),
                }
            },
        );
}

#[test]
fn test_blacklist_address() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone(); // Owner
    let bob = &suite.senders[1].clone();
    let carol: &Addr = &suite.senders[2].clone(); // Address to be blacklisted
    let placeholder = &Addr::unchecked("bad.placeholder"); // Another address to be blacklisted
    let current_time = &suite.get_time();

    suite.instantiate_claimdrop_contract(None); // Alice is owner

    // Upload allocations
    let allocations = &vec![
        (alice.to_string(), Uint128::new(100_000)),
        (bob.to_string(), Uint128::new(200_000)),
        (carol.to_string(), Uint128::new(300_000)),
        (placeholder.to_string(), Uint128::new(400_000)),
    ];
    suite.add_allocations(
        alice,
        allocations,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    suite
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(600_000, "uom"), // Sum of allocations
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::percent(100),
                        start_time: current_time.plus_days(1).seconds(), // Starts tomorrow
                    }],
                    start_time: current_time.plus_days(1).seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(1_000_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite
        .blacklist_address(
            // Non-owner fails
            bob,
            carol,
            true,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::OwnershipError(e) => match e {
                        OwnershipError::NotOwner => {}
                        _ => panic!("Wrong error type, should return OwnershipError::NotOwner"),
                    },
                    _ => panic!("Wrong error type, should return ContractError::OwnershipError"),
                }
            },
        )
        .query_is_blacklisted(carol, |result| {
            let blacklist_status = result.unwrap();
            assert!(!blacklist_status.is_blacklisted);
        })
        .blacklist_address(
            // Owner succeeds
            alice,
            carol,
            true,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .blacklist_address(
            alice,
            placeholder,
            true,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_is_blacklisted(carol, |result| {
            let blacklist_status = result.unwrap();
            assert!(blacklist_status.is_blacklisted);
        })
        .query_is_blacklisted(placeholder, |result| {
            let blacklist_status = result.unwrap();
            assert!(blacklist_status.is_blacklisted);
        });

    suite.add_day(); // Advance 1 day, campaign starts

    // Carol (blacklisted) tries to claim, should fail
    suite.claim(
        carol,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::AddressBlacklisted => {}
                _ => panic!("Wrong error type, should return ContractError::AddressBlacklisted"),
            }
        },
    );

    // remove from blacklist, claiming should work
    suite
        .blacklist_address(
            alice,
            carol,
            false, // Unblacklist
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .claim(
            carol,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                // Carol claims successfully
                result.unwrap();
            },
        );
}

#[test]
fn test_claim_more_than_currently_available_fails() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let dan = &suite.senders[3].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (dan.to_string(), Uint128::new(35_000)),
    ];

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.plus_days(7).seconds(),
                            end_time: current_time.plus_days(14).seconds(),
                            cliff_duration: Some(3 * 86_400u64),
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Advance time for lump sum to be available
    suite.add_day();

    let alice_lump_sum_share = Uint128::from(2_500u128); // 25% of the total allocation for alice
    let excessive_amount = alice_lump_sum_share + Uint128::new(1);

    // At this point, only lump_sum_share is available. Vesting hasn't started/cliffed.
    suite.claim(
        alice,
        None,
        Some(excessive_amount),
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::InvalidClaimAmount { reason } => {
                    assert!(reason.contains("exceeds available claimable amount"));
                }
                _ => panic!("Wrong error type, should return ContractError::InvalidClaimAmount"),
            }
        },
    );
}

#[test]
fn test_partial_claim_lump_sum() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let dan = &suite.senders[3].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (dan.to_string(), Uint128::new(35_000)),
    ];

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.plus_days(7).seconds(),
                            end_time: current_time.plus_days(14).seconds(),
                            cliff_duration: Some(3 * 86_400u64),
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(14).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Advance time for lump sum to be available
    suite.add_day();

    let alice_lump_sum_share = Uint128::new(2_500);
    let partial_claim_amount = Uint128::new(1_250);

    assert!(partial_claim_amount < alice_lump_sum_share);

    // Query rewards before claim
    suite.query_rewards(alice, |result| {
        let rewards: RewardsResponse = result.unwrap();
        assert_eq!(
            rewards,
            RewardsResponse {
                claimed: vec![],
                pending: vec![coin(Uint128::new(10_000).u128(), "uom")],
                available_to_claim: vec![coin(alice_lump_sum_share.u128(), "uom")]
            }
        );
    });

    // Alice performs a partial claim
    suite
        .claim(
            alice,
            Some(alice.to_string()),
            Some(partial_claim_amount),
            |res: Result<AppResponse, anyhow::Error>| {
                res.unwrap();
            },
        )
        .query_balance("uom", alice, |balance| {
            assert_eq!(
                balance,
                Uint128::new(1_000_000_000 - 100_000 + partial_claim_amount.u128())
            );
        });

    // Query rewards after partial claim
    let remaining_lump_sum = alice_lump_sum_share.saturating_sub(partial_claim_amount);

    suite.query_rewards(alice, |result| {
        let rewards = result.unwrap();

        let total_pending = Uint128::new(10_000).saturating_sub(partial_claim_amount);

        assert_eq!(
            rewards,
            RewardsResponse {
                claimed: vec![coin(partial_claim_amount.u128(), "uom")],
                pending: vec![coin(total_pending.u128(), "uom")],
                available_to_claim: vec![coin(remaining_lump_sum.u128(), "uom")]
            }
        );
    });

    // alice claims the rest of the lump sum
    suite.claim(
        alice,
        None,
        Some(remaining_lump_sum),
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );
    suite.query_balance("uom", alice, |balance| {
        assert_eq!(
            balance,
            Uint128::new(1_000_000_000 - 100_000 + alice_lump_sum_share.u128())
        );
    });
    suite.query_rewards(alice, |result| {
        let rewards = result.unwrap();
        let total_pending_after_full_lump =
            Uint128::new(10_000).saturating_sub(alice_lump_sum_share);

        assert_eq!(
            rewards,
            RewardsResponse {
                claimed: vec![coin(alice_lump_sum_share.u128(), "uom")],
                pending: vec![coin(total_pending_after_full_lump.u128(), "uom")],
                available_to_claim: vec![]
            }
        );
    });
}

#[test]
fn test_partial_claim_lumpsum_and_linear_vesting() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let dan = &suite.senders[3].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (dan.to_string(), Uint128::new(35_000)),
    ];

    let reward_denom = "uom";

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, reward_denom),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.seconds(),
                            end_time: current_time.plus_days(5).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(5).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Advance time, lump sum and 1/5th of vesting is available
    suite.add_day();

    let alice_lump_sum_share = Uint128::new(2_500);
    let expected_vested_amount = Uint128::new(7_500).checked_div(Uint128::new(5)).unwrap();
    let total_currently_available = alice_lump_sum_share + expected_vested_amount; // 2_500 + 1_500 = 4_000

    suite.query_rewards(alice, |result| {
        let rewards = result.unwrap();
        assert_eq!(
            rewards.available_to_claim,
            vec![coin(total_currently_available.u128(), reward_denom)]
        );
    });

    let alice_partial_lump_sum_claim = Uint128::new(2_000);

    // User makes a claim. This will first take from lump sum.
    // To test partial vesting claim, let's first claim entire lump sum.
    suite
        .claim(
            alice,
            None,
            Some(alice_partial_lump_sum_claim),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_rewards(alice, |result| {
            let rewards = result.unwrap();
            assert_eq!(
                rewards.available_to_claim,
                vec![coin(
                    total_currently_available.u128() - alice_partial_lump_sum_claim.u128(),
                    reward_denom
                )],
            );
        });

    // claim remaining of lump sum
    suite
        .claim(
            alice,
            None,
            Some(alice_lump_sum_share.saturating_sub(alice_partial_lump_sum_claim)),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_rewards(alice, |result| {
            let rewards = result.unwrap();
            assert_eq!(
                rewards.available_to_claim,
                vec![coin(expected_vested_amount.u128(), reward_denom)]
            );
            assert_eq!(
                rewards.claimed,
                vec![coin(alice_lump_sum_share.u128(), reward_denom)]
            );
        });

    // now claim vesting share
    let partial_claim_vesting_only = Uint128::new(500);
    assert!(partial_claim_vesting_only < expected_vested_amount);

    // Now claim a part of the vested amount
    suite.claim(
        alice,
        None,
        Some(partial_claim_vesting_only),
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );

    let total_claimed_after_partial_vesting = alice_lump_sum_share + partial_claim_vesting_only;
    suite.query_balance(reward_denom, alice, |balance| {
        assert_eq!(
            balance,
            Uint128::new(1_000_000_000 - 100_000 + total_claimed_after_partial_vesting.u128())
        );
    });

    let remaining_vested_available =
        expected_vested_amount.saturating_sub(partial_claim_vesting_only);

    suite.query_rewards(alice, |result| {
        let rewards = result.unwrap();
        assert_eq!(
            rewards,
            RewardsResponse {
                claimed: vec![coin(
                    total_claimed_after_partial_vesting.u128(),
                    reward_denom
                )],
                pending: vec![coin(
                    Uint128::new(10_000 - total_claimed_after_partial_vesting.u128()).u128(),
                    reward_denom
                )],
                available_to_claim: vec![coin(remaining_vested_available.u128(), reward_denom)]
            }
        );
    });

    // move all the way to the end of the vesting period
    suite.add_day().add_day().add_day().add_day();

    let remaining_vested_available =
        Uint128::new(10_000 - total_claimed_after_partial_vesting.u128());

    suite.query_rewards(alice, |result| {
        let rewards = result.unwrap();
        assert_eq!(
            rewards.available_to_claim,
            vec![coin(remaining_vested_available.u128(), reward_denom)],
        );
    });

    // alice claims another chunk of the vested amount
    let partial_claim_vesting_only = Uint128::new(5_000);
    assert!(remaining_vested_available > partial_claim_vesting_only);

    suite
        .claim(
            alice,
            None,
            Some(partial_claim_vesting_only),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_rewards(alice, |result| {
            let rewards = result.unwrap();
            assert_eq!(
                rewards.available_to_claim,
                vec![coin(
                    remaining_vested_available.u128() - partial_claim_vesting_only.u128(),
                    reward_denom
                )],
            );
        })
        .claim(
            alice,
            None,
            Some(remaining_vested_available.saturating_sub(partial_claim_vesting_only)),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_rewards(alice, |result| {
            let rewards = result.unwrap();
            assert_eq!(
                rewards,
                RewardsResponse {
                    claimed: vec![coin(Uint128::new(10_000).u128(), reward_denom)],
                    pending: vec![],
                    available_to_claim: vec![]
                }
            );
        });
}

#[test]
fn test_claim_zero_amount_fails() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let dan = &suite.senders[3].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (dan.to_string(), Uint128::new(35_000)),
    ];

    let reward_denom = "uom";

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, reward_denom),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.seconds(),
                            end_time: current_time.plus_days(5).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(5).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Advance time, lump sum and 1/5th of vesting is available
    suite.add_day();

    suite.claim(
        alice,
        None,
        Some(Uint128::zero()),
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::InvalidClaimAmount { reason } => {
                    assert!(reason.contains("amount must be greater than zero"));
                }
                _ => panic!("Wrong error type, should return ContractError::InvalidClaimAmount"),
            }
        },
    );
}

#[test]
fn test_claim_full_amount_when_none_specified_after_partial_claims() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let dan = &suite.senders[3].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (dan.to_string(), Uint128::new(35_000)),
    ];

    let reward_denom = "uom";

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop, 土金, ك".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, reward_denom),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(25),
                            start_time: current_time.seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(75),
                            start_time: current_time.seconds(),
                            end_time: current_time.plus_days(5).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.seconds(),
                    end_time: current_time.plus_days(5).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Advance time, lump sum and 1/5th of vesting is available
    suite.add_day();

    let alice_lump_sum_share = Uint128::new(2_500);
    let expected_vested_amount = Uint128::new(7_500).checked_div(Uint128::new(5)).unwrap();
    let total_currently_available = alice_lump_sum_share + expected_vested_amount; // 2_500 + 1_500 = 4_000

    suite.query_rewards(alice, |result| {
        let rewards = result.unwrap();
        assert_eq!(
            rewards.available_to_claim,
            vec![coin(total_currently_available.u128(), reward_denom)]
        );
    });

    let partial_claim = Uint128::new(2_000);
    assert!(partial_claim < total_currently_available);

    // claim lump sum
    suite
        .claim(
            alice,
            None,
            Some(partial_claim),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_rewards(alice, |result| {
            let rewards = result.unwrap();
            assert_eq!(
                rewards.available_to_claim,
                vec![coin(
                    total_currently_available.u128() - partial_claim.u128(),
                    reward_denom
                )]
            );
            assert_eq!(
                rewards.claimed,
                vec![coin(partial_claim.u128(), reward_denom)]
            );
        });

    // now claim the remaining available amount with None
    suite.claim(
        alice,
        None,
        None,
        |res: Result<AppResponse, anyhow::Error>| {
            res.unwrap();
        },
    );

    suite.query_rewards(alice, |result| {
        let rewards = result.unwrap();
        assert_eq!(
            rewards,
            RewardsResponse {
                claimed: vec![coin(total_currently_available.u128(), reward_denom)],
                pending: vec![coin(
                    Uint128::new(10_000 - total_currently_available.u128()).u128(),
                    reward_denom
                )],
                available_to_claim: vec![],
            }
        );
    });

    // move a few days so more rewards from the vesting get available
    suite.add_day().add_day().add_day();
    // by now, 4/5th of the vesting have been unlocked, with 1/5th claimed and 1/5th left to be vested

    let expected_vested_amount = Uint128::new(7_500)
        .checked_div(Uint128::new(5))
        .unwrap()
        .checked_mul(Uint128::new(3))
        .unwrap();

    suite.query_rewards(alice, |result| {
        let rewards = result.unwrap();
        assert_eq!(
            rewards.available_to_claim,
            vec![coin(expected_vested_amount.u128(), reward_denom)],
        );
    });

    // alice claims another chunk of the vested amount, partially
    let partial_claim_vesting_only = expected_vested_amount.checked_div(Uint128::new(4)).unwrap();

    suite
        .claim(
            alice,
            None,
            Some(partial_claim_vesting_only),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_rewards(alice, |result| {
            let rewards = result.unwrap();
            assert_eq!(
                rewards.claimed,
                vec![coin(
                    total_currently_available.u128() + partial_claim_vesting_only.u128(),
                    reward_denom
                )],
            );
            assert_eq!(
                rewards.available_to_claim,
                vec![coin(partial_claim_vesting_only.u128() * 3, reward_denom)],
            );
        });

    // claim remaining with None
    suite
        .add_day()
        .claim(
            alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_rewards(alice, |result| {
            let rewards = result.unwrap();
            assert_eq!(
                rewards,
                RewardsResponse {
                    claimed: vec![coin(Uint128::new(10_000).u128(), reward_denom)],
                    pending: vec![],
                    available_to_claim: vec![]
                }
            );
        });
}

#[test]
fn test_claim_authorization() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![
        (alice.to_string(), Uint128::new(10_000)),
        (bob.to_string(), Uint128::new(10_000)),
        (carol.to_string(), Uint128::new(20_000)),
    ];

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Authorization".to_string(),
                    description: "Testing claim authorization".to_string(),
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
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.add_day();

    // Test 1: Bob tries to claim for Alice (should fail - unauthorized)
    suite.claim(
        bob,
        Some(alice.to_string()),
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::Unauthorized => {}
                _ => panic!("Wrong error type, should return ContractError::Unauthorized"),
            }
        },
    );

    // Test 2: Carol tries to claim for Bob (should fail - unauthorized)
    suite.claim(
        carol,
        Some(bob.to_string()),
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::Unauthorized => {}
                _ => panic!("Wrong error type, should return ContractError::Unauthorized"),
            }
        },
    );

    // Test 3: Alice (owner) can claim on behalf of Bob
    suite.claim(
        alice,
        Some(bob.to_string()),
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Test 4: Alice can claim for herself
    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Test 5: Carol can claim for herself
    suite.claim(
        carol,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify balances
    suite
        .query_balance("uom", alice, |balance| {
            assert_eq!(balance, Uint128::new(999_910_000)); // alice claimed her 10k
        })
        .query_balance("uom", bob, |balance| {
            assert_eq!(balance, Uint128::new(1_000_010_000)); // alice claimed 10k for bob
        })
        .query_balance("uom", carol, |balance| {
            assert_eq!(balance, Uint128::new(1_000_020_000)); // carol claimed her 20k
        });
}

#[test]
fn unvalidated_address_collisions_should_not_be_allowed() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);

    let alice = &suite.senders[0].clone();

    let allocations = &vec![
        (
            "0x24a42fD28C976A61Df5D00D0599C34c4f90748c8".to_string(),
            Uint128::new(10_000),
        ),
        (
            "0X24A42FD28C976A61DF5D00D0599C34C4F90748C8".to_string(),
            Uint128::new(20_000),
        ),
    ];

    suite
        .instantiate_claimdrop_contract(Some(alice.to_string()))
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                let err = result.unwrap_err().downcast::<ContractError>().unwrap();
                match err {
                    ContractError::AllocationAlreadyExists { .. } => {}
                    _ => panic!(
                        "Wrong error type, should return ContractError::AllocationAlreadyExists"
                    ),
                }
            },
        );
}

#[test]
fn test_manage_authorized_wallets_basic_functionality() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let alice = &suite.senders[0].clone(); // owner
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();

    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Test: Owner can authorize wallets
    suite.manage_authorized_wallets(
        alice,
        vec![bob.to_string(), carol.to_string()],
        true,
        &[],
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Test: Query authorized wallets
    suite.query_authorized_wallets(None, None, |result| {
        let response = result.unwrap();
        assert_eq!(response.wallets.len(), 2);
        assert!(response.wallets.contains(&bob.to_string()));
        assert!(response.wallets.contains(&carol.to_string()));
    });

    // Test: Query individual authorization status
    suite.query_is_authorized(alice.to_string(), |result| {
        let response = result.unwrap();
        assert!(response.is_authorized); // owner is always authorized
    });

    suite.query_is_authorized(bob.to_string(), |result| {
        let response = result.unwrap();
        assert!(response.is_authorized); // bob was authorized
    });

    // Test: Owner can unauthorize wallets
    suite.manage_authorized_wallets(
        alice,
        vec![bob.to_string()],
        false,
        &[],
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify bob is no longer authorized but carol still is
    suite.query_is_authorized(bob.to_string(), |result| {
        let response = result.unwrap();
        assert!(!response.is_authorized); // bob is no longer authorized
    });

    suite.query_is_authorized(carol.to_string(), |result| {
        let response = result.unwrap();
        assert!(response.is_authorized); // carol is still authorized
    });
}

#[test]
fn test_manage_authorized_wallets_nonpayable_enforcement() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let alice = &suite.senders[0].clone(); // owner
    let bob = &suite.senders[1].clone();

    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Test: Cannot send funds with ManageAuthorizedWallets message
    suite.manage_authorized_wallets(
        alice,
        vec![bob.to_string()],
        true,
        &coins(100, "uom"), // Trying to send funds should fail
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::PaymentError(_) => {}
                _ => panic!("Wrong error type, should return ContractError::PaymentError"),
            }
        },
    );
}

#[test]
fn test_manage_authorized_wallets_atomic_batch_operations() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let alice = &suite.senders[0].clone(); // owner
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();

    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Test: Batch operation with one invalid address should fail atomically
    suite.manage_authorized_wallets(
        alice,
        vec![
            bob.to_string(),
            "".to_string(), // Invalid address
            carol.to_string(),
        ],
        true,
        &[],
        |result: Result<AppResponse, anyhow::Error>| {
            // Should fail due to invalid address
            assert!(result.is_err());
        },
    );

    // Verify no addresses were authorized
    suite.query_is_authorized(bob.to_string(), |result| {
        let response = result.unwrap();
        assert!(!response.is_authorized);
    });

    suite.query_is_authorized(carol.to_string(), |result| {
        let response = result.unwrap();
        assert!(!response.is_authorized);
    });

    // Test: Valid batch operation should succeed
    suite.manage_authorized_wallets(
        alice,
        vec![bob.to_string(), carol.to_string()],
        true,
        &[],
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify both addresses were authorized
    suite.query_authorized_wallets(None, None, |result| {
        let response = result.unwrap();
        assert_eq!(response.wallets.len(), 2);
    });
}

#[test]
fn test_manage_authorized_wallets_unauthorized_access() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let alice = &suite.senders[0].clone(); // owner
    let bob = &suite.senders[1].clone(); // unauthorized user
    let carol = &suite.senders[2].clone();

    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Test: Non-owner cannot manage authorized wallets
    suite.manage_authorized_wallets(
        bob, // bob is not the owner
        vec![carol.to_string()],
        true,
        &[],
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::OwnershipError(cw_ownable::OwnershipError::NotOwner) => {}
                _ => panic!("Wrong error type, should return OwnershipError::NotOwner"),
            }
        },
    );

    // Verify carol was not authorized
    suite.query_is_authorized(carol.to_string(), |result| {
        let response = result.unwrap();
        assert!(!response.is_authorized);
    });
}

#[test]
fn test_manage_authorized_wallets_pagination() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(1_000_000_000, "uom")]);

    let alice = &suite.senders[0].clone(); // owner

    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Create 4 test addresses using the valid bech32 addresses from the suite (excluding owner)
    let addresses: Vec<String> = suite.senders[1..5]
        .iter()
        .map(|addr| addr.to_string())
        .collect();

    suite.manage_authorized_wallets(
        alice,
        addresses.clone(),
        true,
        &[],
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Test: Query all authorized wallets
    suite.query_authorized_wallets(None, None, |result| {
        let response = result.unwrap();
        assert_eq!(response.wallets.len(), 4);
    });

    // Test: Query with limit
    suite.query_authorized_wallets(None, Some(2), |result| {
        let response = result.unwrap();
        assert_eq!(response.wallets.len(), 2);
    });

    // Test: Query with start_after beyond all addresses
    suite.query_authorized_wallets(Some("zzz9999".to_string()), None, |result| {
        let response = result.unwrap();
        assert_eq!(response.wallets.len(), 0);
    });
}

#[test]
fn test_lump_sum_cannot_be_scheduled_after_campaign_end() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(200_000_000, "uom")]);

    let alice = &suite.senders[0].clone();
    let current_time = suite.get_time();

    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Test: Try to create a campaign with Lump Sum distribution scheduled after campaign end
    suite.manage_campaign(
        alice,
        CampaignAction::CreateCampaign {
            params: Box::new(CampaignParams {
                name: "Test Airdrop".to_string(),
                description: "Testing Lump Sum validation fix".to_string(),
                ty: "airdrop".to_string(),
                total_reward: coin(100_000, "uom"),
                distribution_type: vec![
                    DistributionType::LumpSum {
                        percentage: Decimal::percent(50),
                        // Lump Sum scheduled AFTER campaign end - this should fail
                        start_time: current_time.plus_days(10).seconds(),
                    },
                    DistributionType::LinearVesting {
                        percentage: Decimal::percent(50),
                        start_time: current_time.seconds(),
                        end_time: current_time.plus_days(7).seconds(),
                        cliff_duration: None,
                    },
                ],
                start_time: current_time.seconds(),
                // Campaign ends in 7 days, but Lump Sum is scheduled for day 10
                end_time: current_time.plus_days(7).seconds(),
            }),
        },
        &[], // No funds during campaign creation
        |result: Result<AppResponse, anyhow::Error>| {
            let err = result.unwrap_err().downcast::<ContractError>().unwrap();
            match err {
                ContractError::InvalidInput { reason } => {
                    assert!(
                        reason.contains("Lump Sum distribution start time"),
                        "Error message should mention Lump Sum distribution validation, got: {reason}"
                    );
                    assert!(
                        reason.contains("cannot be after campaign end time"),
                        "Error message should explain the issue, got: {reason}"
                    );
                }
                e => panic!(
                    "Wrong error type, should return ContractError::InvalidInput, got: {e:?}"
                ),
            }
        },
    );

    // Test: Create a valid campaign with Lump Sum distribution at campaign end time (edge case)
    suite.manage_campaign(
        alice,
        CampaignAction::CreateCampaign {
            params: Box::new(CampaignParams {
                name: "Valid Airdrop".to_string(),
                description: "Testing valid Lump Sum at campaign end".to_string(),
                ty: "airdrop".to_string(),
                total_reward: coin(100_000, "uom"),
                distribution_type: vec![
                    DistributionType::LumpSum {
                        percentage: Decimal::percent(50),
                        // Lump Sum scheduled exactly at campaign end - this should be valid
                        start_time: current_time.plus_days(7).seconds(),
                    },
                    DistributionType::LinearVesting {
                        percentage: Decimal::percent(50),
                        start_time: current_time.seconds(),
                        end_time: current_time.plus_days(7).seconds(),
                        cliff_duration: None,
                    },
                ],
                start_time: current_time.seconds(),
                end_time: current_time.plus_days(7).seconds(),
            }),
        },
        &[], // No funds during campaign creation
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap(); // Should succeed
        },
    );

    // Verify the campaign was created successfully
    suite.query_campaign(|result| {
        let campaign = result.unwrap();
        assert_eq!(campaign.name, "Valid Airdrop");
        assert_eq!(campaign.distribution_type.len(), 2);
    });
}

#[test]
fn test_distribution_types_ended_with_lump_sum() {
    let mut suite = TestingSuite::default_with_balances(vec![coin(200_000_000, "uom")]);

    let alice = &suite.senders[0].clone();
    let bob = &suite.senders[1].clone();
    let current_time = suite.get_time();

    suite.instantiate_claimdrop_contract(Some(alice.to_string()));

    // Create a campaign with mixed distribution types
    suite
        .manage_campaign(
            alice,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Mixed Distribution Test".to_string(),
                    description: "Testing distribution_types_ended fix".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(100_000, "uom"),
                    distribution_type: vec![
                        DistributionType::LumpSum {
                            percentage: Decimal::percent(30),
                            start_time: current_time.plus_days(1).seconds(),
                        },
                        DistributionType::LinearVesting {
                            percentage: Decimal::percent(70),
                            start_time: current_time.plus_days(1).seconds(),
                            end_time: current_time.plus_days(7).seconds(),
                            cliff_duration: None,
                        },
                    ],
                    start_time: current_time.plus_days(1).seconds(),
                    end_time: current_time.plus_days(7).seconds(),
                }),
            },
            &[], // No funds during campaign creation
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .top_up_campaign(
            alice,
            &coins(100_000, "uom"),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .add_allocations(
            alice,
            &vec![
                (alice.to_string(), Uint128::new(50_000)),
                (bob.to_string(), Uint128::new(50_000)),
            ],
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Move to day 2 (Lump Sum should have started)
    for _ in 0..2 {
        suite.add_day();
    }

    // Alice claims her Lump Sum portion
    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Query rewards to check claimed amounts
    suite.query_rewards(alice, |result| {
        let rewards = result.unwrap();
        // Should have claimed 30% (Lump Sum) + some vesting amount
        assert!(rewards.claimed[0].amount > Uint128::new(15_000)); // At least the Lump Sum portion
    });

    // Move to campaign end
    for _ in 0..5 {
        suite.add_day();
    }

    // Bob claims everything at the end
    suite.claim(
        bob,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Query rewards to verify dust compensation was calculated correctly
    suite.query_rewards(bob, |result| {
        let rewards = result.unwrap();
        // Bob should have claimed exactly 50,000 (including any dust compensation)
        assert!(
            !rewards.claimed.is_empty(),
            "Bob should have claimed rewards"
        );
        assert_eq!(rewards.claimed[0].amount, Uint128::new(50_000));
        assert!(rewards.pending.is_empty() || rewards.pending[0].amount == Uint128::zero());
        assert_eq!(rewards.available_to_claim.len(), 0);
    });

    // Alice claims the rest
    suite.claim(
        alice,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify Alice also got exactly her allocation
    suite.query_rewards(alice, |result| {
        let rewards = result.unwrap();
        assert!(
            !rewards.claimed.is_empty(),
            "Alice should have claimed rewards"
        );
        assert_eq!(rewards.claimed[0].amount, Uint128::new(50_000));
        assert!(rewards.pending.is_empty() || rewards.pending[0].amount == Uint128::zero());
    });
}

#[test]
fn test_remove_address_also_removes_blacklist() {
    let mut suite = TestingSuite::default_with_balances(vec![
        coin(1_000_000_000, "uom"),
        coin(1_000_000_000, "uusdc"),
    ]);
    let alice = &suite.senders[0].clone(); // Owner
    let bob = &suite.senders[1].clone();
    let carol = &suite.senders[2].clone();
    let current_time = &suite.get_time();

    // Setup: Create contract and add allocations
    let allocations = &vec![
        (bob.to_string(), Uint128::new(100_000)),
        (carol.to_string(), Uint128::new(200_000)),
    ];

    suite
        .instantiate_claimdrop_contract(None) // Alice is owner
        .add_allocations(
            alice,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    // Blacklist Carol
    suite.blacklist_address(
        alice,
        carol,
        true,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify Carol is blacklisted
    suite.query_is_blacklisted(carol, |result| {
        let is_blacklisted = result.unwrap();
        assert!(is_blacklisted.is_blacklisted, "Carol should be blacklisted");
    });

    // Now remove Carol's address allocation (before campaign starts)
    suite.remove_address(
        alice,
        carol,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify Carol's allocation is removed
    suite.query_allocations(Some(carol), None, None, |result| {
        let allocation = result.unwrap();
        assert!(
            allocation.allocations.is_empty(),
            "Carol's allocation should be removed"
        );
    });

    // Verify Carol is no longer blacklisted (the fix)
    suite.query_is_blacklisted(carol, |result| {
        let is_blacklisted = result.unwrap();
        assert!(
            !is_blacklisted.is_blacklisted,
            "Carol should not be blacklisted after address removal"
        );
    });

    // Test edge case: Blacklist Bob, then remove Bob, then re-add Bob
    // This verifies the blacklist doesn't persist across removals
    suite.blacklist_address(
        alice,
        bob,
        true,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify Bob is blacklisted
    suite.query_is_blacklisted(bob, |result| {
        let is_blacklisted = result.unwrap();
        assert!(is_blacklisted.is_blacklisted, "Bob should be blacklisted");
    });

    // Remove Bob's address
    suite.remove_address(alice, bob, |result: Result<AppResponse, anyhow::Error>| {
        result.unwrap();
    });

    // Verify Bob is no longer blacklisted after removal
    suite.query_is_blacklisted(bob, |result| {
        let is_blacklisted = result.unwrap();
        assert!(
            !is_blacklisted.is_blacklisted,
            "Bob should not be blacklisted after address removal"
        );
    });

    // Re-add Bob with a new allocation
    let new_allocations = &vec![(bob.to_string(), Uint128::new(150_000))];
    suite.add_allocations(
        alice,
        new_allocations,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify Bob is still not blacklisted after re-adding
    suite.query_is_blacklisted(bob, |result| {
        let is_blacklisted = result.unwrap();
        assert!(
            !is_blacklisted.is_blacklisted,
            "Bob should still not be blacklisted after being re-added"
        );
    });

    // Now create the campaign with Bob's new allocation
    suite.top_up_campaign(
        alice,
        &coins(150_000, "uom"),
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    suite.manage_campaign(
        alice,
        CampaignAction::CreateCampaign {
            params: Box::new(CampaignParams {
                name: "Test Blacklist Removal".to_string(),
                description: "Test that remove_address also removes blacklist entry".to_string(),
                ty: "airdrop".to_string(),
                total_reward: coin(150_000, "uom"),
                distribution_type: vec![DistributionType::LumpSum {
                    percentage: Decimal::percent(100),
                    start_time: current_time.seconds(), // Starts immediately
                }],
                start_time: current_time.seconds(),
                end_time: current_time.plus_days(7).seconds(),
            }),
        },
        &[], // No funds during campaign creation
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify Bob can claim successfully (not blacklisted)
    suite.claim(
        bob,
        None,
        None,
        |result: Result<AppResponse, anyhow::Error>| {
            result.unwrap();
        },
    );

    // Verify Bob's claim was successful
    suite.query_rewards(bob, |result| {
        let rewards = result.unwrap();
        assert!(
            !rewards.claimed.is_empty(),
            "Bob should have claimed rewards"
        );
        assert_eq!(rewards.claimed[0].amount, Uint128::new(150_000));
    });
}
