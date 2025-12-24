// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { PyseOracle } from "../contracts/PyseOracle.sol";
import { PrimarySaleClaimdropFactory } from "../contracts/PrimarySaleClaimdropFactory.sol";

contract DeployPyseOracle is Script {
    function run() external returns (PyseOracle pyseOracle) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get the claimdrop factory address from environment variables or command line
        address claimDropFactoryAddress = vm.envAddress("CLAIMDROP_FACTORY_ADDRESS");

        // Start broadcasting the transaction
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the PyseOracle contract with the factory address
        console.log("\n1. Deploying PyseOracle contract...");
        pyseOracle = new PyseOracle(claimDropFactoryAddress);

        vm.stopBroadcast();

        // Print the deployed address
        console.log("\n========================================");
        console.log("Deployment Summary:");
        console.log("========================================");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("PyseOracle deployed at:", address(pyseOracle));
        console.log("========================================");
        console.log("Deployment complete!");
    }
}
