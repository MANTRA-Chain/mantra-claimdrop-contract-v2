// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Claimdrop} from "../contracts/Claimdrop.sol";
import {E2ENetworkConfig} from "./e2e/E2ENetworkConfig.sol";

/**
 * @title Deploy
 * @notice Multi-network deployment script for Claimdrop contract
 * @dev Run with: NETWORK=<network> forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast
 *
 * Network Selection:
 *   - Set NETWORK env var: local, dukong, canary, mainnet
 *   - If not set, auto-detects from connected RPC's ChainID
 *
 * Examples:
 *   NETWORK=local forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast
 *   NETWORK=dukong forge script script/Deploy.s.sol:Deploy --rpc-url $MANTRA_DUKONG_RPC_URL --broadcast
 */
contract Deploy is Script, E2ENetworkConfig {
    function run() external returns (Claimdrop) {
        // Load and validate network configuration
        NetworkConfig memory network = getNetworkConfig();
        logNetworkInfo(network);

        console.log("");
        console.log("=== Deploying Claimdrop Contract ===");

        // Determine deployer
        bool useLedger = vm.envExists("USE_LEDGER") && vm.envBool("USE_LEDGER");
        address deployer;

        if (useLedger) {
            deployer = vm.envAddress("LEDGER_ADDRESS");
            console.log("Deployer: Ledger");
            console.log("Address:", deployer);
            vm.startBroadcast(deployer);
        } else {
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            deployer = vm.addr(deployerPrivateKey);
            console.log("Deployer: Private Key");
            console.log("Address:", deployer);
            vm.startBroadcast(deployerPrivateKey);
        }

        // Check deployer balance
        uint256 balance = deployer.balance;
        console.log("Balance:", balance / 1e18, "OM");

        require(balance > 0, "Insufficient balance for deployment");

        // Deploy contract
        Claimdrop claimdrop = new Claimdrop(deployer);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Successful ===");
        console.log("Claimdrop Address:", address(claimdrop));
        console.log("Owner:", deployer);

        // Generate explorer link if available
        if (bytes(network.explorerUrl).length > 0) {
            console.log("Explorer:", getExplorerAddressUrl(network, address(claimdrop)));
        }

        console.log("============================");

        return claimdrop;
    }
}
