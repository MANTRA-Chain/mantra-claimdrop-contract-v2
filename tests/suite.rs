use cosmwasm_std::{coin, Addr, Coin, Empty, StdResult, Timestamp, Uint128};
use cw_multi_test::{
    App, AppBuilder, AppResponse, BankKeeper, Contract, ContractWrapper, Executor, MockApiBech32,
    WasmKeeper,
};
use mantra_claimdrop_std::msg::{
    AllocationsResponse, AuthorizedResponse, AuthorizedWalletsResponse, BlacklistResponse,
    CampaignAction, CampaignResponse, ClaimedResponse, ExecuteMsg, InstantiateMsg, QueryMsg,
    RewardsResponse,
};

type MantraApp = App<BankKeeper, MockApiBech32>;

pub fn claimdrop_contract() -> Box<dyn Contract<Empty>> {
    let contract = ContractWrapper::new(
        claimdrop_contract::contract::execute,
        claimdrop_contract::contract::instantiate,
        claimdrop_contract::contract::query,
    )
    .with_migrate(claimdrop_contract::contract::migrate);

    Box::new(contract)
}

pub struct TestingSuite {
    app: MantraApp,
    pub senders: Vec<Addr>,
    pub claimdrop_contract_addr: Addr,
}

// helpers
impl TestingSuite {
    #[track_caller]
    pub fn admin(&mut self) -> Addr {
        self.senders.first().unwrap().clone()
    }

    #[track_caller]
    pub fn get_time(&mut self) -> Timestamp {
        self.app.block_info().time
    }

    #[track_caller]
    pub fn add_day(&mut self) -> &mut Self {
        let mut block_info = self.app.block_info();
        block_info.time = block_info.time.plus_days(1);
        self.app.set_block(block_info);

        self
    }

    #[track_caller]
    pub fn add_week(&mut self) -> &mut Self {
        let mut block_info = self.app.block_info();
        block_info.time = block_info.time.plus_days(7);
        self.app.set_block(block_info);

        self
    }
}

// instantiate
impl TestingSuite {
    #[track_caller]
    pub fn default_with_balances(initial_balances: Vec<Coin>) -> Self {
        let mut senders = vec![];
        let mut balances = vec![];

        let sender0 = "mantra1c758pr6v2zpgdl2rg2enmjedfglxjkac8m7syw";
        let sender1 = "mantra1jg390tyu84e86ntmzhakcst8gmxnelycwsatsq";
        let sender2 = "mantra1eujd63rrvtc02mt08qp7wfnuzhscgs3laxdgkx";
        let sender3 = "mantra1vyd2mkkrff99kawaqge94puq099ghfkyncntmd";
        let sender4 = "mantra1fawdagn5sfq8c2rylzreepme0yy6h8sdaa603t";

        senders.push(Addr::unchecked(sender0));
        senders.push(Addr::unchecked(sender1));
        senders.push(Addr::unchecked(sender2));
        senders.push(Addr::unchecked(sender3));
        senders.push(Addr::unchecked(sender4));

        balances.push((Addr::unchecked(sender0), initial_balances.clone()));
        balances.push((Addr::unchecked(sender1), initial_balances.clone()));
        balances.push((Addr::unchecked(sender2), initial_balances.clone()));
        balances.push((Addr::unchecked(sender3), initial_balances.clone()));
        balances.push((Addr::unchecked(sender4), initial_balances.clone()));

        let app = AppBuilder::new()
            .with_wasm(WasmKeeper::default())
            .with_wasm(WasmKeeper::default())
            .with_bank(BankKeeper::new())
            .with_api(MockApiBech32::new("mantra"))
            .build(|router, _api, storage| {
                balances.into_iter().for_each(|(account, amount)| {
                    router.bank.init_balance(storage, &account, amount).unwrap()
                });
            });

        TestingSuite {
            app,
            senders,
            claimdrop_contract_addr: Addr::unchecked(""),
        }
    }

    #[track_caller]
    pub fn instantiate_claimdrop_contract(&mut self, owner: Option<String>) -> &mut Self {
        let msg = InstantiateMsg {
            owner,
            action: None,
        };

        let claimdrop_contract_code_id = self.app.store_code(claimdrop_contract());
        let admin = self.admin();

        self.claimdrop_contract_addr = self
            .app
            .instantiate_contract(
                claimdrop_contract_code_id,
                admin.clone(),
                &msg,
                &[],
                "mantra-claimdrop-contract",
                Some(admin.into_string()),
            )
            .unwrap();

        self
    }
}

pub trait ResultHandler {
    fn handle_result(&self, result: Result<AppResponse, anyhow::Error>);
}

impl<F> ResultHandler for F
where
    F: Fn(Result<AppResponse, anyhow::Error>),
{
    fn handle_result(&self, result: Result<AppResponse, anyhow::Error>) {
        self(result);
    }
}

// execute msg
impl TestingSuite {
    fn execute_contract(
        &mut self,
        sender: &Addr,
        msg: ExecuteMsg,
        funds: &[Coin],
        result: impl ResultHandler,
    ) -> &mut Self {
        result.handle_result(self.app.execute_contract(
            sender.clone(),
            self.claimdrop_contract_addr.clone(),
            &msg,
            funds,
        ));

        self
    }

    #[track_caller]
    pub fn top_up_campaign(
        &mut self,
        sender: &Addr,
        funds: &[Coin],
        result: impl ResultHandler,
    ) -> &mut Self {
        result.handle_result(self.app.send_tokens(
            sender.clone(),
            self.claimdrop_contract_addr.clone(),
            funds,
        ));

        self
    }

    #[track_caller]
    pub fn manage_campaign(
        &mut self,
        sender: &Addr,
        action: CampaignAction,
        funds: &[Coin],
        result: impl ResultHandler,
    ) -> &mut Self {
        self.execute_contract(sender, ExecuteMsg::ManageCampaign { action }, funds, result)
    }

    #[track_caller]
    pub fn claim(
        &mut self,
        sender: &Addr,
        receiver: Option<String>,
        amount: Option<Uint128>,
        result: impl ResultHandler,
    ) -> &mut Self {
        self.execute_contract(sender, ExecuteMsg::Claim { receiver, amount }, &[], result)
    }

    #[track_caller]
    pub fn update_ownership(
        &mut self,
        sender: &Addr,
        action: cw_ownable::Action,
        result: impl ResultHandler,
    ) -> &mut Self {
        self.execute_contract(sender, ExecuteMsg::UpdateOwnership(action), &[], result)
    }

    #[track_caller]
    pub fn add_allocations(
        &mut self,
        sender: &Addr,
        allocations: &Vec<(String, Uint128)>,
        result: impl ResultHandler,
    ) -> &mut Self {
        self.execute_contract(
            sender,
            ExecuteMsg::AddAllocations {
                allocations: allocations.clone(),
            },
            &[],
            result,
        )
    }

    #[track_caller]
    pub fn replace_address(
        &mut self,
        sender: &Addr,
        old_address: &Addr,
        new_address: &Addr,
        result: impl ResultHandler,
    ) -> &mut Self {
        self.execute_contract(
            sender,
            ExecuteMsg::ReplaceAddress {
                old_address: old_address.to_string(),
                new_address: new_address.to_string(),
            },
            &[],
            result,
        )
    }

    #[track_caller]
    pub fn remove_address(
        &mut self,
        sender: &Addr,
        address: &Addr,
        result: impl ResultHandler,
    ) -> &mut Self {
        self.execute_contract(
            sender,
            ExecuteMsg::RemoveAddress {
                address: address.to_string(),
            },
            &[],
            result,
        )
    }

    #[track_caller]
    pub fn blacklist_address(
        &mut self,
        sender: &Addr,
        address: &Addr,
        blacklist: bool,
        result: impl ResultHandler,
    ) -> &mut Self {
        self.execute_contract(
            sender,
            ExecuteMsg::BlacklistAddress {
                address: address.to_string(),
                blacklist,
            },
            &[],
            result,
        )
    }

    #[track_caller]
    pub fn manage_authorized_wallets(
        &mut self,
        sender: &Addr,
        addresses: Vec<String>,
        authorized: bool,
        funds: &[Coin],
        result: impl ResultHandler,
    ) -> &mut Self {
        self.execute_contract(
            sender,
            ExecuteMsg::ManageAuthorizedWallets {
                addresses,
                authorized,
            },
            funds,
            result,
        )
    }
}

// queries
impl TestingSuite {
    fn query_contract<T>(&mut self, msg: QueryMsg, result: impl Fn(StdResult<T>)) -> &mut Self
    where
        T: serde::de::DeserializeOwned,
    {
        let response: StdResult<T> = self
            .app
            .wrap()
            .query_wasm_smart(&self.claimdrop_contract_addr, &msg);

        result(response);

        self
    }

    #[track_caller]
    pub fn query_campaign(&mut self, result: impl Fn(StdResult<CampaignResponse>)) -> &mut Self {
        self.query_contract(QueryMsg::Campaign {}, result)
    }

    #[track_caller]
    pub fn query_rewards(
        &mut self,
        receiver: &Addr,
        result: impl Fn(StdResult<RewardsResponse>),
    ) -> &mut Self {
        self.query_contract(
            QueryMsg::Rewards {
                receiver: receiver.to_string(),
            },
            result,
        )
    }

    #[track_caller]
    pub fn query_claimed(
        &mut self,
        address: Option<&Addr>,
        start_from: Option<&Addr>,
        limit: Option<u16>,
        result: impl Fn(StdResult<ClaimedResponse>),
    ) -> &mut Self {
        let address = address.map(|addr| addr.to_string());
        let start_from = start_from.map(|addr| addr.to_string());

        self.query_contract(
            QueryMsg::Claimed {
                address,
                start_from,
                limit,
            },
            result,
        )
    }

    #[track_caller]
    pub fn query_allocations(
        &mut self,
        address: Option<&Addr>,
        start_after: Option<&Addr>,
        limit: Option<u16>,
        result: impl Fn(StdResult<AllocationsResponse>),
    ) -> &mut Self {
        self.query_contract(
            QueryMsg::Allocations {
                address: address.map(|addr| addr.to_string()),
                start_after: start_after.map(|addr| addr.to_string()),
                limit,
            },
            result,
        )
    }

    #[track_caller]
    pub fn query_is_blacklisted(
        &mut self,
        address: &Addr,
        result: impl Fn(StdResult<BlacklistResponse>),
    ) -> &mut Self {
        self.query_contract(
            QueryMsg::IsBlacklisted {
                address: address.to_string(),
            },
            result,
        )
    }

    #[track_caller]
    pub fn _query_ownership(
        &mut self,
        result: impl Fn(StdResult<cw_ownable::Ownership<String>>),
    ) -> &mut Self {
        self.query_contract(QueryMsg::Ownership {}, result)
    }

    #[track_caller]
    pub fn query_balance(
        &mut self,
        denom: &str,
        address: &Addr,
        result: impl Fn(Uint128),
    ) -> &mut Self {
        let balance_response = self.app.wrap().query_balance(address, denom);
        result(balance_response.unwrap_or(coin(0, denom)).amount);
        self
    }

    #[track_caller]
    pub fn query_is_authorized(
        &mut self,
        address: String,
        result: impl Fn(StdResult<AuthorizedResponse>),
    ) -> &mut Self {
        self.query_contract(QueryMsg::IsAuthorized { address }, result)
    }

    #[track_caller]
    pub fn query_authorized_wallets(
        &mut self,
        start_after: Option<String>,
        limit: Option<u32>,
        result: impl Fn(StdResult<AuthorizedWalletsResponse>),
    ) -> &mut Self {
        self.query_contract(QueryMsg::AuthorizedWallets { start_after, limit }, result)
    }
}
