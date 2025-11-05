# Emergency Scripts

This directory contains scripts designed for emergency situations to manage and control aspects of MANTRA Chain contracts. These scripts are powerful and should be used with extreme caution by authorized personnel only.

**WARNING: EXECUTING THESE SCRIPTS CAN HAVE SIGNIFICANT AND POTENTIALLY IRREVERSIBLE CONSEQUENCES. ALWAYS DOUBLE-CHECK PARAMETERS AND FULLY UNDERSTAND THE SCRIPT'S ACTIONS BEFORE EXECUTION.**

## Table of Contents

1.  [Prerequisites](#prerequisites)
2.  [Available Scripts](#available-scripts)
    *   [Close Claimdrop Campaign](#close-claimdrop-campaign)
3.  [General Usage](#general-usage)
4.  [Safety Guidelines](#safety-guidelines)
5.  [Troubleshooting](#troubleshooting)

## 1. Prerequisites

### 1.1 Software & Environment
*   **Node.js**: Version 18.x or higher. Required to run the JavaScript files. Download from [nodejs.org](https://nodejs.org/).
*   **npm/yarn**: For installing Node.js dependencies.
*   **Ledger Hardware Wallet**: With the MANTRA app (or Cosmos app if MANTRA app not available/applicable) installed and updated.
*   **Operating System**: Linux, macOS, or Windows (Node.js is cross-platform).

### 1.2 Dependencies
It's recommended to create a `package.json` in this `scripts/emergency/` directory to manage dependencies for these scripts.
If you don't have one, you can create it by running `npm init -y` inside `scripts/emergency/`.

Then, install the required Node.js dependencies:
```bash
# Navigate to scripts/emergency if you are not already there
# cd scripts/emergency

npm install @cosmjs/cosmwasm-stargate @cosmjs/ledger-amino @cosmjs/amino @ledgerhq/hw-transport-node-hid @cosmjs/stargate @cosmjs/encoding readline secp256k1
```
Ensure `secp256k1` can be built, which might require build tools like `python`, `make`, `g++` depending on your OS. The `readline` module is used for confirmation prompts. The `@cosmjs/encoding` module is used for `toUtf8`.

### 1.3 Ledger Setup
*   Connect your Ledger device and unlock it.
*   Open the MANTRA app (or Cosmos app) on the Ledger.
*   Ensure the Ledger firmware and app are up to date.

## 2. Available Scripts

### 2.1 Close Claimdrop Campaign

**Script File:**
*   `close_claimdrop_campaign.js` (Node.js script)

**Purpose:**
This script identifies claimdrop contracts instantiated from a specific `CODE_ID` and prepares a single batch transaction to close eligible campaigns. This is an emergency measure to halt claimdrop activities.

**Action:**
For each contract found associated with the given `CODE_ID`, the script performs the following checks:
1.  **Verifies an active and open campaign**: It queries the contract. If no campaign state is found, or if the campaign has a `closed` timestamp indicating it's already closed, the contract is skipped.
2.  **Verifies ownership**: If an active and open campaign exists, it then queries the contract's ownership.
3.  **Prepares `CloseCampaign` message**: If the connected Ledger account (`senderAddress`) is the owner of the contract, a `MsgExecuteContract` message (with `CloseCampaign` action) is prepared for this contract and added to a batch.

All prepared messages are then batched into a **single transaction**. You will be prompted for confirmation before this single transaction is broadcast and will need to approve it **once** on your Ledger device.

**Execution:**
The script is configured using command-line arguments.

```bash
node scripts/emergency/close_claimdrop_campaign.js <rpc_endpoint> <code_id> [account_index]
```

**Arguments:**

*   `<rpc_endpoint>`: (Required) RPC endpoint of the target chain (e.g., `"http://localhost:26657"` or `"https://rpc.mantrachain.io"`).
*   `<code_id>`: (Required) The numeric Code ID of the claimdrop contracts to target (e.g., `123`).
*   `[account_index]`: (Optional) The account index for the Ledger HD path (`m/44'/118'/0'/0/X`). Defaults to `0` if not provided.

**Hardcoded Values in Script:**
*   `LEDGER_ACCOUNT_PREFIX`: "mantra"
*   `GAS_PRICE_STRING`: "0.025uom"
*   `GAS_PER_MESSAGE`: Estimated gas for a single close operation (default: `300000`). Total gas is calculated based on this and the number of messages in the batch.

**Example Usage:**
```bash
# Using default Ledger account index 0, with code_id 1
node scripts/emergency/close_claimdrop_campaign.js "http://localhost:26657" 1

# Using Ledger account index 5, with code_id 456
node scripts/emergency/close_claimdrop_campaign.js "https://rpc.mantrachain.io" 456 5
```

**Execution Flow:**
1.  Run the Node.js script with the required command-line arguments.
2.  The script displays its configuration and a critical warning, including the conditions for action (active, open campaign, and ownership).
3.  You will be prompted for an initial confirmation to proceed with data gathering and message preparation.
4.  The script connects to the Ledger and retrieves the sender address.
5.  It queries for all contract addresses instantiated from the given `CODE_ID`.
6.  For each contract address found:
    a.  It queries the contract to check for an active campaign and ensures it's not already marked as `closed`.
    b.  If an active and open campaign is found, it queries for the contract's owner.
    c.  If the sender address from the Ledger matches the contract owner, it prepares a `MsgExecuteContract` to close the campaign and adds it to a batch of messages.
7.  After processing all contracts, a summary of messages prepared for batching is displayed.
8.  If there are messages to broadcast, you will be prompted again for a **final confirmation** to sign and send the single batch transaction.
9.  If confirmed, the script broadcasts all prepared messages as a single transaction.
10. You must approve this **single transaction** on your Ledger device.
11. The overall result of the broadcasted batch transaction (success or failure) is logged.
12. A final summary of actions is provided.

## 3. General Usage

1.  **Navigate to the Project Root:** Open your terminal in the root directory of the `mantra-contracts-claimdrop` repository.
2.  **Install Dependencies:** If you haven't already, navigate to `scripts/emergency` and install the Node.js dependencies (see [Prerequisites](#12-dependencies)).
    ```bash
    cd scripts/emergency
    npm install
    # cd ../.. # Go back to project root if needed
    ```
3.  **Connect Ledger:** Ensure your Ledger device is connected, unlocked, and the MANTRA (or Cosmos) app is open.
4.  **Execute the Script:**
    ```bash
    node scripts/emergency/close_claimdrop_campaign.js "<your_rpc_url>" <target_code_id> [ledger_account_index]
    ```
    (Modify with actual values).
5.  **Follow Prompts:** The script will guide you through confirmation steps on the terminal and your Ledger device. Read all prompts carefully.
6.  **Monitor Output:** Check the console output for success or error messages. Verify actions on-chain using a block explorer if necessary.

## 4. Safety Guidelines

*   **AUTHORIZED PERSONNEL ONLY:** This script should only be run by individuals who fully understand the smart contracts and the implications of these emergency actions.
*   **TESTNET FIRST:** Always test this script thoroughly on a testnet environment that mirrors mainnet conditions as closely as possible before ever considering its use on mainnet.
*   **VERIFY PARAMETERS:** Triple-check all command-line arguments (`<rpc_endpoint>`, `<code_id>`, `[account_index]`) before execution.
*   **SECURE ENVIRONMENT:** Run this script from a secure, trusted machine.
*   **LEDGER CONFIRMATION:** Pay close attention to the details displayed on your Ledger device screen before approving the **single batch transaction**.
*   **UNDERSTAND THE CODE:** Review the Node.js script code to understand its full logic, especially the conditions for action and the batching mechanism.
*   **COMMUNICATION:** If operating as part of a team, communicate clearly before, during, and after script execution.

## 5. Troubleshooting

*   **Ledger Connection Issues:**
    *   Ensure Ledger is unlocked, MANTRA/Cosmos app is open.
    *   Try reconnecting. Check for conflicting apps (e.g., Ledger Live).
    *   Update Ledger firmware and app.
*   **Node.js Script Errors:**
    *   `Usage: node scripts/emergency/...`: Missing or incorrect command-line arguments.
    *   `Error: <code_id> must be an integer.`: Ensure the code ID is a valid number.
    *   `cannot find module '@cosmjs/...'` or other modules: Run `npm install` in `scripts/emergency/`. Ensure all dependencies like `@cosmjs/encoding` are listed and installed.
    *   Verify RPC endpoint is correct and accessible.
*   **Transaction Failures (Batch Transaction):**
    *   `Out of gas`: The script uses a `GAS_PER_MESSAGE` constant (default `300000`) to estimate the total gas for the batch. If the batch transaction fails with "out of gas," you may need to increase this constant in the script, or the chain's gas limit for a single transaction might be too low for a very large batch. The `GAS_PRICE_STRING` is hardcoded to "0.025uom".
    *   `Account sequence mismatch`: Less likely with a single batch transaction, but possible if other transactions are sent from the same account concurrently.
    *   `Signature verification failed` / `Denied by user?`: Ensure correct Ledger operation for the single batch approval.
    *   Contract-specific errors / Batch Rejection: If the **entire batch transaction fails**, the chain's raw log (if provided in the error) might indicate which message within the batch caused the issue (e.g., one campaign was unexpectedly already closed by another party between script preparation and execution, or a contract had an unexpected state). The script attempts to pre-filter, but race conditions are possible.
*   **General Troubleshooting:**
    *   Ensure the `account_index` corresponds to an initialized account on your Ledger with sufficient funds for the transaction fee.
    *   Confirm the `CODE_ID` is correct.
    *   If contracts are skipped with "No active/open campaign found," verify campaigns are indeed active, open, and queryable.
    *   If contracts are skipped with "Campaign already closed," this is expected if they were previously closed.
    *   If contracts are skipped with "sender not owner," verify the Ledger account is the owner.
