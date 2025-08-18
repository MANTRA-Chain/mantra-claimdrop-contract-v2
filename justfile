# Prints the list of recipes.
default:
    @just --list

# Builds the contract.
build:
    cargo build

# Generates JSON schemas for messages.
schemas:
    cargo schema

# Tests the contract.
test:
    cargo test

# Tests the contract without stopping on first failure.
test-all:
    cargo test --no-fail-fast

# Alias to the format recipe.
fmt:
    @just format

# Formats the rust code.
format:
    cargo fmt --all

# Checks code formatting (CI mode).
format-check:
    cargo fmt --all -- --check

# Runs clippy linter.
lint:
    cargo clippy

# Runs clippy with warnings as errors.
lint-strict:
    cargo clippy -- -D warnings

# Tries to fix clippy issues automatically.
lintfix:
    cargo clippy --fix --allow-staged --allow-dirty
    just format

# Cargo check.
check:
    cargo check

# Cargo clean and update.
refresh:
    cargo clean && cargo update

# Compiles and optimizes the contract using Docker.
optimize:
    #!/usr/bin/env bash
    set -euo pipefail
    docker run --rm -v "$(pwd)":/code \
      --mount type=volume,source="$(basename "$(pwd)")_cache",target=/target \
      --mount type=volume,source=registry_cache,target=/usr/local/cargo/registry \
      cosmwasm/optimizer-arm64:0.16.0

# Stores the claimdrop contract on the given CHAIN, default is mantra-dukong.
store CHAIN='mantra-dukong-1':
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "artifacts/claimdrop_contract.wasm" ]; then
        echo "Error: Optimized contract not found. Run 'just optimize' first."
        exit 1
    fi
    echo "Storing claimdrop contract on {{CHAIN}}..."
    
    # Check if mantrachaind is available
    if ! command -v mantrachaind &> /dev/null; then
        echo "Error: mantrachaind not found. Please install mantrachaind or set up your environment."
        echo "You can manually store with:"
        echo "mantrachaind tx wasm store artifacts/claimdrop_contract.wasm --from <wallet> --chain-id {{CHAIN}} --gas auto --gas-adjustment 1.3 --output json"
        exit 1
    fi
    
    # Store the contract and extract code ID
    echo "Executing store transaction..."
    RESULT=$(mantrachaind tx wasm store artifacts/claimdrop_contract.wasm --from admin --chain-id {{CHAIN}} --gas auto --gas-adjustment 1.3 --gas-prices 0.01uom --output json --yes)
    
    if [ $? -eq 0 ]; then
        echo "Transaction successful!"
        echo "$RESULT"
        # Try to extract code_id from the transaction result
        CODE_ID=$(echo "$RESULT" | jq -r '.logs[0].events[] | select(.type=="store_code") | .attributes[] | select(.key=="code_id") | .value' 2>/dev/null)
        if [ "$CODE_ID" != "" ] && [ "$CODE_ID" != "null" ]; then
            echo ""
            echo "🎉 Contract stored successfully!"
            echo "📋 Code ID: $CODE_ID"
            echo ""
            echo "Next steps:"
            echo "  just deploy {{CHAIN}} $CODE_ID"
        else
            echo "Contract stored but could not extract code ID. Check the transaction result above."
        fi
    else
        echo "Transaction failed. Check your wallet, chain connection, and gas settings."
        exit 1
    fi

# Deploys the claimdrop contract on the given CHAIN with CODE_ID, default is mantra-dukong.
deploy CHAIN='mantra-dukong-1' CODE_ID='':
    #!/usr/bin/env bash
    set -euo pipefail
    
    if [ -z "{{CODE_ID}}" ]; then
        echo "Error: CODE_ID is required"
        echo "Usage: just deploy <chain> <code_id>"
        echo "Example: just deploy mantra-dukong-1 123"
        exit 1
    fi
    
    echo "Deploying claimdrop contract on {{CHAIN}} with code ID {{CODE_ID}}..."
    
    # Check if mantrachaind is available
    if ! command -v mantrachaind &> /dev/null; then
        echo "Error: mantrachaind not found. Please install mantrachaind or set up your environment."
        echo "You can manually deploy with:"
        echo "mantrachaind tx wasm instantiate {{CODE_ID}} '{}' --from <wallet> --label 'Claimdrop V2' --chain-id {{CHAIN}} --gas auto --gas-adjustment 1.3 --output json"
        exit 1
    fi
    
    # Default instantiate message (empty campaign)
    INIT_MSG='{}'
    
    echo "Instantiating contract with message: $INIT_MSG"
    RESULT=$(mantrachaind tx wasm instantiate {{CODE_ID}} "$INIT_MSG" --from admin --label "Claimdrop V2" --chain-id {{CHAIN}} --gas auto --gas-adjustment 1.3 --gas-prices 0.01uom --output json --yes)
    
    if [ $? -eq 0 ]; then
        echo "Transaction successful!"
        echo "$RESULT"
        # Try to extract contract address from the transaction result
        CONTRACT_ADDR=$(echo "$RESULT" | jq -r '.logs[0].events[] | select(.type=="instantiate") | .attributes[] | select(.key=="_contract_address") | .value' 2>/dev/null)
        if [ "$CONTRACT_ADDR" != "" ] && [ "$CONTRACT_ADDR" != "null" ]; then
            echo ""
            echo "🎉 Contract deployed successfully!"
            echo "📋 Contract Address: $CONTRACT_ADDR"
            echo ""
        else
            echo "Contract deployed but could not extract address. Check the transaction result above."
        fi
    else
        echo "Transaction failed. Check your wallet, chain connection, and gas settings."
        exit 1
    fi

# Runs emergency script to close campaign (requires Node.js).
emergency-close-campaign:
    node scripts/emergency/close_campaign.js

# Runs emergency script to retrieve unclaimed tokens (requires Node.js).
emergency-retrieve-tokens:
    node scripts/emergency/retrieve_tokens.js

# Full CI pipeline: format check, lint strict, and test.
ci:
    just format-check
    just lint-strict
    just test-all
