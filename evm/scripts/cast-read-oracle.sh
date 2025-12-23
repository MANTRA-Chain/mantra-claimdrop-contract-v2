#!/usr/bin/env bash
#
# Cast-based script to read the latest price from PyseOracle contract
#
# This script calls the getLatestPrice() function of the PyseOracle contract
# to retrieve the current price value.
#
# Usage:
#   RPC_URL="https://evm.dukong.mantrachain.io" PYSE_ORACLE="0xca823a7c89431BF8932b3C521dEF66542aE856b5" ./scripts/cast-read-oracle.sh
#
# Required Environment Variables:
#   RPC_URL      - RPC endpoint URL
#   PYSE_ORACLE  - PyseOracle contract address
#
# Optional Environment Variables:
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

# ============================================================================
# Main Execution Flow
# ============================================================================

main() {
    log_info "=========================================="
    log_info "  Cast Read Oracle Script"
    log_info "=========================================="
    echo ""

    # Setup and validate environment
    log_info "Validating environment and configuration..."

    # Validate required variables
    require_env_var "PYSE_ORACLE" || exit 1

    validate_address "$PYSE_ORACLE" "PyseOracle address" || exit 1
    validate_contract_exists "$PYSE_ORACLE" "$RPC_URL" "PyseOracle" || exit 1
    echo ""

    log_info "PyseOracle: $PYSE_ORACLE"
    echo ""

    # Read oracle price
    read_oracle_price

    # Print summary
    print_summary
}

# ============================================================================
# Execution Functions
# ============================================================================

read_oracle_price() {
    log_info "Reading latest price from oracle..."

    local price
    price=$(cast call \
        --rpc-url "$RPC_URL" \
        "$PYSE_ORACLE" \
        "getLatestPrice()") || {
        log_error "Failed to read price from oracle"
        exit 1
    }

    log_success "Successfully read price from oracle"
    log_info "   Price: $price"
    echo ""
}

print_summary() {
    log_info "=========================================="
    log_info "  ✅ Oracle Price Read Successfully"
    log_info "=========================================="
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
