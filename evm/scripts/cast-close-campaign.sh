#!/usr/bin/env bash
#
# Cast-based campaign closure for Cosmos SDK EVM compatibility
#
# This script closes an active campaign, returning unclaimed tokens to the owner.
# Waits for campaign end time if needed, then executes closure with proper confirmation.
#
# Usage:
#   ./scripts/cast-close-campaign.sh
#
# Required Environment Variables:
#   RPC_URL      - RPC endpoint URL
#   PRIVATE_KEY  - Deployer private key
#   CLAIMDROP    - Claimdrop contract address
#   END_TIME     - Campaign end timestamp
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

# ============================================================================
# Main Execution Flow
# ============================================================================

main() {
    log_info "=========================================="
    log_info "  E2E Cast Close Campaign Script"
    log_info "=========================================="
    echo ""

    # Setup and validate environment
    log_info "Validating environment and configuration..."
    setup_environment || exit 1

    # Validate required variables
    require_env_var "CLAIMDROP" || exit 1
    require_env_var "END_TIME" || exit 1

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

    # Validation: Wait for campaign end if needed
    validate_campaign_ended

    # Close campaign
    close_campaign

    # Print summary
    print_summary
}

# ============================================================================
# Validation and Execution Functions
# ============================================================================

validate_campaign_ended() {
    log_info "Validation: Checking campaign end time..."

    local current_time
    current_time=$(date +%s)

    if [ "$current_time" -lt "$END_TIME" ]; then
        local wait_time=$((END_TIME - current_time))
        log_info "Campaign not yet ended. Waiting ${wait_time} seconds..."
        log_info "Current time: $current_time"
        log_info "End time:     $END_TIME"
        sleep "$wait_time"
        log_success "Campaign end time has passed"
    else
        log_success "Campaign already ended (current: $current_time, end: $END_TIME)"
    fi

    echo ""
}

close_campaign() {
    log_info "Closing campaign..."

    local tx_hash
    tx_hash=$(send_tx \
        "Close campaign" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        ${LEGACY_FLAG:+--legacy} \
        --gas-price "$GAS_PRICE" \
        --json \
        "$CLAIMDROP" \
        "closeCampaign()") || {
        log_error "Failed to close campaign"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Close campaign" || {
        log_error "Campaign closure transaction failed"
        exit 1
    }

    log_success "Campaign closed successfully"
    log_info "   Transaction: $tx_hash"
    log_info "   Remaining tokens refunded to deployer"
    echo ""
}

print_summary() {
    log_info "=========================================="
    log_info "  ✅ Campaign Closed Successfully"
    log_info "=========================================="
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
