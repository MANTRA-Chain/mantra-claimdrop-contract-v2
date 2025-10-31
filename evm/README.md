# MANTRA Claimdrop - EVM Contracts

Token distribution contract with vesting capabilities for EVM-compatible chains.

## Features

- **Campaign Management**: Create and close token distribution campaigns
- **Batch Allocations**: Upload up to 3,000 allocations per batch
- **Multiple Distribution Types**:
  - Lump sum distributions (immediate release at specific time)
  - Linear vesting with optional cliff periods
- **Partial Claims**: Users can claim any amount up to their available balance
- **Authorization**: Two-tier system (owner + authorized wallets)
- **Blacklist**: Prevent specific addresses from claiming
- **Rounding Dust Recovery**: Compensate for precision loss in percentage calculations
- **Emergency Controls**: Pausable and owner-only administrative functions

## Architecture

- **Solidity Version**: 0.8.24
- **Dependencies**: OpenZeppelin Contracts 4.9.3
- **Framework**: Hardhat 2.19.4

## Installation

```bash
npm install
```

## Development Commands

### Build

```bash
npm run build
```

### Test

```bash
# Run all tests
npm test

# Run with gas reporting
npm run test:gas

# Run coverage
npm run test:coverage
```

### Lint

```bash
# Check code
npm run lint

# Auto-fix issues
npm run lint:fix
```

### Format

```bash
# Format code
npm run format

# Check formatting
npm run format:check
```

## Deployment

### 1. Configure Environment

Create a `.env` file:

```bash
cp .env.example .env
```

Edit `.env` with your configuration:

```
MANTRA_DUKONG_RPC_URL=https://evm.dukong.mantrachain.io
MANTRA_MAINNET_RPC_URL=https://evm.mantrachain.io
PRIVATE_KEY=your_private_key_here
MANTRA_API_KEY=your_api_key_here
```

### 2. Deploy Contract

```bash
# Deploy to local Hardhat network
npx hardhat run scripts/deploy.js

# Deploy to MANTRA Dukong testnet
npx hardhat run scripts/deploy.js --network mantradukong

# Deploy to MANTRA mainnet
npx hardhat run scripts/deploy.js --network mantra
```

### 3. Verify Contract

```bash
node scripts/verify.js <contract_address> <owner_address>
```

## Usage

### Create Campaign

Create a campaign configuration file `campaign-config.json`:

```json
{
  "name": "MANTRA Airdrop Q1 2025",
  "description": "Quarterly token distribution",
  "campaignType": "airdrop",
  "rewardToken": "0x...",
  "totalReward": "1000000000000000000000000",
  "distributions": [
    {
      "kind": "LumpSum",
      "percentageBps": 3000,
      "startTime": 1735689600,
      "endTime": 0,
      "cliffDuration": 0
    },
    {
      "kind": "LinearVesting",
      "percentageBps": 7000,
      "startTime": 1735689600,
      "endTime": 1767225600,
      "cliffDuration": 2592000
    }
  ],
  "startTime": 1735689600,
  "endTime": 1767225600
}
```

Run the script:

```bash
node scripts/createCampaign.js <claimdrop_address> ./campaign-config.json
```

### Upload Allocations

Create allocations file `allocations.json`:

```json
[
  {
    "address": "0x1234...",
    "amount": "1000000000000000000000"
  },
  {
    "address": "0x5678...",
    "amount": "2000000000000000000000"
  }
]
```

Upload:

```bash
node scripts/uploadAllocations.js <claimdrop_address> ./allocations.json
```

### Fund Contract

Transfer reward tokens to the contract:

```javascript
await rewardToken.transfer(claimdropAddress, totalRewardAmount);
```

### Claim Tokens

Users can claim through the contract interface:

```javascript
// Claim all available tokens
await claimdrop.claim(userAddress, 0);

// Claim specific amount
await claimdrop.claim(userAddress, ethers.parseEther("1000"));
```

### Close Campaign

Only owner can close the campaign and retrieve unclaimed tokens:

```javascript
await claimdrop.closeCampaign();
```

## Contract Interface

### Core Functions

#### `createCampaign()`
Create a new distribution campaign (owner/authorized only).

#### `closeCampaign()`
Close campaign and return unclaimed tokens to owner.

#### `addAllocations(addresses[], amounts[])`
Add allocations in batch (max 3,000 per batch).

#### `claim(receiver, amount)`
Claim tokens (amount = 0 for maximum available).

#### `replaceAddress(oldAddress, newAddress)`
Migrate allocation and claims to new address.

#### `blacklistAddress(address, blacklisted)`
Update blacklist status for an address.

### View Functions

#### `getCampaign()`
Get current campaign details.

#### `getRewards(address)`
Get claimed, pending, and total allocation for address.

#### `getAllocation(address)`
Get allocation amount for address.

#### `getClaims(address)`
Get claimed amounts per distribution slot.

## Distribution Types

### Lump Sum

Tokens released immediately when distribution starts:

```solidity
{
  kind: 1, // LumpSum
  percentageBps: 3000, // 30%
  startTime: 1735689600,
  endTime: 0,
  cliffDuration: 0
}
```

### Linear Vesting

Tokens vest linearly over time with optional cliff:

```solidity
{
  kind: 0, // LinearVesting
  percentageBps: 7000, // 70%
  startTime: 1735689600,
  endTime: 1767225600, // 1 year later
  cliffDuration: 2592000 // 30 days
}
```

## Security

- **Reentrancy Protection**: All external calls protected with `ReentrancyGuard`
- **Access Control**: Owner + authorized wallets with distinct permissions
- **Pausable**: Emergency circuit breaker
- **Checks-Effects-Interactions**: State updates before external calls
- **SafeERC20**: Handles non-standard token implementations
- **Input Validation**: Comprehensive parameter checks

## Testing

Comprehensive test suite with 41 tests covering:

- Campaign management (creation, closure)
- Allocation management (add, remove, replace)
- Claiming (lump sum, vesting, cliff, partial)
- Administration (blacklist, authorized wallets, pause)
- Security (reentrancy, authorization)
- Edge cases (rounding, time boundaries)

Run tests:

```bash
npm test
```

## Gas Costs

Approximate gas costs (testnet):

- `createCampaign`: ~400,000 gas
- `addAllocations(100)`: ~4,000,000 gas
- `claim`: ~200,000-400,000 gas
- `closeCampaign`: ~150,000 gas

## License

MIT

## Support

For issues and questions:
- GitHub Issues: https://github.com/MANTRA-Finance/mantra-contracts-claimdrop/issues
- Documentation: https://docs.mantrachain.io
