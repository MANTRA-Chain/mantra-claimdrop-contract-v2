// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ClaimdropFactory} from "../contracts/ClaimdropFactory.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployFactory
 * @notice Deployment script for upgradeable ClaimdropFactory contract
 * @dev Run with: forge script script/DeployFactory.s.sol:DeployFactory --rpc-url $RPC_URL --broadcast
 */
contract DeployFactory is Script {
    function run() external {
        bool useLedger = vm.envExists("USE_LEDGER") && vm.envBool("USE_LEDGER");
        address deployer;

        console.log("Deploying upgradeable ClaimdropFactory contract...");
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

        uint256 nonce = vm.getNonce(deployer);
        console.log("Deployer nonce:", nonce);

        // 1. Deploy the implementation contract
        console.log("\n1. Deploying ClaimdropFactory implementation...");
        ClaimdropFactory implementation = new ClaimdropFactory();
        console.log("Implementation deployed to:", address(implementation));

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeCall(
            ClaimdropFactory.initialize,
            (deployer)
        );

        // 3. Deploy the TransparentUpgradeableProxy
        console.log("\n3. Deploying TransparentUpgradeableProxy...");
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            deployer,
            initData
        );
        console.log("Proxy deployed to:", address(proxy));

        vm.stopBroadcast();

        // Get the ProxyAdmin address that was created by the proxy
        bytes32 adminSlot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        address proxyAdmin = address(uint160(uint256(vm.load(address(proxy), adminSlot))));

        console.log("\n========================================");
        console.log("Deployment Summary:");
        console.log("========================================");
        console.log("Implementation:", address(implementation));
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("Proxy (ClaimdropFactory):", address(proxy));
        console.log("Factory Owner:", deployer);
        console.log("========================================");
        console.log("Deployment complete!");
    }
}
