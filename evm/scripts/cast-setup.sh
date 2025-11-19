#!/usr/bin/env bash
#
# Cast-based campaign setup for Cosmos SDK EVM compatibility
#
# This script:
# 1. Mints test tokens to deployer
# 2. Approves Claimdrop contract for token transfer
# 3. Creates campaign with proper timing (using actual block timestamp)
# 4. Transfers reward tokens to contract
# 5. Adds test allocations
#
# Usage:
#   ./scripts/cast-setup.sh
#
# Required Environment Variables:
#   RPC_URL      - RPC endpoint URL
#   PRIVATE_KEY  - Deployer private key
#   MOCKERC20    - MockERC20 contract address
#   CLAIMDROP    - Claimdrop contract address
#   START_TIME   - Campaign start timestamp (will be recalculated for safety)
#   END_TIME     - Campaign end timestamp (will be recalculated for safety)
#
# Optional Environment Variables:
#   GAS_PRICE              - Manual gas price override in wei (default: dynamic estimation)
#   TX_CONFIRMATION_TIMEOUT - Transaction confirmation timeout in seconds (default: 180)
#   CAMPAIGN_START_BUFFER  - Buffer in seconds after campaign creation (default: 30)
#   DEBUG                  - Enable debug logging (default: 0)
#
# Security Notes:
#   - Store PRIVATE_KEY in .env file with 600 permissions (chmod 600 .env)
#   - Ensure .env is in .gitignore to prevent accidental commits
#

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Configuration
GAS_LIMIT="${GAS_LIMIT:-5000000}"
LEGACY_FLAG="${LEGACY_FLAG:-true}"

# ============================================================================
# Main Setup Flow
# ============================================================================

main() {
    log_info "=========================================="
    log_info "  E2E Cast Setup Script"
    log_info "=========================================="
    echo ""

    # Setup and validate environment
    log_info "Validating environment and configuration..."
    setup_environment || exit 1

    # Validate required contract addresses
    require_env_var "MOCKERC20" || exit 1
    require_env_var "CLAIMDROP" || exit 1
    require_env_var "START_TIME" || exit 1
    require_env_var "END_TIME" || exit 1

    validate_address "$MOCKERC20" "MockERC20 address" || exit 1
    validate_address "$CLAIMDROP" "Claimdrop address" || exit 1
    validate_contract_exists "$MOCKERC20" "$RPC_URL" "MockERC20" || exit 1
    validate_contract_exists "$CLAIMDROP" "$RPC_URL" "Claimdrop" || exit 1
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

    log_info "Deployer: $DEPLOYER"
    log_info "Claimdrop: $CLAIMDROP"
    log_info "MockERC20: $MOCKERC20"
    echo ""

    # Execute setup phases
    mint_test_tokens
    approve_token_transfer
    create_campaign_with_safe_timing
    transfer_reward_tokens
    add_test_allocations

    # Print summary
    print_summary
}

# ============================================================================
# Setup Functions
# ============================================================================

mint_test_tokens() {
    log_info "Phase 1: Minting test tokens..."

    local mint_amount="1000000000000000000000000" # 1M with 18 decimals

    local tx_hash
    tx_hash=$(send_tx \
        "Mint test tokens" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        ${LEGACY_FLAG:+--legacy} \
        --gas-price "$GAS_PRICE" \
        --json \
        "$MOCKERC20" \
        "mint(address,uint256)" \
        "$DEPLOYER" \
        "$mint_amount") || {
        log_error "Failed to mint tokens"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Mint tokens" || {
        log_error "Token minting transaction failed"
        exit 1
    }

    log_success "Minted 1,000,000 tokens to deployer"
    log_info "   Transaction: $tx_hash"
    echo ""
}

approve_token_transfer() {
    log_info "Phase 2: Approving token transfer..."

    local max_uint256="115792089237316195423570985008687907853269984665640564039457584007913129639935"

    local tx_hash
    tx_hash=$(send_tx \
        "Approve token transfer" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        ${LEGACY_FLAG:+--legacy} \
        --gas-price "$GAS_PRICE" \
        --json \
        "$MOCKERC20" \
        "approve(address,uint256)" \
        "$CLAIMDROP" \
        "$max_uint256") || {
        log_error "Failed to approve token transfer"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Approve transfer" || {
        log_error "Token approval transaction failed"
        exit 1
    }

    log_success "Approved maximum token transfer"
    log_info "   Transaction: $tx_hash"
    echo ""
}

create_campaign_with_safe_timing() {
    log_info "Phase 3: Creating campaign with safe timing..."

    # Get current block timestamp for accurate timing calculation
    log_info "Querying current block timestamp..."
    local block_timestamp
    block_timestamp=$(get_block_timestamp "$RPC_URL") || {
        log_error "Failed to get block timestamp"
        exit 1
    }
    log_debug "Current block timestamp: $block_timestamp"

    # Calculate safe start time with configurable buffer
    # This accounts for: transaction submission + confirmation + safety margin
    local start_time=$((block_timestamp + CAMPAIGN_START_BUFFER))
    local end_time=$((start_time + 120))  # 120 second campaign duration

    log_info "Campaign timing calculation:"
    log_info "  Block timestamp: $block_timestamp"
    log_info "  Start buffer:    ${CAMPAIGN_START_BUFFER}s"
    log_info "  Start time:      $start_time"
    log_info "  End time:        $end_time"
    echo ""

    # Validate start time is in the future
    local current_time
    current_time=$(date +%s)
    if [ "$start_time" -le "$current_time" ]; then
        log_error "Calculated start time ($start_time) is not in the future (current: $current_time)"
        log_error "Increase CAMPAIGN_START_BUFFER or check system time"
        exit 1
    fi
    log_debug "Start time validated as future timestamp"

    # Build Distribution array
    # Distribution struct: (DistributionKind kind, uint16 percentageBps, uint64 startTime, uint64 endTime, uint64 cliffDuration)
    # DistributionKind: 0=LinearVesting, 1=LumpSum
    local distributions="[(1,3000,$start_time,0,0),(0,7000,$start_time,$end_time,0)]"

    log_info "Creating campaign..."
    local tx_hash
    tx_hash=$(send_tx \
        "Create campaign" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        ${LEGACY_FLAG:+--legacy} \
        --gas-price "$GAS_PRICE" \
        --json \
        "$CLAIMDROP" \
        "createCampaign(string,string,string,address,uint256,(uint8,uint16,uint64,uint64,uint64)[],uint64,uint64)" \
        "E2E Test Campaign" \
        "Pure cast E2E testing - no forge scripts" \
        "e2e-test" \
        "$MOCKERC20" \
        "100000000000000000000" \
        "$distributions" \
        "$start_time" \
        "$end_time") || {
        log_error "Failed to create campaign"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Create campaign" || {
        log_error "Campaign creation transaction failed"
        exit 1
    }

    # Update global timing variables for subsequent phases
    START_TIME=$start_time
    END_TIME=$end_time

    log_success "Campaign created with safe timing"
    log_info "   Transaction: $tx_hash"
    log_info "   Distributions: 30% lump sum, 70% linear vesting"
    echo ""
}

transfer_reward_tokens() {
    log_info "Phase 4: Transferring reward tokens to contract..."

    local reward_amount="100000000000000000000"  # 100 tokens with 18 decimals

    local tx_hash
    tx_hash=$(send_tx \
        "Transfer reward tokens" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        ${LEGACY_FLAG:+--legacy} \
        --gas-price "$GAS_PRICE" \
        --json \
        "$MOCKERC20" \
        "transfer(address,uint256)" \
        "$CLAIMDROP" \
        "$reward_amount") || {
        log_error "Failed to transfer tokens"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Transfer tokens" || {
        log_error "Token transfer transaction failed"
        exit 1
    }

    log_success "Transferred 100 tokens to contract"
    log_info "   Transaction: $tx_hash"
    echo ""
}

add_test_allocations() {
    log_info "Phase 5: Adding test allocations..."

    # Build address and amount arrays (5 test users, 10 tokens each)
    local addresses="[0x0000000000000000000000000000000000000001,0x0000000000000000000000000000000000000002,0x0000000000000000000000000000000000000003,0x0000000000000000000000000000000000000004,0x0000000000000000000000000000000000000005]"
    local amounts="[10000000000000000000,10000000000000000000,10000000000000000000,10000000000000000000,10000000000000000000]"

    local tx_hash
    tx_hash=$(send_tx \
        "Add allocations" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        ${LEGACY_FLAG:+--legacy} \
        --gas-price "$GAS_PRICE" \
        --json \
        "$CLAIMDROP" \
        "addAllocations(address[],uint256[])" \
        "$addresses" \
        "$amounts") || {
        log_error "Failed to add allocations"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Add allocations" || {
        log_error "Add allocations transaction failed"
        exit 1
    }

    log_success "Allocations added successfully"
    log_info "   Transaction: $tx_hash"
    log_info "   5 users × 10 tokens each"
    echo ""
}

print_summary() {
    # Update deployments.txt with accurate timing
    cat > deployments.txt <<EOF
MOCKERC20=$MOCKERC20
CLAIMDROP=$CLAIMDROP
DEPLOYER=$DEPLOYER
START_TIME=$START_TIME
END_TIME=$END_TIME
EOF

    log_info "=========================================="
    log_info "  ✅ Setup Complete"
    log_info "=========================================="
    echo ""
    echo "Campaign Configuration:"
    echo "  Start Time: $START_TIME ($(date -r "$START_TIME" 2>/dev/null || date -d "@$START_TIME" 2>/dev/null || echo "timestamp"))"
    echo "  End Time:   $END_TIME ($(date -r "$END_TIME" 2>/dev/null || date -d "@$END_TIME" 2>/dev/null || echo "timestamp"))"
    echo ""
    echo "Updated deployments.txt with accurate timing"
    echo "Next step: run 'just e2e-execute' after campaign starts"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
