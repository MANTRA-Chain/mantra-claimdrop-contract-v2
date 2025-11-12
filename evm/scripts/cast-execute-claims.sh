#!/usr/bin/env bash
#
# Cast-based sequential claims execution for Cosmos SDK EVM compatibility
#
# This script executes test claims for predefined test addresses.
# Waits for campaign start time if needed, then executes claims with proper confirmation.
#
# Usage:
#   ./scripts/cast-execute-claims.sh
#
# Required Environment Variables:
#   RPC_URL      - RPC endpoint URL
#   PRIVATE_KEY  - Deployer private key (used to submit claim transactions)
#   CLAIMDROP    - Claimdrop contract address
#   START_TIME   - Campaign start timestamp
#
# Optional Environment Variables:
#   GAS_PRICE              - Manual gas price override in wei (default: dynamic estimation)
#   TX_CONFIRMATION_TIMEOUT - Transaction confirmation timeout in seconds (default: 180)
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

# Test addresses (same as in setup script)
TEST_USER_1="0x0000000000000000000000000000000000000001"
TEST_USER_2="0x0000000000000000000000000000000000000002"
TEST_USER_3="0x0000000000000000000000000000000000000003"
TEST_USER_4="0x0000000000000000000000000000000000000004"
TEST_USER_5="0x0000000000000000000000000000000000000005"

# ============================================================================
# Main Execution Flow
# ============================================================================

main() {
    log_info "=========================================="
    log_info "  E2E Cast Execute Claims Script"
    log_info "=========================================="
    echo ""

    # Setup and validate environment
    log_info "Validating environment and configuration..."
    setup_environment || exit 1

    # Validate required variables
    require_env_var "CLAIMDROP" || exit 1
    require_env_var "START_TIME" || exit 1

    validate_address "$CLAIMDROP" "Claimdrop address" || exit 1
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
    echo ""

    # Validation: Wait for campaign start if needed
    validate_campaign_started

    # Execute claims
    execute_test_claims

    # Print summary
    print_summary
}

# ============================================================================
# Validation and Execution Functions
# ============================================================================

validate_campaign_started() {
    log_info "Validation: Checking campaign start time..."

    local current_time
    current_time=$(date +%s)

    if [ "$current_time" -lt "$START_TIME" ]; then
        local wait_time=$((START_TIME - current_time))
        log_info "Campaign not yet started. Waiting ${wait_time} seconds..."
        log_info "Current time: $current_time"
        log_info "Start time:   $START_TIME"
        sleep "$wait_time"
        log_success "Campaign has started"
    else
        log_success "Campaign already started (current: $current_time, start: $START_TIME)"
    fi

    echo ""
}

execute_test_claims() {
    log_info "Executing test claims..."
    echo ""

    local total_claimed=0

    # User 1: Claim full lump sum amount (30% of 10 tokens = 3 tokens)
    execute_claim "$TEST_USER_1" "3000000000000000000" "User 1" "3 tokens (full lump sum)"
    total_claimed=$((total_claimed + 3))

    # User 2: Claim partial amount (1.5 tokens = 50% of lump sum)
    execute_claim "$TEST_USER_2" "1500000000000000000" "User 2" "1.5 tokens (50% of lump sum)"
    total_claimed=$((total_claimed + 1))

    # User 3: Claim full amount
    execute_claim "$TEST_USER_3" "3000000000000000000" "User 3" "3 tokens"
    total_claimed=$((total_claimed + 3))

    # User 4: Claim full amount
    execute_claim "$TEST_USER_4" "3000000000000000000" "User 4" "3 tokens"
    total_claimed=$((total_claimed + 3))

    # User 5: Claim full amount
    execute_claim "$TEST_USER_5" "3000000000000000000" "User 5" "3 tokens"
    total_claimed=$((total_claimed + 3))

    TOTAL_CLAIMED=$total_claimed
}

execute_claim() {
    local user_address="$1"
    local claim_amount="$2"
    local label="$3"
    local description="$4"

    log_info "$label: $user_address"

    local tx_hash
    tx_hash=$(send_tx \
        "Claim for $label" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        ${LEGACY_FLAG:+--legacy} \
        --gas-price "$GAS_PRICE" \
        --json \
        "$CLAIMDROP" \
        "claim(address,uint256)" \
        "$user_address" \
        "$claim_amount") || {
        log_error "Failed to execute claim for $label"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Claim for $label" || {
        log_error "Claim transaction failed for $label"
        exit 1
    }

    log_success "  Claimed $description"
    log_info "  Transaction: $tx_hash"
    echo ""
}

print_summary() {
    log_info "=========================================="
    log_info "  ✅ Claims Complete"
    log_info "=========================================="
    echo ""
    echo "Total distributed: ${TOTAL_CLAIMED:-13} tokens"
    echo "Remaining: ~87 tokens in contract"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
