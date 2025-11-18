# MANTRA Claimdrop - EVM Implementation

Token distribution contract with vesting capabilities for Ethereum-compatible chains.

## Multi-Network Testing

This implementation supports **unified multi-network testing** across all MANTRA networks (local, DuKong testnet, Canary staging, mainnet) with a single command interface.

**Quick Start**:
```bash
just networks              # List available networks
just deploy local          # Deploy to local Anvil
just deploy dukong         # Deploy to DuKong testnet
```

**🚀 Hybrid Cast/Forge E2E Testing**: See the justfile recipes for hybrid E2E setup:
- `just forge-e2e-deploy` - Deploy contracts using cast
- `just forge-e2e-setup` - Create campaign and add allocations
- `just forge-e2e-execute` - Execute test claims
- `just forge-e2e-close` - Close campaign
- `just forge-e2e-full` - Run all phases in sequence

## Features

- **Campaign management** (create/close)
- **Batch allocation uploads** (up to 3000 per batch)
- **Multiple distribution types** (lump sum + linear vesting)
- **Partial claims supported**
- **Cliff periods for vesting**
- **Blacklist functionality**
- **Optional allowlist integration** (KYC/AML compliance)
- **Authorized wallet management**
- **Emergency pause functionality**

## Tech Stack

- **Framework**: Foundry (Rust-based Solidity development toolkit)
- **Language**: Solidity 0.8.24
- **Dependencies**: OpenZeppelin Contracts 4.9.3
- **Build Tool**: `just` command runner

## Installation

### Prerequisites

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install `just` command runner:
```bash
# macOS
brew install just

# Or see: https://github.com/casey/just#installation
```

### Setup

```bash
# Clone and navigate to EVM directory
cd evm/

# Install dependencies
forge install

# Copy environment template
cp .env.example .env
# Edit .env with your configuration
```

## Development Commands

All commands use the `justfile` for consistency. Run `just` to see available commands:

```bash
just                  # List all available commands
just build            # Compile contracts
just test             # Run tests
just test-all         # Run all tests (no fail-fast)
just test-gas         # Run tests with gas reporting
just coverage         # Generate coverage report
just format           # Format Solidity files
just format-check     # Check formatting (CI)
just clean            # Clean build artifacts
just ci               # Run CI pipeline (format-check + test-all)
just e2e              # Run complete E2E test on testnet
just e2e-report       # View E2E transaction report
```

## Production-Grade Cast Scripts

**⚠️ IMPORTANT: Cast scripts are the preferred deployment method for this project.**

The EVM implementation includes **production-hardened cast-based deployment scripts** designed for reliability on Cosmos SDK EVM chains (MANTRA DuKong, mainnet). These scripts are the **recommended and actively maintained** deployment approach.

### Why Cast Scripts Are Preferred

Cast scripts solve critical issues with `forge script` batch broadcasting on Cosmos SDK EVMs:
- **Nonce Management**: Sequential transaction handling prevents nonce conflicts
- **Cosmos SDK Compatibility**: Works reliably on MANTRA chains (DuKong testnet, mainnet)
- **Production Reliability**: Proven deployment success on testnet (see E2E-DUKONG-REPORT.md)
- **Enhanced Error Handling**: Comprehensive validation and transaction confirmation

**When to use forge vs cast:**
- ✅ **Use cast scripts for deployment**: `just deploy <network>` (production deployments)
- ✅ **Use forge for testing/simulations**: `forge test`, `forge script --no-broadcast` (development)
- ❌ **Do NOT use forge script for actual deployments**: Causes nonce management issues on Cosmos SDK EVMs

### Key Features

**🔒 Security Hardening**:
- Private key format validation (prevents malformed keys)
- `.env` file permission checks (warns if not 600/400)
- `.gitignore` validation (prevents accidental key commits)
- No private keys in logs or error messages

**⚡ Robust Transaction Handling**:
- Automatic transaction confirmation polling (no more blind `sleep` waits)
- Exponential backoff (2s → 4s → 6s → 8s → 10s intervals)
- Configurable timeout (default: 180 seconds)
- Transaction status validation (detects failed transactions)
- Revert reason extraction from failed transactions
- **Enhanced validation features** (opt-in):
  - Gas usage validation with warnings for excessive consumption
  - Multi-block confirmation depth support for critical transactions
  - Transaction summary logging with explorer links

**💰 Dynamic Gas Pricing**:
- Network gas price estimation via `cast gas-price`
- Configurable min/max bounds (default: 10-200 gwei)
- Manual override support via `GAS_PRICE` env var
- Automatic fallback to safe default on estimation failure

**⏱️ Deterministic Timing**:
- Campaign start time calculated from actual block timestamp
- Eliminates race conditions (no more 20-second buffer guessing)
- Configurable safety buffer (default: 30 seconds)
- Validation that start time is in the future

**🔍 Comprehensive Validation**:
- RPC connectivity checks before execution
- Ethereum address format validation
- Contract existence verification (prevents calls to non-existent contracts)
- Required environment variable validation with clear error messages

**📊 Enhanced Logging**:
- Color-coded output (disabled in CI/non-TTY environments)
- Severity levels: INFO, WARN, ERROR, DEBUG
- Debug mode for verbose logging (`DEBUG=1`)
- Transaction tracking with report generation

### Configuration Options

All scripts support the following environment variables:

```bash
# Required
RPC_URL=<your_rpc_endpoint>
PRIVATE_KEY=<64_hex_chars>

# Gas Configuration (optional)
GAS_PRICE=50000000000           # Manual override in wei (default: dynamic estimation)
GAS_PRICE_MIN=10000000000       # Minimum gas price (default: 10 gwei)
GAS_PRICE_MAX=200000000000      # Maximum gas price (default: 200 gwei)
GAS_LIMIT=10000000              # Gas limit for transactions (default: 10000000)

# Transaction Settings (optional)
TX_CONFIRMATION_TIMEOUT=180     # Confirmation timeout in seconds (default: 180)

# Enhanced Validation (optional)
TX_VALIDATE_GAS=1               # Enable gas usage validation (default: 1)
TX_VALIDATE_CONFIRMATIONS=1     # Required block confirmations (default: 1, set higher for critical txs)

# Campaign Timing (optional)
CAMPAIGN_START_BUFFER=30        # Safety buffer after campaign creation (default: 30)

# Debug Mode (optional)
DEBUG=1                         # Enable verbose logging (default: 0)
```

### Available Scripts

1. **`cast-deploy.sh`** - Deploy contracts (MockERC20 + Claimdrop)
   - Validates environment and RPC connectivity
   - Deploys contracts with confirmed transactions
   - Verifies deployment on-chain
   - Saves state to `deployments.txt`

2. **`cast-setup.sh`** - Campaign setup
   - Mints test tokens
   - Approves token transfer
   - Creates campaign with deterministic timing
   - Transfers reward tokens
   - Adds test allocations

3. **`cast-execute-claims.sh`** - Execute test claims
   - Waits for campaign start automatically
   - Executes claims with confirmation
   - Validates all transactions

4. **`cast-close-campaign.sh`** - Close campaign
   - Waits for campaign end automatically
   - Closes campaign with confirmation
   - Returns unclaimed tokens to owner

5. **`cast-e2e-complete.sh`** - Full E2E orchestration
   - Generates temporary test wallets
   - Funds test addresses (2 OM each)
   - Runs complete E2E flow with claim simulation
   - Uses block timestamps for accurate campaign timing
   - Sweeps funds back to deployer
   - Generates transaction report with Mantrascan links

### Usage Examples

```bash
# Full E2E test on DuKong testnet
cd evm
just e2e-deploy    # Deploy contracts
just e2e-setup     # Setup campaign
just e2e-execute   # Execute claims
just e2e-close     # Close campaign

# Or run everything at once
just e2e           # Complete E2E flow
just e2e-report    # View formatted transaction report with Mantrascan links

# Run E2E and generate report
just e2e && just e2e-report

# With custom configuration
GAS_PRICE_MAX=100000000000 DEBUG=1 just e2e-deploy
GAS_LIMIT=15000000 just e2e  # Increase gas limit for complex operations

# Manual script execution
export RPC_URL="https://evm.dukong.mantrachain.io"
export PRIVATE_KEY="your_key_here"
./scripts/cast-deploy.sh
```

### Error Handling & Troubleshooting

**Common Error Messages**:

- `❌ Failed to connect to RPC endpoint` - Check RPC_URL is correct and accessible
- `❌ Invalid private key format` - Private key must be 64 hex characters
- `❌ Invalid Ethereum address format` - Address must be 0x + 40 hex characters
- `❌ Contract has no code deployed` - Address is not a contract or deployment failed
- `❌ Transaction confirmation timeout` - Network congestion or RPC issues
- `⚠️ .env file has insecure permissions` - Run `chmod 600 .env`

**Debug Mode**:

Enable verbose logging to troubleshoot issues:

```bash
DEBUG=1 ./scripts/cast-deploy.sh
```

This shows:
- All function calls and parameters
- Transaction polling progress
- Gas price calculation details
- Address validation steps
- RPC connectivity checks

**Network Issues**:

If transactions time out:
1. Check RPC endpoint is responsive: `cast block latest --rpc-url $RPC_URL`
2. Increase timeout: `TX_CONFIRMATION_TIMEOUT=300 ./scripts/cast-deploy.sh`
3. Try different RPC endpoint if available

**Gas Price Issues**:

If transactions fail due to gas:
1. Check current network gas price: `cast gas-price --rpc-url $RPC_URL`
2. Set manual gas price: `GAS_PRICE=100000000000 ./scripts/cast-deploy.sh`
3. Adjust bounds: `GAS_PRICE_MAX=500000000000 ./scripts/cast-deploy.sh`

### Security Best Practices

**Private Key Management**:
1. Store keys in `.env` file, never in code
2. Set restrictive permissions: `chmod 600 .env`
3. Verify `.env` is in `.gitignore`
4. Never commit or share private keys
5. Use hardware wallets (Ledger) for production

**Pre-Deployment Checklist**:
- [ ] `.env` has 600 permissions
- [ ] `.env` is in `.gitignore`
- [ ] RPC URL is correct for target network
- [ ] Test deployment on testnet first
- [ ] Verify contract addresses after deployment
- [ ] Keep transaction hashes for verification

## Deployment

### Local (Anvil)

```bash
# Terminal 1: Start local node
anvil

# Terminal 2: Deploy
just deploy-local
```

### MANTRA Dukong Testnet

```bash
# Ensure .env is configured with:
# - MANTRA_DUKONG_RPC_URL
# - PRIVATE_KEY

just deploy-testnet
```

### MANTRA Mainnet

```bash
# Ensure .env is configured with:
# - MANTRA_MAINNET_RPC_URL
# - PRIVATE_KEY

just deploy-mainnet  # Includes confirmation prompt
```

## Contract Verification

```bash
# Verify on MANTRA Dukong
just verify <CONTRACT_ADDRESS> mantradukong

# Verify on MANTRA Mainnet
just verify <CONTRACT_ADDRESS> mantra
```

## Testing

Tests are written in Solidity using Foundry's testing framework.

```bash
# Run all tests
just test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_ShouldAllowClaimAfterStart

# Run with gas reporting
just test-gas
```

### Test Coverage

The test suite includes **49 comprehensive tests** covering:

- Deployment (3 tests)
- Campaign Management (9 tests)
- Allocation Management (7 tests)
- Claiming (12 tests - lump sum, vesting, cliff, partial)
- Administration (6 tests)
- View Functions (4 tests)
- Allowlist Integration (8 tests - compliance, batch operations, gas costs)

## Architecture

### Contracts

- `contracts/Claimdrop.sol` - Main distribution contract
- `contracts/mocks/MockERC20.sol` - Test ERC20 token

### Inheritance Chain

```
Claimdrop
├── Ownable2Step (OpenZeppelin)
├── ReentrancyGuard (OpenZeppelin)
└── Pausable (OpenZeppelin)
```

### Key Constants

- `MAX_ALLOCATION_BATCH_SIZE = 3000`
- `BASIS_POINTS_TOTAL = 10000` (100%)

## Gas Costs

Approximate gas costs on MANTRA testnet:

| Operation | Gas Cost |
|-----------|----------|
| Deploy | ~2,680,000 |
| Create Campaign | ~238,000 |
| Add Allocations (100) | ~4,000,000 |
| Claim | ~130,000-140,000 |
| Close Campaign | ~40,000 |

## Allowlist Integration

The Claimdrop contract supports optional allowlist integration for KYC/AML compliance and access control. When configured, users must be on the allowlist to claim tokens.

### Allowlist Contract

The implementation uses the production-ready [MANTRA Allowlist contract](https://github.com/MANTRA-Finance/mantra-rwa-token-primary-sale-contract-v1) from the primary-sale repository, which provides:

- **Access Control**: Role-based permissions (DEFAULT_ADMIN_ROLE, COMPLIANCE_ROLE)
- **Pausable**: Emergency pause functionality
- **Batch Updates**: Efficient batch allowlist management via `setAllowedBatch()`
- **Audit Trail**: Events for transparency (AllowlistUpdated, ContractPaused, ContractUnpaused)
- **EIP-712**: Support for future off-chain signature verification

### Setup

The allowlist contract is included as a git submodule:

```bash
# Initialize submodules (if not already done)
git submodule update --init --recursive

# The Allowlist contract is available at:
# evm/lib/primary-sale/packages/evm/contracts/Allowlist.sol
```

### Usage

#### Creating a Campaign with Allowlist

When creating a campaign, pass the allowlist contract address as the last parameter:

```solidity
// Deploy Allowlist contract
Allowlist allowlist = new Allowlist(msg.sender);

// Create campaign with allowlist enabled
claimdrop.createCampaign(
    "KYC Required Campaign",
    "Only verified users can claim",
    "airdrop",
    rewardTokenAddress,
    totalReward,
    distributions,
    startTime,
    endTime,
    address(allowlist)  // Enable allowlist
);

// To disable allowlist, pass address(0)
claimdrop.createCampaign(..., address(0));
```

#### Managing the Allowlist

```solidity
// Add users to allowlist (batch operation)
address[] memory users = new address[](3);
users[0] = 0x123...;
users[1] = 0x456...;
users[2] = 0x789...;

bool[] memory allowed = new bool[](3);
allowed[0] = true;  // Allow
allowed[1] = true;  // Allow
allowed[2] = false; // Deny/Remove

allowlist.setAllowedBatch(users, allowed);

// Check if user is allowed
bool isUserAllowed = allowlist.isAllowed(userAddress);
```

### Key Features

**Optional Integration**: Set `address(0)` to disable allowlist checking (zero gas overhead)

**Fail-Safe Design**: Invalid allowlist contracts cause claims to revert (prevents unauthorized access)

**Blacklist Priority**: Blacklist check occurs before allowlist check (cheaper local storage access first)

**Batch Compatibility**: Allowlist validation applies to both single claims and batch operations

### Use Cases

- **KYC/AML Compliance**: Only verified addresses can claim tokens
- **Token Gating**: Restrict claims to specific token holders
- **Partner Campaigns**: Limit access to partner community members
- **Sybil Prevention**: Ensure only verified unique users can participate

### Gas Costs

| Operation | Gas Cost (without allowlist) | Gas Cost (with allowlist) | Overhead |
|-----------|------------------------------|---------------------------|----------|
| Claim | ~130-140k | ~210-250k | ~2,600 gas |
| Batch Claim (100 users) | ~4.5M | ~4.76M | ~2,600 gas/user |

The allowlist check adds approximately **2,600 gas per claim** (SLOAD + external view call).

### Security Considerations

**Allowlist Contract Reliability**: The allowlist contract is a critical dependency - ensure it's audited and trusted

**Centralization Risk**: Allowlist management is controlled by addresses with COMPLIANCE_ROLE

**Immutability**: Allowlist address cannot be changed after campaign creation

**External Call Risks**: Failed allowlist contract calls will revert claims (fail-safe behavior)

## Security

- Reentrancy protection on all external calls
- Owner protection (cannot be blacklisted)
- Two-step ownership transfer
- Pausable for emergency situations
- Comprehensive access control
- Optional allowlist integration for KYC/AML compliance

## Configuration

### Environment Variables (`.env`)

```bash
# Network RPC URLs
MANTRA_DUKONG_RPC_URL=https://evm.dukong.mantrachain.io
MANTRA_MAINNET_RPC_URL=https://evm.mantrachain.io

# Deployment
PRIVATE_KEY=<your_private_key>
OWNER_ADDRESS=<optional_owner_address>
```

### Compiler Settings (`foundry.toml`)

- Solidity: 0.8.24
- Optimizer: Enabled (200 runs)
- IR Optimizer: Enabled (`via_ir = true`)

## Foundry Documentation

- [Foundry Book](https://book.getfoundry.sh/)
- [Forge Reference](https://book.getfoundry.sh/reference/forge/)
- [Cast Reference](https://book.getfoundry.sh/reference/cast/)


## License

MIT
