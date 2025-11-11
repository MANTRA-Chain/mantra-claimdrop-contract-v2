// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ClaimdropFactory} from "../contracts/ClaimdropFactory.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title UpgradeFactory
 * @notice Upgrade script for ClaimdropFactory contract
 * @dev Run with: forge script script/UpgradeFactory.s.sol:UpgradeFactory --rpc-url $RPC_URL --broadcast
 *
 * Required environment variables:
 * - PROXY_ADDRESS: Address of the TransparentUpgradeableProxy
 * - PROXY_ADMIN_ADDRESS: Address of the ProxyAdmin
 */
contract UpgradeFactory is Script {
    function run() external returns (ClaimdropFactory) {
        // Get required addresses from environment
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");

        console.log("Upgrading ClaimdropFactory...");
        console.log("Proxy address:", proxyAddress);
        console.log("ProxyAdmin address:", proxyAdminAddress);

        bool useLedger = vm.envExists("USE_LEDGER") && vm.envBool("USE_LEDGER");
        address deployer;

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

        // 1. Deploy the new implementation
        console.log("\n1. Deploying new ClaimdropFactory implementation...");
        ClaimdropFactory newImplementation = new ClaimdropFactory();
        console.log("New implementation deployed to:", address(newImplementation));

        // 2. Upgrade the proxy
        console.log("\n2. Upgrading proxy to new implementation...");
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(proxyAddress),
            address(newImplementation)
        );
        console.log("Proxy upgraded successfully!");

        // 3. Verify the upgrade
        ClaimdropFactory factory = ClaimdropFactory(proxyAddress);
        console.log("\n3. Verifying upgrade...");
        console.log("Factory owner:", factory.owner());
        console.log("Deployed claimdrops count:", factory.getDeployedClaimdropsCount());

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Upgrade Summary:");
        console.log("========================================");
        console.log("New Implementation:", address(newImplementation));
        console.log("Proxy (unchanged):", proxyAddress);
        console.log("ProxyAdmin (unchanged):", proxyAdminAddress);
        console.log("========================================");
        console.log("Upgrade complete!");

        return factory;
    }
}

