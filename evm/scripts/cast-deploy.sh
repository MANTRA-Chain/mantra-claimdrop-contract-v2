#!/usr/bin/env bash
#
# Cast-based sequential contract deployment for Cosmos SDK EVM compatibility
#
# This script deploys contracts using `cast send --create` for explicit nonce management
# instead of forge script batch broadcasting (which fails on Cosmos SDK EVMs).
#
# Usage:
#   ./scripts/cast-deploy.sh
#
# Required Environment Variables:
#   RPC_URL      - RPC endpoint URL
#   PRIVATE_KEY  - Deployer private key (64 hex chars, with or without 0x prefix)
#
# Optional Environment Variables:
#   GAS_PRICE              - Manual gas price override in wei (default: dynamic estimation)
#   GAS_PRICE_MIN          - Minimum gas price in wei (default: 10 gwei)
#   GAS_PRICE_MAX          - Maximum gas price in wei (default: 200 gwei)
#   GAS_LIMIT              - Gas limit for transactions (default: 5000000)
#   TX_CONFIRMATION_TIMEOUT - Transaction confirmation timeout in seconds (default: 180)
#   DEBUG                  - Enable debug logging (default: 0)
#
# Security Notes:
#   - Store PRIVATE_KEY in .env file with 600 permissions (chmod 600 .env)
#   - Ensure .env is in .gitignore to prevent accidental commits
#   - Never share or commit private keys
#

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Configuration
GAS_LIMIT="${GAS_LIMIT:-5000000}"
LEGACY_FLAG="${LEGACY_FLAG:-true}"

# ============================================================================
# Main Deployment Flow
# ============================================================================

main() {
    log_info "=========================================="
    log_info "  E2E Cast Deployment Script"
    log_info "=========================================="
    echo ""

    # Setup and validate environment
    log_info "Validating environment and configuration..."
    setup_environment || exit 1
    echo ""

    # Estimate gas price
    log_info "Estimating gas price..."
    GAS_PRICE=$(estimate_gas_price "$RPC_URL")
    GAS_PRICE_GWEI=$(echo "scale=2; $GAS_PRICE / 1000000000" | bc)
    log_info "Using gas price: ${GAS_PRICE_GWEI} gwei"
    echo ""

    # Get deployer address
    DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
    validate_address "$DEPLOYER" "Deployer address" || exit 1

    log_info "Deployer address: $DEPLOYER"

    # Check deployer balance
    BALANCE=$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL" --ether)
    log_info "Deployer balance: $BALANCE OM"
    echo ""

    # Build contracts
    log_info "Building contracts..."
    if ! forge build --quiet; then
        log_error "Failed to build contracts"
        exit 1
    fi
    log_success "Build complete"
    echo ""

    # Deploy MockERC20
    deploy_mock_erc20

    # Deploy Claimdrop
    deploy_claimdrop

    # Verify deployments on-chain
    verify_deployments

    # Save deployment state
    save_deployment_state

    # Print summary
    print_summary
}

# ============================================================================
# Deployment Functions
# ============================================================================

deploy_mock_erc20() {
    log_info "Phase 1: Deploying MockERC20 token..."

    MOCKERC20_BYTECODE=$(forge inspect contracts/mocks/MockERC20.sol:MockERC20 bytecode)

    # Encode constructor: constructor(string name, string symbol, uint8 decimals)
    MOCKERC20_CONSTRUCTOR=$(cast abi-encode \
        "constructor(string,string,uint8)" \
        "Test Token" \
        "TEST" \
        "18")

    # Deploy contract with transaction confirmation
    local tx_result
    tx_result=$(send_and_wait \
        "Deploy MockERC20" \
        "$RPC_URL" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        ${LEGACY_FLAG:+--legacy} \
        --gas-price "$GAS_PRICE" \
        --gas-limit "$GAS_LIMIT" \
        --json \
        --create "${MOCKERC20_BYTECODE}${MOCKERC20_CONSTRUCTOR:2}") || {
        log_error "Failed to deploy MockERC20"
        exit 1
    }

    MOCKERC20=$(parse_json_field "$tx_result" "contractAddress" "MockERC20 address") || exit 1
    MOCKERC20_TX_HASH=$(parse_json_field "$tx_result" "transactionHash" "Transaction hash") || exit 1

    validate_address "$MOCKERC20" "MockERC20 address" || exit 1

    log_success "MockERC20 deployed: $MOCKERC20"
    log_info "   Transaction: $MOCKERC20_TX_HASH"
    echo ""
}

deploy_claimdrop() {
    log_info "Phase 2: Deploying Claimdrop contract..."

    CLAIMDROP_BYTECODE=$(forge inspect contracts/Claimdrop.sol:Claimdrop bytecode)

    # Encode constructor: constructor(address initialOwner)
    CLAIMDROP_CONSTRUCTOR=$(cast abi-encode \
        "constructor(address)" \
        "$DEPLOYER")

    # Deploy contract with transaction confirmation
    local tx_result
    tx_result=$(send_and_wait \
        "Deploy Claimdrop" \
        "$RPC_URL" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        ${LEGACY_FLAG:+--legacy} \
        --gas-price "$GAS_PRICE" \
        --gas-limit "$GAS_LIMIT" \
        --json \
        --create "${CLAIMDROP_BYTECODE}${CLAIMDROP_CONSTRUCTOR:2}") || {
        log_error "Failed to deploy Claimdrop"
        exit 1
    }

    CLAIMDROP=$(parse_json_field "$tx_result" "contractAddress" "Claimdrop address") || exit 1
    CLAIMDROP_TX_HASH=$(parse_json_field "$tx_result" "transactionHash" "Transaction hash") || exit 1

    validate_address "$CLAIMDROP" "Claimdrop address" || exit 1

    log_success "Claimdrop deployed: $CLAIMDROP"
    log_info "   Transaction: $CLAIMDROP_TX_HASH"
    echo ""
}

verify_deployments() {
    log_info "Phase 3: Verifying deployments on-chain..."

    # Verify MockERC20
    if validate_contract_exists "$MOCKERC20" "$RPC_URL" "MockERC20"; then
        log_success "MockERC20 verified on-chain"
    else
        log_error "MockERC20 verification failed"
        exit 1
    fi

    # Verify Claimdrop
    if validate_contract_exists "$CLAIMDROP" "$RPC_URL" "Claimdrop"; then
        log_success "Claimdrop verified on-chain"
    else
        log_error "Claimdrop verification failed"
        exit 1
    fi

    echo ""
}

save_deployment_state() {
    log_info "Phase 4: Saving deployment state to deployments.txt..."

    # Calculate timing for E2E flow (5 second delay, then 60 second campaign)
    START_OFFSET="${START_OFFSET:-5}"
    DURATION="${DURATION:-60}"
    CURRENT_TIME=$(date +%s)
    START_TIME=$((CURRENT_TIME + START_OFFSET))
    END_TIME=$((START_TIME + DURATION))

    # Load sale parameters from environment or use defaults
    SOFT_CAP="${SOFT_CAP:-10000000000000000000}"        # 10 tokens (18 decimals)
    HARD_CAP="${HARD_CAP:-100000000000000000000}"       # 100 tokens
    MIN_STEP="${MIN_STEP:-1000000000000000000}"         # 1 token

    cat > deployments.txt <<EOF
# Contract Addresses
MOCKERC20=$MOCKERC20
CLAIMDROP=$CLAIMDROP
DEPLOYER=$DEPLOYER

# Timing Configuration (Unix timestamps)
START_TIME=$START_TIME
END_TIME=$END_TIME

# Campaign Parameters (18 decimals)
SOFT_CAP=$SOFT_CAP
HARD_CAP=$HARD_CAP
MIN_STEP=$MIN_STEP

# Distribution Configuration (basis points)
LUMP_SUM_PERCENTAGE_BPS=3000
VESTING_PERCENTAGE_BPS=7000
CLIFF_DURATION=0

# Vesting Configuration
VESTING_DURATION=$DURATION

# Network Configuration
RPC_URL=$RPC_URL
GAS_PRICE=$GAS_PRICE
EOF

    log_success "State saved to deployments.txt"
    echo ""
}

print_summary() {
    log_info "=========================================="
    log_info "  ✅ Deployment Complete"
    log_info "=========================================="
    echo ""
    echo "Deployment Summary:"
    echo "  MockERC20:      $MOCKERC20"
    echo "  Claimdrop:      $CLAIMDROP"
    echo "  Deployer:       $DEPLOYER"
    echo ""
    echo "Timing (Unix timestamps):"
    echo "  Start Time:     $START_TIME"
    echo "  End Time:       $END_TIME"
    echo ""
    echo "All addresses saved to: deployments.txt"
    echo "Next step: run 'just e2e-setup' to mint tokens and configure campaign"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
