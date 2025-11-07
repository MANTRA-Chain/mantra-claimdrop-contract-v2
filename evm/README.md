# MANTRA Claimdrop - EVM Implementation

Token distribution contract with vesting capabilities for Ethereum-compatible chains.

## Features

- **Campaign management** (create/close)
- **Batch allocation uploads** (up to 3000 per batch)
- **Multiple distribution types** (lump sum + linear vesting)
- **Partial claims supported**
- **Cliff periods for vesting**
- **Blacklist functionality**
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
```

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
# - MANTRA_API_KEY

just deploy-testnet
```

### MANTRA Mainnet

```bash
# Ensure .env is configured with:
# - MANTRA_MAINNET_RPC_URL
# - PRIVATE_KEY
# - MANTRA_API_KEY

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

The test suite includes **41 comprehensive tests** covering:

- Deployment (3 tests)
- Campaign Management (9 tests)
- Allocation Management (7 tests)
- Claiming (12 tests - lump sum, vesting, cliff, partial)
- Administration (6 tests)
- View Functions (4 tests)

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

## Security

- Reentrancy protection on all external calls
- Owner protection (cannot be blacklisted)
- Two-step ownership transfer
- Pausable for emergency situations
- Comprehensive access control

## Configuration

### Environment Variables (`.env`)

```bash
# Network RPC URLs
MANTRA_DUKONG_RPC_URL=https://evm.dukong.mantrachain.io
MANTRA_MAINNET_RPC_URL=https://evm.mantrachain.io

# Deployment
PRIVATE_KEY=<your_private_key>
OWNER_ADDRESS=<optional_owner_address>

# Block Explorer
MANTRA_API_KEY=<your_api_key>
```

### Compiler Settings (`foundry.toml`)

- Solidity: 0.8.24
- Optimizer: Enabled (200 runs)
- IR Optimizer: Enabled (`via_ir = true`)

## Foundry Documentation

- [Foundry Book](https://book.getfoundry.sh/)
- [Forge Reference](https://book.getfoundry.sh/reference/forge/)
- [Cast Reference](https://book.getfoundry.sh/reference/cast/)

## Migration from Hardhat

This project was migrated from Hardhat to Foundry for:

- **Native language testing**: Solidity tests for Solidity contracts
- **Performance**: 30-50% faster compilation and testing
- **Unified toolchain**: Rust-based tooling across the project
- **Modern best practices**: Industry-leading framework for 2025

All 41 tests were successfully ported from JavaScript to Solidity.

## License

MIT
