// @ts-check
const { SigningCosmWasmClient } = require('@cosmjs/cosmwasm-stargate');
const { LedgerSigner } = require('@cosmjs/ledger-amino');
const { makeCosmoshubPath } = require("@cosmjs/amino");
const TransportNodeHid = require('@ledgerhq/hw-transport-node-hid').default;
const { GasPrice, coin } = require('@cosmjs/stargate');
const { toUtf8 } = require("@cosmjs/encoding");
const readline = require('readline');

const GAS_PRICE_STRING = "0.025uom";
const LEDGER_ACCOUNT_PREFIX = "mantra";
const GAS_PER_MESSAGE = 300000; // Estimated gas for one MsgExecuteContract to close a campaign

async function main() {
    let transport;

    try {
        const rpcEndpoint = process.argv[2];
        const codeIdString = process.argv[3];
        const accountIndex = parseInt(process.argv[4] || "0", 10);

        if (!rpcEndpoint || !codeIdString) {
            console.error("Usage: node scripts/emergency/close_claimdrop_campaign.js <rpc_endpoint> <code_id> [account_index]");
            process.exit(1);
        }
        const codeId = parseInt(codeIdString, 10);
        if (isNaN(codeId)) {
            console.error("Error: <code_id> must be an integer.");
            process.exit(1);
        }

        console.log("--- Emergency Claimdrop Campaign Closure Script ---");
        console.log("Configuration:");
        console.log(`  RPC Endpoint:           ${rpcEndpoint}`);
        console.log(`  Target Code ID:         ${codeId}`);
        console.log(`  Ledger Account Index:   ${accountIndex} (HD Path: m/44'/118'/0'/0/${accountIndex})`);
        console.log(`  Ledger Account Prefix:  ${LEDGER_ACCOUNT_PREFIX}`);
        console.log(`  Gas Price:              ${GAS_PRICE_STRING}`);
        console.log(`  Est. Gas per message:   ${GAS_PER_MESSAGE}`);
        console.log("----------------------------------------------------");
        console.log("IMPORTANT: This script will prepare a SINGLE transaction to attempt to close campaigns on contracts that:");
        console.log("           1. Have an active, OPEN campaign (not already closed).");
        console.log("           2. Where the connected Ledger account is the current owner.");
        console.log("           This action is IRREVERSIBLE for each campaign closed.");
        console.log("----------------------------------------------------");

        const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
        await new Promise(resolve => {
            rl.question("Type 'yes' to confirm data gathering and preparation (transaction will be prompted later): ", (answer) => {
                if (answer.toLowerCase() !== 'yes') {
                    console.log("Operation cancelled by user.");
                    rl.close();
                    process.exit(0);
                }
                rl.close();
                resolve();
            });
        });

        console.log("\nAttempting to connect to Ledger device...");
        try {
            transport = await TransportNodeHid.create();
        } catch (e) {
            console.error("Error connecting to Ledger device:", e.message);
            process.exit(1);
        }

        const hdPath = makeCosmoshubPath(accountIndex);
        const ledgerSigner = new LedgerSigner(transport, { hdPaths: [hdPath], prefix: LEDGER_ACCOUNT_PREFIX });

        let accounts;
        try {
            accounts = await ledgerSigner.getAccounts();
        } catch (e) {
            console.error("Error getting accounts from Ledger:", e.message);
            process.exit(1);
        }
        if (accounts.length === 0) {
            console.error(`No accounts found on Ledger for HD Path ${hdPath.toString()} with prefix '${LEDGER_ACCOUNT_PREFIX}'.`);
            process.exit(1);
        }
        const senderAddress = accounts[0].address;
        console.log(`Successfully connected to Ledger. Using address: ${senderAddress}`);

        const client = await SigningCosmWasmClient.connectWithSigner(rpcEndpoint, ledgerSigner, {
            gasPrice: GasPrice.fromString(GAS_PRICE_STRING)
        });
        console.log(`Connected to RPC endpoint: ${rpcEndpoint}`);

        console.log(`Querying contracts for code ID ${codeId}...`);
        let contractAddresses;
        try {
            contractAddresses = await client.getContracts(codeId);
        } catch (err) {
            console.error(`Failed to query contracts for code ID ${codeId}:`, err);
            process.exit(1);
        }
        if (!contractAddresses || contractAddresses.length === 0) {
            console.log(`No contracts found for code ID ${codeId}. Exiting.`);
            process.exit(0);
        }
        console.log(`Found ${contractAddresses.length} contract(s) for code ID ${codeId}.`);

        const messagesToBroadcast = [];
        const closeCampaignMsgPayload = { manage_campaign: { action: { close_campaign: {} } } };

        let skippedNotOwnerCount = 0;
        let skippedNoCampaignCount = 0;
        let skippedAlreadyClosedCount = 0;
        let queryFailureCount = 0;

        console.log("\nFiltering contracts and preparing messages...");
        for (const contractAddress of contractAddresses) {
            console.log(`\nInspecting contract: ${contractAddress}`);
            try { // This try-catch is for errors during the querying phase for a single contract
                const campaignQuery = { campaign: {} };
                let campaignDetails;
                try {
                    campaignDetails = await client.queryContractSmart(contractAddress, campaignQuery);
                    if (campaignDetails && (campaignDetails.closed !== undefined && campaignDetails.closed !== null && campaignDetails.closed !== 0)) {
                        console.log(`  Campaign already closed (closed at: ${campaignDetails.closed}). Skipping.`);
                        skippedAlreadyClosedCount++;
                        continue;
                    }
                    console.log(`  Active and open campaign found.`);
                } catch (campaignQueryError) {
                    console.log(`  No active/open campaign found or error querying campaign.`);
                    skippedNoCampaignCount++;
                    continue;
                }

                const ownershipQuery = { ownership: {} };
                const ownershipResponse = await client.queryContractSmart(contractAddress, ownershipQuery);
                if (ownershipResponse && ownershipResponse.owner) {
                    const contractOwner = ownershipResponse.owner;
                    console.log(`  Contract owner: ${contractOwner}`);
                    if (contractOwner === senderAddress) {
                        console.log(`  Ledger address IS the owner. Adding 'CloseCampaign' message to batch for ${contractAddress}.`);
                        messagesToBroadcast.push({
                            typeUrl: "/cosmwasm.wasm.v1.MsgExecuteContract",
                            value: {
                                sender: senderAddress,
                                contract: contractAddress,
                                msg: toUtf8(JSON.stringify(closeCampaignMsgPayload)),
                                funds: [],
                            },
                        });
                    } else {
                        console.log(`  Ledger address is NOT the owner. Skipping.`);
                        skippedNotOwnerCount++;
                    }
                } else {
                    console.warn(`  Could not determine owner for contract ${contractAddress}. Skipping.`);
                    skippedNotOwnerCount++;
                }
            } catch (processContractError) {
                console.error(`  Error processing/querying contract ${contractAddress}:`, processContractError.message || processContractError);
                queryFailureCount++;
            }
        }

        console.log("\n--- Message Preparation Summary ---");
        console.log(`Prepared ${messagesToBroadcast.length} 'CloseCampaign' message(s) to broadcast.`);
        console.log(`Skipped ${skippedAlreadyClosedCount} contract(s) (campaign already closed).`);
        console.log(`Skipped ${skippedNoCampaignCount} contract(s) (no active/open campaign or query error).`);
        console.log(`Skipped ${skippedNotOwnerCount} contract(s) (sender not owner or owner undetermined).`);
        console.log(`Encountered ${queryFailureCount} errors during contract query/processing stage for individual contracts.`);


        if (messagesToBroadcast.length === 0) {
            console.log("\nNo valid campaigns to close for the connected Ledger account. Exiting.");
            process.exitCode = 0;
        } else {
            const rlConfirmBroadcast = readline.createInterface({ input: process.stdin, output: process.stdout });
            let confirmedToBroadcast = false;
            await new Promise(resolve => {
                rlConfirmBroadcast.question(`\nARE YOU ABSOLUTELY SURE you want to sign and broadcast a single transaction with ${messagesToBroadcast.length} 'CloseCampaign' messages? (yes/no): `, (answer) => {
                    rlConfirmBroadcast.close();
                    if (answer.toLowerCase() === 'yes') {
                        confirmedToBroadcast = true;
                    } else {
                        console.log("Operation cancelled by user. No transaction will be broadcast.");
                        process.exitCode = 0;
                    }
                    resolve();
                });
            });

            if (confirmedToBroadcast) {
                console.log("\nProceeding with signing and broadcasting... Please confirm on your Ledger device.");
                const totalGas = BigInt(messagesToBroadcast.length * GAS_PER_MESSAGE);
                const gasPriceForFee = GasPrice.fromString(GAS_PRICE_STRING);
                const feeAmount = Math.ceil(Number(totalGas) * parseFloat(gasPriceForFee.amount.toString()));

                const fee = {
                    amount: [coin(feeAmount.toString(), gasPriceForFee.denom)],
                    gas: totalGas.toString(),
                };
                const memo = `Emergency: Close ${messagesToBroadcast.length} claimdrop campaign(s)`;

                console.log(`  Total messages: ${messagesToBroadcast.length}`);
                console.log(`  Calculated total gas: ${totalGas.toString()}`);
                console.log(`  Calculated fee: ${fee.amount[0].amount}${fee.amount[0].denom}`);
                console.log(`  Memo: "${memo}"`);

                try {
                    const broadcastResult = await client.signAndBroadcast(senderAddress, messagesToBroadcast, fee, memo);
                    if (broadcastResult.code !== undefined && broadcastResult.code !== 0) {
                        console.error(`Transaction failed! Code: ${broadcastResult.code}, Log: ${broadcastResult.rawLog}`);
                        process.exitCode = 1;
                    } else {
                        console.log(`Transaction broadcasted successfully! Hash: ${broadcastResult.transactionHash}`);
                        console.log(`${messagesToBroadcast.length} 'CloseCampaign' messages were included in this transaction.`);
                        process.exitCode = 0;
                    }
                } catch (broadcastError) {
                    console.error("Error during signAndBroadcast:", broadcastError.message);
                    process.exitCode = 1;
                }
            }
        }
    } catch (error) { // This is the main catch block for the entire script's operation
        console.error("\nA critical unexpected error occurred:", error.message);
        if (error.stack) console.error(error.stack);
        process.exitCode = 1;
    } finally {
        if (transport) {
            try {
                await transport.close();
                console.log("Ledger transport closed.");
            } catch (closeError) {
                console.error("Error closing Ledger transport:", closeError.message);
            }
        }
        const exitCodeToUse = process.exitCode === undefined ? 1 : process.exitCode;
        console.log(`Exiting with code ${exitCodeToUse}.`);
        process.exit(exitCodeToUse);
    }
}

main();