use cosmwasm_std::{coin, coins, Addr, Decimal, Uint128};
use cw_multi_test::AppResponse;

use mantra_claimdrop_std::msg::{
    CampaignAction, CampaignParams, DistributionType, RewardsResponse,
};

use crate::suite::TestingSuite;
mod suite;

/*
This test is built to confirm a potential issue with the contract when using a denom with a exponent of 18.
The numbers used in this test are based on a small real-world scenario where the contract was not returning the correct rewards.
The contract will need to handle at least 999_000_000 * 10^18 to be able to handle the rewards in the real-world scenario.
Subsequent pools have investment in the 10's of millions of dollars, so the contract will need to handle these.
We should build to expect the contract to handle at least 999_000_000 * 10^18 preferably more.
 */

#[test]
fn bug_large_numbers() {
    let alice = Addr::unchecked("mantra13qtg0gys4lfxccjeqed3vrdgmp7g5kzcmf7kjm");
    let denom = "factory/mantra1ady9vl53r6ct6kxklhgxvtnscmszryl8nnzule/ausdy";

    let amount: u128 = 48138819536000000000000;
    let alice_amount: u128 = 2040555238000000000000;

    let mut suite = TestingSuite::default_with_balances(vec![coin(amount, denom)]);
    let owner = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(alice_amount))];

    suite
        .instantiate_claimdrop_contract(None)
        .add_allocations(
            owner,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            owner,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with no cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(amount, denom),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::percent(100),
                        start_time: current_time.seconds(),
                    }],
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
            owner,
            &coins(amount, denom),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite
        .query_rewards(&alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: vec![],
                    pending: coins(alice_amount, denom),
                    available_to_claim: coins(alice_amount, denom),
                }
            );
        })
        .query_balance(denom, &alice, |balance| {
            assert_eq!(balance, Uint128::zero());
        })
        .claim(
            &alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance(denom, &alice, |balance| {
            assert_eq!(balance, Uint128::new(alice_amount));
        });
}

#[allow(clippy::inconsistent_digit_grouping)]
#[test]
fn bug_large_numbers_2() {
    let alice = Addr::unchecked("mantra13qtg0gys4lfxccjeqed3vrdgmp7g5kzcmf7kjm");
    let denom = "factory/mantra1ady9vl53r6ct6kxklhgxvtnscmszryl8nnzule/ausdy";

    // 100 trillion
    let amount: u128 = 100_000_000_000_000_000000000000000000;
    let alice_amount: u128 = 70_000_000_000_000_000000000000000000;
    let mut suite = TestingSuite::default_with_balances(vec![coin(amount, denom)]);

    let owner = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(alice_amount))];

    suite
        .instantiate_claimdrop_contract(None)
        .add_allocations(
            owner,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            owner,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with no cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(amount, denom),
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
        )
        .top_up_campaign(
            owner,
            &coins(amount, denom),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.add_day();

    suite
        .query_rewards(&alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: vec![],
                    pending: coins(alice_amount, denom),
                    available_to_claim: coins(9_999_999_999_999_999990000000000000, denom),
                }
            );
        })
        .query_balance(denom, &alice, |balance| {
            assert_eq!(balance, Uint128::zero());
        })
        .claim(
            &alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance(denom, &alice, |balance| {
            assert_eq!(balance, Uint128::new(9_999_999_999_999_999990000000000000));
        });

    suite.add_week();

    suite
        .claim(
            &alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance(denom, &alice, |balance| {
            assert_eq!(balance, Uint128::new(alice_amount));
        });
}

#[allow(clippy::inconsistent_digit_grouping)]
#[test]
fn bug_large_numbers_3() {
    let alice = Addr::unchecked("mantra13qtg0gys4lfxccjeqed3vrdgmp7g5kzcmf7kjm");
    let denom = "factory/mantra1ady9vl53r6ct6kxklhgxvtnscmszryl8nnzule/ausdy";

    // 100 trillion
    let amount: u128 = 340_000_000_000_000_000000000000000000;
    let alice_amount: u128 = 340_000_000_000_000_000000000000000000;

    let mut suite = TestingSuite::default_with_balances(vec![coin(amount, denom)]);

    let owner = &suite.senders[0].clone();
    let current_time = &suite.get_time();

    let allocations = &vec![(alice.to_string(), Uint128::new(alice_amount))];

    suite
        .instantiate_claimdrop_contract(None)
        .add_allocations(
            owner,
            allocations,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .manage_campaign(
            owner,
            CampaignAction::CreateCampaign {
                params: Box::new(CampaignParams {
                    name: "Test Airdrop I".to_string(),
                    description: "This is an airdrop with no cliff".to_string(),
                    ty: "airdrop".to_string(),
                    total_reward: coin(amount, denom),
                    distribution_type: vec![DistributionType::LumpSum {
                        percentage: Decimal::percent(100),
                        start_time: current_time.seconds(),
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
            owner,
            &coins(amount, denom),
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        );

    suite.add_day();

    suite
        .query_rewards(&alice, |result| {
            assert_eq!(
                result.unwrap(),
                RewardsResponse {
                    claimed: vec![],
                    pending: coins(alice_amount, denom),
                    available_to_claim: coins(alice_amount, denom),
                }
            );
        })
        .query_balance(denom, &alice, |balance| {
            assert_eq!(balance, Uint128::zero());
        })
        .claim(
            &alice,
            None,
            None,
            |result: Result<AppResponse, anyhow::Error>| {
                result.unwrap();
            },
        )
        .query_balance(denom, &alice, |balance| {
            assert_eq!(balance, Uint128::new(alice_amount));
        });
}
