// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { PrimarySaleClaimdropFactory } from "../contracts/PrimarySaleClaimdropFactory.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployFactory
 * @notice Deployment script for upgradeable PrimarySaleClaimdropFactory contract
 * @dev Run with: forge script script/DeployFactory.s.sol:DeployFactory --rpc-url $RPC_URL --broadcast
 */
contract DeployFactory is Script {
    function run() external {
        // Load admin private key from env
        uint256 factoryAdminPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAdmin = vm.addr(factoryAdminPrivateKey);

        /*
         * Deploy with hardware wallet
         */
        // address factoryAdmin = <YOUR_HARDWARE_WALLET_ADDRESS>;
        // vm.startBroadcast(hardwareWalletAddress);

        console.log("Deploying upgradeable PrimarySaleClaimdropFactory contract...");
        console.log("Factory Admin address: ", factoryAdmin);

        // Use factory admin for broadcasting deployment
        vm.startBroadcast(factoryAdminPrivateKey);

        // 1. Deploy the implementation contract
        console.log("\n2. Deploying PrimarySaleClaimdropFactory implementation...");
        PrimarySaleClaimdropFactory implementation = new PrimarySaleClaimdropFactory();
        console.log("Implementation deployed to:", address(implementation));

        // 2. Prepare initialization data with metadata
        string memory factoryName = "MANTRA Primary Sale & Claimdrop Factory";
        string memory factorySlug = "mantra-factory";
        string memory factoryDescription = "Factory for deploying and managing Claimdrop and PrimarySale contracts";

        bytes memory initData = abi.encodeCall(
            PrimarySaleClaimdropFactory.initialize, (factoryAdmin, factoryName, factorySlug, factoryDescription)
        );

        // 3. Deploy the TransparentUpgradeableProxy with ProxyAdmin contract as admin
        console.log("\n4. Deploying TransparentUpgradeableProxy...");
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), factoryAdmin, initData);
        console.log("Proxy deployed to:", address(proxy));

        // 4. Get the ProxyAdmin address that was created by the proxy
        // The proxy's admin is stored at ERC1967 admin slot
        console.log("\n1. Deploying ProxyAdmin contract...");
        bytes32 adminSlot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        address proxyAdminAddress = address(uint160(uint256(vm.load(address(proxy), adminSlot))));
        console.log("ProxyAdmin deployed to:", proxyAdminAddress);

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Deployment Summary:");
        console.log("========================================");
        console.log("ProxyAdmin Contract:", proxyAdminAddress);
        console.log("ProxyAdmin Owner:", factoryAdmin);
        console.log("Implementation:", address(implementation));
        console.log("Proxy (PrimarySaleClaimdropFactory):", address(proxy));
        console.log("Factory Owner:", factoryAdmin);
        console.log("Factory Name:", factoryName);
        console.log("Factory Slug:", factorySlug);
        console.log("========================================");
        console.log("Deployment complete!");
    }
}
