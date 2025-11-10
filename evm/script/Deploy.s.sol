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
        bool useLedger = vm.envExists("USE_LEDGER") && vm.envBool("USE_LEDGER");
        address deployer;

        console.log("Deploying Claimdrop contract...");
        if (useLedger) {
            deployer = vm.envAddress("LEDGER_ADDRESS");
            console.log("Using Ledger as deployer, address is ", deployer);
            vm.startBroadcast(deployer);
        } else {
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            deployer = vm.addr(deployerPrivateKey);
            console.log("Using private key as deployer, address is ", deployer);
            vm.startBroadcast(deployerPrivateKey);
        }

        // Check deployer balance
        uint256 balance = deployer.balance;
        console.log("Deployer balance:", (balance / 1e18), ".", (balance % 1e18));


        // Deploy contract
        Claimdrop claimdrop = new Claimdrop(deployer);

        vm.stopBroadcast();

        console.log("Claimdrop deployed to:", address(claimdrop));
        console.log("Deployment complete!");

        return claimdrop;
    }
}
