# To-Do

1. Need to aggregate `PYSEGREEN1` tokenholder details and the amount of tokens each wallet has.
2. Distribution Parameters: 
    ```yaml
     - DistributionKind: BULK
        percentageBps: 100%
        startTime: Nov 10 2026 14:00 GMT+8 // FAKE MONTH 1
        endTime: Shouldn't Exist for Pyse; Need to review how it works; Nov 10 2026 14:00 GMT+8
        cliffDuration: 0
    ```
3. Campaign
    ```
    string name; `PYSEGREEN1 Primary Sale Campaign: Yield Distribution 1/52 (TEST 2025.11.10)` 
    string description; `This is a development test of yield distribution`
    string campaignType; `BULK`
    address rewardToken; `~mantraUSD`
    uint256 totalReward; `67*<TOTAL TOKENS SOLD>`
    Distribution[] distributions; `[DISTRIBUTION INFO ABOVE]`
    uint64 startTime;  Nov 10 2026 14:00 GMT+8 // FAKE MONTH 1
    uint64 endTime; LAST FAKE MONTH
    uint256 claimed; 0
    uint64 closedAt; 0
    bool exists; true
    ```

4. Campaign Allocation Example (for 1/52)
    (CSV Upload)

    | Wallet Address | Allocation Amount |
    |----------------|-------------------|
    | 0x2366147637f3d3ad98316379d71fF13dc6928909 _(Aaron, only 1 token)_| 67 |
    | 0x78d891B412eaAA4df95364105D48Ef9cA52911B3 _(Aaron, 2 tokens)_ | 134 |
    | 0xEA10DBD1C6DB87DE27811a7c9D0913E1c46b924C _(Bigto, 1 token)_ | 67 |
    | 0x7eFCA8F83cC8Ecb4bcd7C13730A8A1C5D24475Da _(Bigto, 2 tokens)_ | 134 |
    | 0x64df0e3e801c957f877abcf7a960fc7a49b7be53 _(Chiu, 3 tokens)_ | 201 |
    | 0x6d16709103235a95Dd314DaFaD37E6594298BD52 _(Samuel, 1 token)_ | 67 |



