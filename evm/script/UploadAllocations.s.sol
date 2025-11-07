// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Claimdrop} from "../contracts/Claimdrop.sol";

/**
 * @title UploadAllocations
 * @notice Script to upload allocations in batches to Claimdrop contract
 * @dev Run with: forge script script/UploadAllocations.s.sol:UploadAllocations --rpc-url $RPC_URL --broadcast
 *
 * Required environment variables:
 * - CLAIMDROP_ADDRESS: Address of deployed Claimdrop contract
 * - ALLOCATIONS_FILE: Path to JSON file with allocations
 *
 * Allocations file format (JSON):
 * [
 *   {"address": "0x123...", "amount": "1000000000000000000000"},
 *   {"address": "0x456...", "amount": "2000000000000000000000"}
 * ]
 *
 * The script will automatically batch allocations in groups of 3000 (MAX_ALLOCATION_BATCH_SIZE).
 *
 * Example:
 * CLAIMDROP_ADDRESS=0x123...
 * ALLOCATIONS_FILE=./allocations.json
 * forge script script/UploadAllocations.s.sol:UploadAllocations --rpc-url $RPC_URL --broadcast
 */
contract UploadAllocations is Script {
    uint256 constant BATCH_SIZE = 3000;

    struct Allocation {
        address addr;
        uint256 amount;
    }

    function run() external {
        // Load required parameters
        address claimdropAddress = vm.envAddress("CLAIMDROP_ADDRESS");
        string memory allocationsFilePath = vm.envString("ALLOCATIONS_FILE");

        console.log("=== Uploading Allocations ===");
        console.log("Claimdrop address:", claimdropAddress);
        console.log("Allocations file:", allocationsFilePath);

        // Read and parse JSON file
        string memory jsonContent = vm.readFile(allocationsFilePath);
        bytes memory jsonBytes = vm.parseJson(jsonContent);
        Allocation[] memory allocations = abi.decode(jsonBytes, (Allocation[]));

        console.log("Total allocations to upload:", allocations.length);
        console.log("");

        // Get Claimdrop contract
        Claimdrop claimdrop = Claimdrop(claimdropAddress);

        // Calculate number of batches
        uint256 totalBatches = (allocations.length + BATCH_SIZE - 1) / BATCH_SIZE;

        // Start broadcasting transactions
        vm.startBroadcast();

        uint256 totalUploaded = 0;

        // Upload in batches
        for (uint256 batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
            uint256 startIdx = batchIndex * BATCH_SIZE;
            uint256 endIdx = startIdx + BATCH_SIZE;
            if (endIdx > allocations.length) {
                endIdx = allocations.length;
            }

            uint256 batchSize = endIdx - startIdx;

            // Prepare batch arrays
            address[] memory addresses = new address[](batchSize);
            uint256[] memory amounts = new uint256[](batchSize);

            for (uint256 i = 0; i < batchSize; i++) {
                addresses[i] = allocations[startIdx + i].addr;
                amounts[i] = allocations[startIdx + i].amount;
            }

            console.log("Uploading batch", batchIndex + 1, "/", totalBatches);
            console.log("  Batch size:", batchSize);
            console.log("  From index:", startIdx);
            console.log("  To index:", endIdx - 1);

            // Upload batch
            claimdrop.addAllocations(addresses, amounts);

            totalUploaded += batchSize;

            console.log("  Batch uploaded successfully!");
            console.log("");
        }

        vm.stopBroadcast();

        console.log("All allocations uploaded!");
        console.log("Total uploaded:", totalUploaded);
    }
}
