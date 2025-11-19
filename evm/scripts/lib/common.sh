#!/usr/bin/env bash
#
# Common utilities for cast-based deployment scripts
#
# This library provides production-grade utilities for:
# - Robust error handling and logging
# - Security validation (private keys, file permissions)
# - Address validation and contract verification
# - Dynamic gas price estimation
# - Transaction confirmation with exponential backoff
# - Environment variable validation
#
# Variable Scope Strategy:
# - Module-level constants declared with 'readonly' or 'declare -r'
# - Module-level variables declared with 'declare' at top level
# - Function-local variables declared with 'local' within functions
# - Parameters passed explicitly rather than relying on globals
#
# Usage: source "$(dirname "$0")/lib/common.sh"
#

# Strict error handling
set -euo pipefail

# ============================================================================
# Configuration and Constants
# ============================================================================

# Color codes for terminal output (disabled in CI or non-TTY)
# These are module-level constants set once at load time
declare COLOR_RESET
declare COLOR_RED
declare COLOR_GREEN
declare COLOR_YELLOW
declare COLOR_BLUE
declare COLOR_GRAY

if [ -t 1 ] && [ "${CI:-false}" != "true" ]; then
    COLOR_RESET='\033[0m'
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_GRAY='\033[0;90m'
else
    COLOR_RESET=''
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_GRAY=''
fi

# Gas price bounds (in wei)
# These can be overridden by environment variables
declare GAS_PRICE_MIN="${GAS_PRICE_MIN:-10000000000}"    # 10 gwei
declare GAS_PRICE_MAX="${GAS_PRICE_MAX:-200000000000}"   # 200 gwei
declare -r GAS_PRICE_DEFAULT="50000000000"                 # 50 gwei (constant)

# Transaction confirmation settings
# These can be overridden by environment variables
declare TX_CONFIRMATION_TIMEOUT="${TX_CONFIRMATION_TIMEOUT:-180}"  # 3 minutes
declare CAMPAIGN_START_BUFFER="${CAMPAIGN_START_BUFFER:-30}"       # 30 seconds

# Timestamp validation bounds (Unix timestamps)
# These are constants and cannot be modified
declare -r TIMESTAMP_MIN=1600000000  # Sep 2020 - before most EVM chains launched
declare -r TIMESTAMP_MAX=$(($(date +%s) + 31536000))  # Current time + 1 year

# Debug mode
declare DEBUG="${DEBUG:-0}"

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${COLOR_BLUE}ℹ${COLOR_RESET}  $*" >&2
}

log_success() {
    echo -e "${COLOR_GREEN}✅${COLOR_RESET} $*" >&2
}

log_warn() {
    echo -e "${COLOR_YELLOW}⚠️${COLOR_RESET}  $*" >&2
}

log_error() {
    echo -e "${COLOR_RED}❌${COLOR_RESET} $*" >&2
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        echo -e "${COLOR_GRAY}🔍${COLOR_RESET} $*" >&2
    fi
}

# ============================================================================
# Security Validation Functions
# ============================================================================

validate_rpc_url() {
    local url="$1"

    # Check if URL is empty
    if [ -z "$url" ]; then
        log_error "RPC URL is empty"
        return 1
    fi

    # Check protocol: Must start with http:// or https://
    if [[ ! "$url" =~ ^http:// ]] && [[ ! "$url" =~ ^https:// ]]; then
        log_error "Invalid RPC URL format: Must start with http:// or https://"
        return 1
    fi

    # Check for shell metacharacters (command injection attempts)
    # Reject URLs containing: ; | & $ ` ( ) \ ' " < > { } [ ]
    local forbidden_chars='[;|&$`()\"\047<>{}]'
    if [[ "$url" =~ $forbidden_chars ]]; then
        log_error "Invalid RPC URL format: Contains prohibited characters"
        log_error "RPC URL must not contain shell metacharacters"
        return 1
    fi

    # Whitelist allowed characters: alphanumeric, colon, slash, dot, question, equals, dash, underscore
    # Using a more conservative approach: check that after protocol, only safe characters are present
    local url_without_protocol="${url#http://}"
    url_without_protocol="${url_without_protocol#https://}"
    local allowed_pattern='^[a-zA-Z0-9:/.\?&=_-]+$'
    if [[ ! "$url_without_protocol" =~ $allowed_pattern ]]; then
        log_error "Invalid RPC URL format: Contains invalid characters"
        log_error "Allowed characters: alphanumeric, :, /, ., ?, &, =, -, _"
        return 1
    fi

    log_debug "RPC URL format validated"
    return 0
}

validate_private_key() {
    local key="$1"

    # Check format (with or without 0x prefix, 64 hex chars)
    if [[ ! "$key" =~ ^(0x)?[0-9a-fA-F]{64}$ ]]; then
        log_error "Invalid private key format"
        log_error "Expected: 64 hexadecimal characters (with optional 0x prefix)"
        return 1
    fi

    log_debug "Private key format validated"
    return 0
}

check_env_security() {
    local env_file="${1:-.env}"

    # Only check if .env file exists
    if [ ! -f "$env_file" ]; then
        log_debug "No .env file found at $env_file, skipping security checks"
        return 0
    fi

    # Check file permissions (should be 600 or 400)
    local perms="unknown"
    local platform_detected=false

    # Detect platform and get permissions
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        perms=$(stat -f %A "$env_file" 2>/dev/null || echo "unknown")
        platform_detected=true
        log_debug "Platform detected: macOS"
    elif [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "linux" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        # Linux, Cygwin, WSL
        perms=$(stat -c %a "$env_file" 2>/dev/null || echo "unknown")
        platform_detected=true
        log_debug "Platform detected: Linux/GNU"
    elif [[ "$OSTYPE" == "freebsd"* ]] || [[ "$OSTYPE" == "openbsd"* ]]; then
        # FreeBSD, OpenBSD
        perms=$(stat -f %Lp "$env_file" 2>/dev/null || echo "unknown")
        platform_detected=true
        log_debug "Platform detected: BSD"
    else
        # Unsupported platform
        log_debug "Platform detected: $OSTYPE (unsupported for automatic check)"
    fi

    # Validate permissions or warn about unsupported platform
    if [ "$perms" = "unknown" ]; then
        if [ "$platform_detected" = false ]; then
            log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_warn "⚠️  Cannot automatically check file permissions on: $OSTYPE"
            log_warn "⚠️  Please manually verify .env file permissions are secure"
            log_warn ""
            log_warn "Manual check:"
            log_warn "  Run: ls -la $env_file"
            log_warn "  Expected: -rw------- (600) or -r-------- (400)"
            log_warn "  Fix with: chmod 600 $env_file"
            log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        else
            log_warn "Failed to read file permissions for $env_file"
            log_warn "Please verify manually: ls -la $env_file"
        fi
    elif [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
        log_warn ".env file has insecure permissions ($perms)"
        log_warn "Recommended: chmod 600 $env_file"
        log_warn "This prevents unauthorized access to your private keys"
    else
        log_debug "File permissions validated: $perms"
    fi

    # Check if .env is gitignored (only if in a git repo)
    if git rev-parse --git-dir > /dev/null 2>&1; then
        if ! git check-ignore -q "$env_file" 2>/dev/null; then
            log_warn ".env file is NOT in .gitignore"
            log_warn "Add '$env_file' to .gitignore to prevent accidental commits"
            log_warn "Run: echo '$env_file' >> .gitignore"
        else
            log_debug "File is properly gitignored"
        fi
    fi

    return 0
}

# ============================================================================
# Address Validation Functions
# ============================================================================

validate_transaction_hash() {
    local tx_hash="$1"
    local label="${2:-Transaction hash}"

    # Check if hash is empty
    if [ -z "$tx_hash" ]; then
        log_error "$label is empty"
        return 1
    fi

    # Check format: 0x followed by exactly 64 hex characters (32 bytes)
    if [[ ! "$tx_hash" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        log_error "$label has invalid format"
        log_error "Expected: 0x followed by 64 hexadecimal characters"
        return 1
    fi

    log_debug "$label format validated: $tx_hash"
    return 0
}

validate_address() {
    local address="$1"
    local label="${2:-Address}"

    # Check if address is empty
    if [ -z "$address" ]; then
        log_error "$label is empty"
        return 1
    fi

    # Check format: 0x followed by 40 hex characters
    if [[ ! "$address" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        log_error "$label has invalid format: $address"
        log_error "Expected: 0x followed by 40 hexadecimal characters"
        return 1
    fi

    log_debug "$label format validated: $address"
    return 0
}

validate_contract_exists() {
    local address="$1"
    local rpc_url="$2"
    local label="${3:-Contract}"

    # First validate address format
    validate_address "$address" "$label" || return 1

    # Check if contract code exists at address
    local code
    code=$(cast code "$address" --rpc-url "$rpc_url" 2>/dev/null || echo "0x")

    if [ "$code" = "0x" ] || [ -z "$code" ]; then
        log_error "$label at $address has no code deployed"
        log_error "This address is either an EOA or contract not yet deployed"
        return 1
    fi

    log_debug "$label verified on-chain: $address"
    return 0
}

# ============================================================================
# Gas Price Estimation
# ============================================================================

is_mainnet_rpc() {
    local rpc_url="$1"

    # Detect mainnet by URL pattern
    if [[ "$rpc_url" =~ evm\.mantrachain\.io ]] || [[ "$rpc_url" =~ mainnet ]]; then
        log_debug "Mainnet detected by URL pattern"
        return 0
    fi

    # Try to detect by chain ID (if RPC is accessible)
    # Chain ID 5888 = MANTRA mainnet, 5887 = MANTRA DuKong testnet
    local chain_id
    if chain_id=$(cast chain-id --rpc-url "$rpc_url" 2>/dev/null); then
        if [ "$chain_id" = "5888" ]; then
            log_debug "Mainnet detected by chain ID: $chain_id"
            return 0
        fi
        log_debug "Testnet detected by chain ID: $chain_id"
        return 1
    fi

    # Default to testnet if cannot determine
    log_debug "Could not determine network type, assuming testnet"
    return 1
}

estimate_gas_price() {
    local rpc_url="$1"

    # If GAS_PRICE is manually set, use it (skip estimation)
    if [ -n "${GAS_PRICE:-}" ]; then
        log_debug "Using manually set gas price: $GAS_PRICE wei"
        echo "$GAS_PRICE"
        return 0
    fi

    # Detect if this is mainnet
    local is_mainnet=0
    if is_mainnet_rpc "$rpc_url"; then
        is_mainnet=1
        log_debug "Network type: Mainnet (strict gas price mode enabled)"
    else
        log_debug "Network type: Testnet (fallback mode allowed)"
    fi

    # Query network gas price
    local estimated_price
    if estimated_price=$(cast gas-price --rpc-url "$rpc_url" 2>/dev/null); then
        log_debug "Network gas price: $estimated_price wei"

        # Apply bounds
        if [ "$estimated_price" -lt "$GAS_PRICE_MIN" ]; then
            log_debug "Gas price below minimum, using minimum: $GAS_PRICE_MIN wei"
            echo "$GAS_PRICE_MIN"
        elif [ "$estimated_price" -gt "$GAS_PRICE_MAX" ]; then
            log_warn "Gas price above maximum ($estimated_price wei), capping at $GAS_PRICE_MAX wei"
            echo "$GAS_PRICE_MAX"
        else
            echo "$estimated_price"
        fi
    else
        # Gas estimation failed
        if [ "$is_mainnet" = "1" ] || [ "${MAINNET_STRICT:-0}" = "1" ]; then
            # MAINNET: Fail fast, don't use default
            log_error "Failed to estimate gas price on mainnet"
            log_error "This may indicate RPC issues or network problems"
            log_error "Refusing to use default gas price on mainnet for safety"
            log_error ""
            log_error "Solutions:"
            log_error "  1. Check RPC endpoint connectivity: cast block latest --rpc-url \$RPC_URL"
            log_error "  2. Set gas price manually: export GAS_PRICE=50000000000"
            log_error "  3. Try a different RPC endpoint"
            return 1
        else
            # TESTNET: Allow fallback with prominent warning
            log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_warn "⚠️  Failed to estimate gas price, using default: $GAS_PRICE_DEFAULT wei"
            log_warn "⚠️  This is allowed on testnet but may cause transaction failures"
            log_warn "⚠️  Consider setting GAS_PRICE manually for production use"
            log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "$GAS_PRICE_DEFAULT"
        fi
    fi
}

# ============================================================================
# Transaction Confirmation Functions
# ============================================================================

normalize_tx_status() {
    local status="$1"

    # Check if status is empty or null
    if [ -z "$status" ] || [ "$status" = "null" ]; then
        log_error "Transaction status is empty or null"
        return 1
    fi

    # Normalize to decimal integer
    # Bash arithmetic expansion handles both hex (0x1) and decimal (1) formats
    local normalized
    if [[ "$status" =~ ^0x[0-9a-fA-F]+$ ]]; then
        # Hex format: 0x1 or 0x0
        normalized=$((status))
    elif [[ "$status" =~ ^[0-9]+$ ]]; then
        # Decimal format: 1 or 0
        normalized=$status
    else
        log_error "Invalid transaction status format: $status"
        return 1
    fi

    # Status must be exactly 0 (failure) or 1 (success)
    if [ "$normalized" != "0" ] && [ "$normalized" != "1" ]; then
        log_error "Transaction status out of range: $normalized (expected 0 or 1)"
        return 1
    fi

    log_debug "Status normalized: '$status' → $normalized"
    echo "$normalized"
    return 0
}

wait_for_tx() {
    local tx_hash="$1"
    local rpc_url="$2"
    local timeout="${3:-$TX_CONFIRMATION_TIMEOUT}"
    local label="${4:-Transaction}"

    # Enhanced validation is controlled by environment variables:
    # - TX_VALIDATE_GAS: Enable gas usage validation (default: "1" = enabled)
    # - TX_VALIDATE_CONFIRMATIONS: Required block confirmations (default: "1" = single block)
    #
    # These features are opt-in and non-blocking (warnings only, don't prevent success)

    # Validate transaction hash format before polling
    validate_transaction_hash "$tx_hash" "Transaction hash" || return 1

    # Validate timeout is a positive integer
    if ! [[ "$timeout" =~ ^[0-9]+$ ]] || [ "$timeout" -le 0 ]; then
        log_error "Invalid timeout value: $timeout (must be positive integer)"
        return 1
    fi

    log_debug "Waiting for $label confirmation: $tx_hash"

    local elapsed=0
    local interval=2
    local max_interval=10

    while [ $elapsed -lt $timeout ]; do
        # Try to get receipt
        local receipt
        if receipt=$(cast receipt "$tx_hash" --rpc-url "$rpc_url" --json 2>/dev/null); then
            # Check transaction status
            local status
            status=$(echo "$receipt" | jq -r '.status // empty')

            if [ -z "$status" ]; then
                log_error "$label receipt missing status field"
                return 1
            fi

            # Normalize status to handle different RPC provider formats
            local normalized_status
            if ! normalized_status=$(normalize_tx_status "$status"); then
                log_error "$label has invalid status"
                return 1
            fi

            if [ "$normalized_status" = "1" ]; then
                log_debug "$label confirmed successfully (${elapsed}s)"

                # Enhanced validation: Gas usage validation (opt-in, non-blocking)
                local validate_gas="${TX_VALIDATE_GAS:-1}"
                if [ "$validate_gas" != "0" ]; then
                    local gas_used
                    gas_used=$(echo "$receipt" | jq -r '.gasUsed // empty')
                    if [ -n "$gas_used" ] && [ "$gas_used" != "null" ]; then
                        # Validation errors are logged but don't prevent success
                        validate_gas_usage "$gas_used" || log_debug "Gas validation encountered an issue (non-blocking)"
                    fi
                fi

                # Enhanced validation: Block confirmation depth (opt-in, may fail)
                local required_confirmations="${TX_VALIDATE_CONFIRMATIONS:-1}"
                if [ "$required_confirmations" -gt 1 ]; then
                    log_debug "Waiting for $required_confirmations confirmations..."
                    if ! receipt=$(wait_for_confirmations "$tx_hash" "$rpc_url" "$required_confirmations" "$timeout" "$label"); then
                        log_error "Failed to achieve required confirmations"
                        return 1
                    fi
                fi

                echo "$receipt"
                return 0
            else
                # Transaction failed (status = 0)
                log_error "$label failed on-chain"

                # Try to extract revert reason
                local revert_reason
                revert_reason=$(echo "$receipt" | jq -r '.revertReason // empty')
                if [ -n "$revert_reason" ]; then
                    log_error "Revert reason: $revert_reason"
                fi

                return 1
            fi
        fi

        # Not yet mined, wait with exponential backoff
        sleep $interval
        elapsed=$((elapsed + interval))

        # Increase interval up to max
        if [ $interval -lt $max_interval ]; then
            interval=$((interval + 2))
            if [ $interval -gt $max_interval ]; then
                interval=$max_interval
            fi
        fi

        log_debug "Waiting for confirmation... ${elapsed}s"
    done

    # Timeout reached
    log_error "$label confirmation timeout after ${timeout}s"
    log_error "Transaction may still be pending: $tx_hash"
    return 1
}

# ============================================================================
# Enhanced Transaction Validation Functions
# ============================================================================

validate_gas_usage() {
    local gas_used="$1"
    local max_threshold="${2:-10000000}"  # Default: 10M gas

    # Validate gas_used parameter is provided
    if [ -z "$gas_used" ]; then
        log_error "gas_used parameter is required"
        return 1
    fi

    # Convert gas_used to decimal if in hex format
    local gas_decimal
    if [[ "$gas_used" =~ ^0x[0-9a-fA-F]+$ ]]; then
        gas_decimal=$((gas_used))
    elif [[ "$gas_used" =~ ^[0-9]+$ ]]; then
        gas_decimal=$gas_used
    else
        log_error "Invalid gas format: $gas_used (expected decimal or hex)"
        return 0  # Non-blocking: return success even on validation error
    fi

    # Format gas in human-readable form (K/M suffix)
    local gas_formatted
    if [ "$gas_decimal" -ge 1000000 ]; then
        gas_formatted=$(echo "scale=1; $gas_decimal / 1000000" | bc)"M"
    elif [ "$gas_decimal" -ge 1000 ]; then
        gas_formatted=$(echo "scale=1; $gas_decimal / 1000" | bc)"K"
    else
        gas_formatted="$gas_decimal"
    fi

    # Log gas usage
    log_info "Gas used: ${gas_formatted} (${gas_decimal} gas)"

    # Check if gas exceeds threshold (warning only, non-blocking)
    if [ "$gas_decimal" -gt "$max_threshold" ]; then
        log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_warn "⚠️  Gas usage (${gas_formatted}) exceeds threshold ($(echo "scale=1; $max_threshold / 1000000" | bc)M)"
        log_warn "⚠️  This may indicate inefficient code or unexpected behavior"
        log_warn "⚠️  Consider reviewing the transaction for optimization opportunities"
        log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi

    # Always return success (non-blocking validation)
    return 0
}

wait_for_confirmations() {
    local tx_hash="$1"
    local rpc_url="$2"
    local required_confirmations="${3:-1}"
    local timeout="${4:-300}"  # Default: 5 minutes
    local label="${5:-Transaction}"

    # Validate transaction hash format
    validate_transaction_hash "$tx_hash" "Transaction hash" || return 1

    # Validate required_confirmations is a positive integer
    if ! [[ "$required_confirmations" =~ ^[0-9]+$ ]] || [ "$required_confirmations" -le 0 ]; then
        log_error "Invalid confirmations value: $required_confirmations (must be positive integer)"
        return 1
    fi

    log_debug "Waiting for $required_confirmations confirmation(s) for $label: $tx_hash"

    # First, wait for transaction to be mined
    local receipt
    if ! receipt=$(cast receipt "$tx_hash" --rpc-url "$rpc_url" --json 2>/dev/null); then
        log_error "$label not yet mined, waiting..."

        # Poll for initial receipt
        local elapsed=0
        local interval=2
        while [ $elapsed -lt $timeout ]; do
            if receipt=$(cast receipt "$tx_hash" --rpc-url "$rpc_url" --json 2>/dev/null); then
                break
            fi
            sleep $interval
            elapsed=$((elapsed + interval))
        done

        if [ $elapsed -ge $timeout ]; then
            log_error "$label not mined within timeout: ${timeout}s"
            return 1
        fi
    fi

    # Extract transaction block number
    local tx_block
    tx_block=$(echo "$receipt" | jq -r '.blockNumber // empty')

    if [ -z "$tx_block" ]; then
        log_error "Failed to extract block number from receipt"
        return 1
    fi

    # Convert to decimal if hex
    if [[ "$tx_block" =~ ^0x[0-9a-fA-F]+$ ]]; then
        tx_block=$((tx_block))
    fi

    log_debug "$label mined in block: $tx_block"

    # If only 1 confirmation required, we're done
    if [ "$required_confirmations" -eq 1 ]; then
        log_debug "$label has 1 confirmation"
        echo "$receipt"
        return 0
    fi

    # Poll for additional confirmations
    local elapsed=0
    local interval=2
    local max_interval=10

    while [ $elapsed -lt $timeout ]; do
        # Get current block height
        local current_block
        if ! current_block=$(cast block-number --rpc-url "$rpc_url" 2>/dev/null); then
            log_debug "Failed to query current block, retrying..."
            sleep $interval
            elapsed=$((elapsed + interval))
            continue
        fi

        # Calculate confirmations: current_block - tx_block + 1
        local confirmations=$((current_block - tx_block + 1))

        log_debug "Waiting for confirmations... ($confirmations/$required_confirmations)"

        # Check if we have enough confirmations
        if [ "$confirmations" -ge "$required_confirmations" ]; then
            log_debug "$label confirmed with $confirmations confirmations"
            echo "$receipt"
            return 0
        fi

        # Wait with exponential backoff
        sleep $interval
        elapsed=$((elapsed + interval))

        # Increase interval up to max
        if [ $interval -lt $max_interval ]; then
            interval=$((interval + 2))
            if [ $interval -gt $max_interval ]; then
                interval=$max_interval
            fi
        fi
    done

    # Timeout reached
    log_error "$label confirmation timeout after ${timeout}s"
    log_error "Only $confirmations of $required_confirmations confirmations received"
    return 1
}

log_tx_summary() {
    local receipt="$1"
    local description="${2:-Transaction}"
    local explorer_base="${3:-}"  # Optional: explorer base URL (e.g., "https://mantrascan.io/dukong/tx")

    # Validate receipt is not empty
    if [ -z "$receipt" ]; then
        log_error "Receipt is empty, cannot generate summary"
        return 1
    fi

    # Parse receipt fields with defaults for missing values
    local tx_hash
    tx_hash=$(echo "$receipt" | jq -r '.transactionHash // empty')
    if [ -z "$tx_hash" ]; then
        log_warn "Transaction hash missing from receipt"
        tx_hash="unknown"
    fi

    local block_number
    block_number=$(echo "$receipt" | jq -r '.blockNumber // empty')
    if [ -z "$block_number" ] || [ "$block_number" = "null" ]; then
        block_number="unknown"
    elif [[ "$block_number" =~ ^0x[0-9a-fA-F]+$ ]]; then
        # Convert hex to decimal for readability
        block_number=$((block_number))
    fi

    local gas_used
    gas_used=$(echo "$receipt" | jq -r '.gasUsed // empty')
    if [ -z "$gas_used" ] || [ "$gas_used" = "null" ]; then
        gas_used="unknown"
    else
        # Convert to decimal and format
        local gas_decimal
        if [[ "$gas_used" =~ ^0x[0-9a-fA-F]+$ ]]; then
            gas_decimal=$((gas_used))
        else
            gas_decimal=$gas_used
        fi

        # Format with K/M suffix
        if [ "$gas_decimal" != "unknown" ] && [ "$gas_decimal" -ge 1000000 ]; then
            gas_used="$(echo "scale=2; $gas_decimal / 1000000" | bc)M (${gas_decimal})"
        elif [ "$gas_decimal" != "unknown" ] && [ "$gas_decimal" -ge 1000 ]; then
            gas_used="$(echo "scale=2; $gas_decimal / 1000" | bc)K (${gas_decimal})"
        else
            gas_used="$gas_decimal"
        fi
    fi

    local status
    status=$(echo "$receipt" | jq -r '.status // empty')
    local status_symbol="❓"
    if [ -n "$status" ] && [ "$status" != "null" ]; then
        local normalized_status
        if [[ "$status" =~ ^0x[0-9a-fA-F]+$ ]]; then
            normalized_status=$((status))
        else
            normalized_status=$status
        fi

        if [ "$normalized_status" = "1" ]; then
            status_symbol="✅"
        elif [ "$normalized_status" = "0" ]; then
            status_symbol="❌"
        fi
    fi

    local event_count
    event_count=$(echo "$receipt" | jq -r '.logs | length' 2>/dev/null || echo "0")

    # Display formatted summary
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "📋 Transaction Summary: $description"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Status:       $status_symbol"
    log_info "TX Hash:      $tx_hash"
    log_info "Block:        $block_number"
    log_info "Gas Used:     $gas_used"
    log_info "Events:       $event_count"

    # Add explorer link if provided
    if [ -n "$explorer_base" ] && [ "$tx_hash" != "unknown" ]; then
        log_info "Explorer:     $explorer_base/$tx_hash"
    fi

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

send_tx() {
    local description="$1"
    shift
    local cast_args=("$@")

    log_debug "Sending transaction: $description"
    log_debug "Command: cast send ${cast_args[*]}"

    # Execute transaction
    local tx_output
    if ! tx_output=$(cast send "${cast_args[@]}" 2>&1); then
        log_error "Failed to send transaction: $description"
        log_error "Error: $tx_output"
        return 1
    fi

    # Parse transaction hash from output
    # Priority 1: Try JSON parsing (most reliable)
    local tx_hash
    tx_hash=$(echo "$tx_output" | jq -r '.transactionHash // empty' 2>/dev/null || echo "")

    if [ -z "$tx_hash" ]; then
        # Priority 2: Try regex fallback with context awareness
        # Only extract if output looks like a transaction confirmation
        if echo "$tx_output" | grep -qi "transaction\|hash\|tx"; then
            tx_hash=$(echo "$tx_output" | grep -oE '0x[0-9a-fA-F]{64}' | head -1 || echo "")
        fi
    fi

    if [ -z "$tx_hash" ]; then
        log_error "Failed to extract transaction hash from output"
        log_error "This may indicate the transaction was not broadcast"
        return 1
    fi

    # Validate extracted hash format (security: prevent accidental extraction of private keys)
    if ! validate_transaction_hash "$tx_hash" "Extracted transaction hash"; then
        log_error "Extracted value is not a valid transaction hash"
        log_error "This may indicate parsing error or malformed output"
        return 1
    fi

    log_debug "Transaction hash: $tx_hash"
    echo "$tx_hash"
    return 0
}

send_and_wait() {
    local description="$1"
    local rpc_url="$2"
    shift 2
    local cast_args=("$@")

    # Send transaction
    local tx_hash
    if ! tx_hash=$(send_tx "$description" "${cast_args[@]}"); then
        return 1
    fi

    # Wait for confirmation
    local receipt
    if ! receipt=$(wait_for_tx "$tx_hash" "$rpc_url" "$TX_CONFIRMATION_TIMEOUT" "$description"); then
        return 1
    fi

    # Extract key fields for caller
    local contract_address
    contract_address=$(echo "$receipt" | jq -r '.contractAddress // empty')

    # Return both hash and address in JSON format
    jq -n \
        --arg hash "$tx_hash" \
        --arg address "$contract_address" \
        '{transactionHash: $hash, contractAddress: $address}'

    return 0
}

# ============================================================================
# Environment Variable Validation
# ============================================================================

require_env_var() {
    local var_name="$1"
    local var_value="${!var_name:-}"

    if [ -z "$var_value" ]; then
        log_error "Required environment variable not set: $var_name"
        log_error "Set $var_name in your .env file or environment"
        return 1
    fi

    log_debug "Environment variable validated: $var_name"
    return 0
}

setup_environment() {
    log_debug "Setting up environment and validating configuration"

    # SECURITY FIRST: Check .env file security BEFORE processing any secrets
    # This ensures warnings about insecure permissions are shown before
    # any sensitive data (like private keys) could be exposed in error messages
    check_env_security ".env"

    # Check required environment variables exist
    require_env_var "RPC_URL" || return 1
    require_env_var "PRIVATE_KEY" || return 1

    # Validate RPC URL format to prevent command injection
    # This must happen BEFORE using RPC_URL in any shell command
    validate_rpc_url "$RPC_URL" || return 1

    # Validate private key format (after security checks)
    validate_private_key "$PRIVATE_KEY" || return 1

    # Test RPC connectivity (now safe - URL has been validated)
    log_debug "Testing RPC connectivity: $RPC_URL"
    if ! cast block latest --rpc-url "$RPC_URL" > /dev/null 2>&1; then
        log_error "Failed to connect to RPC endpoint: $RPC_URL"
        log_error "Check that the RPC URL is correct and accessible"
        return 1
    fi
    log_debug "RPC connection successful"

    return 0
}

# ============================================================================
# Timing Helpers
# ============================================================================

get_block_timestamp() {
    local rpc_url="$1"

    local block_data
    if ! block_data=$(cast block latest --json --rpc-url "$rpc_url" 2>/dev/null); then
        log_error "Failed to fetch latest block"
        return 1
    fi

    local timestamp
    timestamp=$(echo "$block_data" | jq -r '.timestamp // empty')

    if [ -z "$timestamp" ] || [ "$timestamp" = "null" ]; then
        log_error "Failed to parse block timestamp (empty or null)"
        return 1
    fi

    # Validate and convert timestamp format
    local decimal_timestamp
    if [[ "$timestamp" =~ ^0x[0-9a-fA-F]+$ ]]; then
        # Hex format: validate and convert
        decimal_timestamp=$((timestamp))
    elif [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        # Decimal format: use directly
        decimal_timestamp=$timestamp
    else
        log_error "Invalid block timestamp format: $timestamp"
        log_error "Expected hex (0x...) or decimal integer"
        return 1
    fi

    # Validate timestamp is within reasonable bounds
    if [ "$decimal_timestamp" -lt "$TIMESTAMP_MIN" ]; then
        log_error "Block timestamp out of range: $decimal_timestamp"
        log_error "Timestamp is before minimum ($TIMESTAMP_MIN)"
        log_error "This may indicate RPC data corruption or clock skew"
        return 1
    fi

    if [ "$decimal_timestamp" -gt "$TIMESTAMP_MAX" ]; then
        log_error "Block timestamp out of range: $decimal_timestamp"
        log_error "Timestamp is after maximum ($TIMESTAMP_MAX)"
        log_error "This may indicate RPC data corruption or clock skew"
        return 1
    fi

    log_debug "Block timestamp validated: $decimal_timestamp"
    echo "$decimal_timestamp"
}

calculate_campaign_start_time() {
    local rpc_url="$1"
    local buffer="${2:-$CAMPAIGN_START_BUFFER}"

    # Validate buffer is a positive integer
    if ! [[ "$buffer" =~ ^[0-9]+$ ]] || [ "$buffer" -le 0 ]; then
        log_error "Invalid campaign start buffer: $buffer"
        log_error "Buffer must be a positive integer (seconds)"
        return 1
    fi

    local current_block_time
    current_block_time=$(get_block_timestamp "$rpc_url") || return 1

    local start_time=$((current_block_time + buffer))

    log_debug "Campaign timing: block_time=$current_block_time, buffer=${buffer}s, start=$start_time"

    echo "$start_time"
}

# ============================================================================
# Utility Functions
# ============================================================================

parse_json_field() {
    local json="$1"
    local field="$2"
    local label="${3:-Field}"

    local value
    value=$(echo "$json" | jq -r ".$field // empty")

    if [ -z "$value" ] || [ "$value" = "null" ]; then
        log_error "Failed to parse $label from JSON (field: $field)"
        return 1
    fi

    echo "$value"
}

# ============================================================================
# Initialization
# ============================================================================

log_debug "Common library loaded successfully"
