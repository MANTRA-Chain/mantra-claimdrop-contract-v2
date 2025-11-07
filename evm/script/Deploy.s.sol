// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Claimdrop} from "../contracts/Claimdrop.sol";

/**
 * @title Deploy
 * @notice Deployment script for Claimdrop contract
 * @dev Run with: forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast
 */
contract Deploy is Script {
    function run() external returns (Claimdrop) {
        // Get owner address from environment or use msg.sender
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);

        console.log("Deploying Claimdrop contract...");
        console.log("Deploying with account:", msg.sender);
        console.log("Owner will be:", owner);
        console.log("Account balance:", msg.sender.balance / 1e18, "ETH");

        vm.startBroadcast();

        // Deploy contract
        Claimdrop claimdrop = new Claimdrop(owner);

        vm.stopBroadcast();

        console.log("Claimdrop deployed to:", address(claimdrop));
        console.log("Deployment complete!");

        return claimdrop;
    }
}
