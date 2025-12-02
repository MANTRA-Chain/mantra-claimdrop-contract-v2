#!/usr/bin/env bash
#
# Complete E2E test with funded test addresses
#
# This script orchestrates a complete end-to-end test:
# 1. Loads deployed contracts from deployments.txt
# 2. Generates temporary test addresses
# 3. Funds test addresses with OM from deployer
# 4. Mints tokens, approves, creates campaign (with safe timing)
# 5. Adds allocations for test addresses
# 6. Waits for campaign start
# 7. Executes claims from test addresses (using their own private keys)
# 8. Verifies token balances
# 9. Sweeps remaining OM back to deployer
#
# Usage:
#   ./scripts/cast-e2e-complete.sh
#
# Prerequisites:
#   - deployments.txt file exists (run cast-deploy.sh first)
#   - .env file with RPC_URL and PRIVATE_KEY
#
# Security Notes:
#   - Temporary wallets are generated and discarded after use
#   - Store PRIVATE_KEY in .env file with 600 permissions
#   - Ensure .env is in .gitignore
#

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Configuration
GAS_LIMIT="${GAS_LIMIT:-10000000}"  # Increased for complex claim operations
LEGACY_FLAG="--legacy"

# Report file for transaction tracking
REPORT_FILE="e2e-report.txt"

# ============================================================================
# Main E2E Flow
# ============================================================================

main() {
    log_info "=========================================="
    log_info "  Complete E2E Test with Funded Addresses"
    log_info "=========================================="
    echo ""

    # Load deployments
    load_deployments

    # Setup and validate environment
    log_info "Validating environment and configuration..."
    setup_environment || exit 1
    echo ""

    # Validate contract addresses
    validate_address "$MOCKERC20" "MockERC20 address" || exit 1
    validate_address "$CLAIMDROP" "Claimdrop address" || exit 1
    validate_contract_exists "$MOCKERC20" "$RPC_URL" "MockERC20" || exit 1
    validate_contract_exists "$CLAIMDROP" "$RPC_URL" "Claimdrop" || exit 1

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

    # Initialize report
    initialize_report

    # Execute E2E flow
    generate_test_addresses
    fund_test_addresses
    setup_campaign
    add_allocations
    wait_for_campaign_start
    execute_claims
    verify_balances
    sweep_remaining_funds

    # Print final summary
    print_final_summary
}

# ============================================================================
# Helper Functions
# ============================================================================

load_deployments() {
    if [ ! -f "deployments.txt" ]; then
        log_error "deployments.txt not found"
        log_error "Run 'just e2e-deploy' first"
        exit 1
    fi

    log_info "Loading deployments from deployments.txt..."

    # Export variables from deployments.txt, skipping comments and empty lines
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        if [[ "$key" =~ ^#.*$ ]] || [ -z "$key" ]; then
            continue
        fi
        # Export the variable
        export "$key=$value"
        log_debug "Loaded: $key=$value"
    done < deployments.txt

    require_env_var "MOCKERC20" || exit 1
    require_env_var "CLAIMDROP" || exit 1
    require_env_var "DEPLOYER" || exit 1
    require_env_var "START_TIME" || exit 1
    require_env_var "END_TIME" || exit 1

    log_success "Deployments loaded successfully"
    echo ""
}

initialize_report() {
    rm -f "$REPORT_FILE"

    {
        echo "NETWORK|$RPC_URL"
        echo "DEPLOYER|$DEPLOYER"
        echo "CLAIMDROP|$CLAIMDROP"
        echo "MOCKERC20|$MOCKERC20"
        echo "SEPARATOR|"
    } >> "$REPORT_FILE"

    log_debug "Initialized transaction report: $REPORT_FILE"
}

log_tx() {
    local label="$1"
    local tx_hash="$2"
    if [ -n "$tx_hash" ]; then
        echo "$label|$tx_hash" >> "$REPORT_FILE"
    fi
}

# ============================================================================
# Test Address Management
# ============================================================================

generate_test_addresses() {
    log_info "Step 1: Generating 3 test addresses..."

    TEST_ADDRS=()
    TEST_PKS=()

    for i in 1 2 3; do
        local wallet
        wallet=$(cast wallet new 2>/dev/null)
        local addr
        addr=$(echo "$wallet" | grep "Address:" | awk '{print $2}')
        local pk
        pk=$(echo "$wallet" | grep "Private key:" | awk '{print $3}')

        validate_address "$addr" "Test address $i" || exit 1

        TEST_ADDRS+=("$addr")
        TEST_PKS+=("$pk")

        log_info "  Test User $i: $addr"
    done

    echo ""
}

fund_test_addresses() {
    log_info "Step 2: Funding test addresses with 2 OM each..."

    for i in "${!TEST_ADDRS[@]}"; do
        local addr="${TEST_ADDRS[$i]}"
        local user_num=$((i + 1))

        log_info "  Funding User $user_num: $addr"

        local tx_hash
        tx_hash=$(send_tx \
            "Fund test address $user_num" \
            --rpc-url "$RPC_URL" \
            --private-key "$PRIVATE_KEY" \
            $LEGACY_FLAG \
            --gas-price "$GAS_PRICE" \
            --gas-limit "$GAS_LIMIT" \
            --json \
            --value 2ether \
            "$addr") || {
            log_error "Failed to fund test address $user_num"
            exit 1
        }

        wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Fund address $user_num" || {
            log_error "Funding transaction failed for user $user_num"
            exit 1
        }

        log_success "    Funded: $tx_hash"
        log_tx "Fund test address User $user_num" "$tx_hash"
    done

    echo ""
}

# ============================================================================
# Campaign Setup
# ============================================================================

setup_campaign() {
    log_info "Step 3: Setting up campaign..."

    # Mint tokens
    mint_tokens

    # Transfer reward tokens to contract BEFORE creating campaign
    # (createCampaign validates the contract has sufficient balance)
    transfer_reward_tokens

    # Create campaign with safe timing
    create_campaign

    echo ""
}

mint_tokens() {
    log_info "  Minting test tokens..."

    local mint_amount="1000000000000000000000000" # 1M tokens

    local tx_hash
    tx_hash=$(send_tx \
        "Mint tokens" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        $LEGACY_FLAG \
        --gas-price "$GAS_PRICE" \
        --gas-limit "$GAS_LIMIT" \
        --json \
        "$MOCKERC20" \
        "mint(address,uint256)" \
        "$DEPLOYER" \
        "$mint_amount") || {
        log_error "Failed to mint tokens"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Mint tokens" || {
        log_error "Mint transaction failed"
        exit 1
    }

    log_success "  Minted 1,000,000 tokens: $tx_hash"
    log_tx "Mint 1,000,000 test tokens" "$tx_hash"
}

approve_tokens() {
    log_info "  Approving token transfer..."

    local max_uint256="115792089237316195423570985008687907853269984665640564039457584007913129639935"

    local tx_hash
    tx_hash=$(send_tx \
        "Approve tokens" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        $LEGACY_FLAG \
        --gas-price "$GAS_PRICE" \
        --gas-limit "$GAS_LIMIT" \
        --json \
        "$MOCKERC20" \
        "approve(address,uint256)" \
        "$CLAIMDROP" \
        "$max_uint256") || {
        log_error "Failed to approve tokens"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Approve tokens" || {
        log_error "Approval transaction failed"
        exit 1
    }

    log_success "  Approved transfer: $tx_hash"
    log_tx "Approve token transfer to Claimdrop" "$tx_hash"
}

create_campaign() {
    log_info "  Creating campaign with safe timing..."

    # Get current block timestamp for accurate timing
    local block_timestamp
    block_timestamp=$(get_block_timestamp "$RPC_URL") || {
        log_error "Failed to get block timestamp"
        exit 1
    }

    # Calculate safe start time
    START_TIME=$((block_timestamp + CAMPAIGN_START_BUFFER))
    END_TIME=$((START_TIME + 120))

    log_info "  Campaign timing: start=$START_TIME, end=$END_TIME"

    # Build distributions
    local distributions="[(1,3000,$START_TIME,0,0),(0,7000,$START_TIME,$END_TIME,0)]"

    local tx_hash
    tx_hash=$(send_tx \
        "Create campaign" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        $LEGACY_FLAG \
        --gas-price "$GAS_PRICE" \
        --gas-limit "$GAS_LIMIT" \
        --json \
        "$CLAIMDROP" \
        "createCampaign(string,string,string,address,uint256,(uint8,uint16,uint64,uint64,uint64)[],uint64,uint64,address)" \
        "E2E Complete Test Campaign" \
        "Fully automated E2E test with funded addresses" \
        "e2e-complete" \
        "$MOCKERC20" \
        "100000000000000000000" \
        "$distributions" \
        "$START_TIME" \
        "$END_TIME" \
        "0x0000000000000000000000000000000000000000") || {
        log_error "Failed to create campaign"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Create campaign" || {
        log_error "Campaign creation failed"
        exit 1
    }

    log_success "  Campaign created: $tx_hash"
    log_info "     30% lump sum + 70% linear vesting"
    log_tx "Create campaign (30% lump + 70% vesting)" "$tx_hash"
}

transfer_reward_tokens() {
    log_info "  Transferring reward tokens to contract..."

    local reward_amount="100000000000000000000"

    local tx_hash
    tx_hash=$(send_tx \
        "Transfer reward tokens" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        $LEGACY_FLAG \
        --gas-price "$GAS_PRICE" \
        --gas-limit "$GAS_LIMIT" \
            --json \
        "$MOCKERC20" \
        "transfer(address,uint256)" \
        "$CLAIMDROP" \
        "$reward_amount") || {
        log_error "Failed to transfer tokens"
        exit 1
    }

    wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Transfer tokens" || {
        log_error "Transfer transaction failed"
        exit 1
    }

    log_success "  Transferred 100 tokens: $tx_hash"
    log_tx "Transfer 100 tokens to Claimdrop contract" "$tx_hash"
}

# ============================================================================
# Allocations
# ============================================================================

add_allocations() {
    log_info "Step 4: Adding allocations for test addresses..."

    # Build address and amount arrays
    local addresses="[${TEST_ADDRS[0]},${TEST_ADDRS[1]},${TEST_ADDRS[2]}]"
    local amounts="[10000000000000000000,10000000000000000000,10000000000000000000]"

    log_debug "Addresses: $addresses"
    log_debug "Amounts: $amounts"

    local tx_hash
    tx_hash=$(send_tx \
        "Add allocations" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        $LEGACY_FLAG \
        --gas-price "$GAS_PRICE" \
        --gas-limit "$GAS_LIMIT" \
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

    log_success "Allocations added: $tx_hash"
    log_info "   3 users × 10 tokens each"
    log_tx "Add allocations (3 users × 10 tokens)" "$tx_hash"

    echo ""
}

# ============================================================================
# Claims Execution
# ============================================================================

wait_for_campaign_start() {
    # Use block timestamp instead of system time for accuracy
    local current_block_time
    current_block_time=$(get_block_timestamp "$RPC_URL") || {
        log_error "Failed to get block timestamp"
        exit 1
    }

    log_debug "Current block timestamp: $current_block_time"
    log_debug "Campaign start time: $START_TIME"

    if [ "$current_block_time" -lt "$START_TIME" ]; then
        # Calculate wait time with 3 block buffer (~18 seconds on MANTRA)
        local wait_time=$((START_TIME - current_block_time + 18))
        log_info "Step 5: Waiting $wait_time seconds for campaign start (with buffer)..."
        sleep "$wait_time"

        # Verify campaign started by checking block time again
        current_block_time=$(get_block_timestamp "$RPC_URL")
        log_info "  After wait - block time: $current_block_time, start time: $START_TIME"

        if [ "$current_block_time" -lt "$START_TIME" ]; then
            log_warn "  Campaign may not have started yet, waiting 10 more seconds..."
            sleep 10
        fi
    else
        log_info "Step 5: Campaign already started ✓"
    fi

    echo ""
}

execute_claims() {
    log_info "Step 6: Executing claims from test addresses..."

    for i in 0 1 2; do
        local addr="${TEST_ADDRS[$i]}"
        local pk="${TEST_PKS[$i]}"
        local user_num=$((i + 1))

        log_info "  User $user_num ($addr):"

        # First, simulate the claim to check for any reverts
        log_info "  Simulating claim for debugging..."
        local sim_output
        sim_output=$(cast call \
            --rpc-url "$RPC_URL" \
            --from "$addr" \
            "$CLAIMDROP" \
            "claim(address,uint256)" \
            "$addr" \
            "3000000000000000000" 2>&1) || {
            log_error "  Claim simulation failed:"
            echo "$sim_output"
            log_error "  Skipping actual transaction due to simulation failure"
            exit 1
        }
        log_info "  Simulation successful: $sim_output"

        # Claim 3 tokens (30% lump sum from 10 token allocation)
        local tx_hash
        tx_hash=$(send_tx \
            "Claim for User $user_num" \
            --rpc-url "$RPC_URL" \
            --private-key "$pk" \
            $LEGACY_FLAG \
            --gas-price "$GAS_PRICE" \
            --gas-limit "$GAS_LIMIT" \
            --json \
            "$CLAIMDROP" \
            "claim(address,uint256)" \
            "$addr" \
            "3000000000000000000") || {
            log_error "Claim failed for User $user_num"
            exit 1
        }

        wait_for_tx "$tx_hash" "$RPC_URL" "$TX_CONFIRMATION_TIMEOUT" "Claim User $user_num" || {
            log_error "Claim transaction failed for User $user_num"
            exit 1
        }

        log_success "    Claimed 3 tokens: $tx_hash"
        log_tx "User $user_num claim 3 tokens" "$tx_hash"
    done

    echo ""
}

# ============================================================================
# Verification and Cleanup
# ============================================================================

verify_balances() {
    log_info "Step 7: Verifying token balances..."

    for i in 0 1 2; do
        local addr="${TEST_ADDRS[$i]}"
        local user_num=$((i + 1))

        local balance_raw
        balance_raw=$(cast call \
            --rpc-url "$RPC_URL" \
            "$MOCKERC20" \
            "balanceOf(address)(uint256)" \
            "$addr" 2>/dev/null || echo "0")

        # Extract just the number
        local balance
        balance=$(echo "$balance_raw" | grep -oE "^[0-9]+" | head -1)
        balance=${balance:-0}

        # Convert from wei to tokens (18 decimals)
        local balance_tokens
        balance_tokens=$(echo "scale=2; $balance / 1000000000000000000" | bc 2>/dev/null || echo "0")

        log_info "  User $user_num: $balance_tokens tokens"
    done

    echo ""
}

sweep_remaining_funds() {
    log_info "Step 8: Sweeping remaining OM back to deployer..."

    for i in 0 1 2; do
        local addr="${TEST_ADDRS[$i]}"
        local pk="${TEST_PKS[$i]}"
        local user_num=$((i + 1))

        # Get current balance
        local balance
        balance=$(cast balance --rpc-url "$RPC_URL" "$addr" 2>/dev/null || echo "0")

        if [ "$balance" != "0" ] && [ -n "$balance" ]; then
            # Calculate amount to send (balance - gas cost - buffer)
            local gas_cost=$((21000 * GAS_PRICE))
            local send_amount=$((balance - gas_cost - 100000000000))

            if [ "$send_amount" -gt 0 ]; then
                local balance_om
                balance_om=$(echo "scale=4; $send_amount / 1000000000000000000" | bc)
                log_info "  Sweeping from User $user_num: $balance_om OM"

                local tx_hash
                tx_hash=$(send_tx \
                    "Sweep OM User $user_num" \
                    --rpc-url "$RPC_URL" \
                    --private-key "$pk" \
                    $LEGACY_FLAG \
                    --gas-price "$GAS_PRICE" \
            --json \
                    --value "$send_amount" \
                    "$DEPLOYER") || {
                    log_warn "Failed to sweep from User $user_num (non-critical)"
                    continue
                }

                # Don't wait for confirmation on sweeps (non-critical)
                log_success "    Swept: $tx_hash"
                log_tx "Sweep OM from User $user_num back to deployer" "$tx_hash"
            else
                log_info "  User $user_num: Insufficient balance to sweep"
            fi
        fi
    done

    echo ""
}

# ============================================================================
# Summary
# ============================================================================

print_final_summary() {
    log_success "=========================================="
    log_success "  ✅ Complete E2E Test PASSED"
    log_success "=========================================="
    echo ""
    echo "📊 Transaction report saved to: $REPORT_FILE"
    echo "   Run 'just e2e-report' to view formatted report with Mantrascan links"
    echo ""
    echo "Summary:"
    echo "  - Generated 3 temporary test addresses"
    echo "  - Funded with 0.5 OM each from deployer"
    echo "  - Minted tokens, approved, created campaign (pure cast)"
    echo "  - Added allocations (10 tokens each, pure cast)"
    echo "  - Executed claims (3 tokens each, pure cast)"
    echo "  - Verified token balances"
    echo "  - Swept remaining OM back to deployer"
    echo ""
    echo "All operations used pure cast with robust transaction confirmation!"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
