// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { PrimarySaleClaimdropFactory } from "../contracts/PrimarySaleClaimdropFactory.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title UpgradeFactory
 * @notice Upgrade script for PrimarySaleClaimdropFactory contract
 * @dev Run with: forge script script/UpgradeFactory.s.sol:UpgradeFactory --rpc-url $RPC_URL --broadcast
 */
contract UpgradeFactory is Script {
    // Replace with your deployed proxy and proxy admin addresses
    address constant PROXY_ADDRESS = 0x30056743b1dC4407b6AfA0CfC0332B79d1f79258;
    address constant PROXY_ADMIN_ADDRESS = 0x0A9a091C266d3D8bAF807faC22Be7e2AdDe410A6;

    function run() external {
        // Load admin private key from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Upgrading PrimarySaleClaimdropFactory contract...");
        console.log("Deployer address: ", deployer);

        // Use factory admin for broadcasting upgrade
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the new implementation contract
        console.log("\n1. Deploying new PrimarySaleClaimdropFactory implementation...");
        PrimarySaleClaimdropFactory newImplementation = new PrimarySaleClaimdropFactory();
        console.log("New implementation deployed to:", address(newImplementation));

        // 2. Load proxy address from environment
        console.log("Proxy address:", PROXY_ADDRESS);

        // 3. Load ProxyAdmin address from environment
        console.log("ProxyAdmin address:", PROXY_ADMIN_ADDRESS);

        // 4. Create ProxyAdmin instance
        ProxyAdmin proxyAdmin = ProxyAdmin(PROXY_ADMIN_ADDRESS);
        address admin = proxyAdmin.owner();
        console.log("ProxyAdmin owner:", admin);
        require(admin == deployer, "Deployer is not the ProxyAdmin owner");

        // 5. Perform the upgrade
        console.log("\n2. Upgrading proxy to new implementation...");
        
        // For OpenZeppelin v5.0.0, we must use upgradeAndCall even if we don't need to call anything
        // Pass empty bytes for initialization data since we're not reinitializing
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(PROXY_ADDRESS),
            address(newImplementation),
            ""
        );
        
        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Upgrade Summary:");
        console.log("========================================");
        console.log("ProxyAdmin Contract:", PROXY_ADMIN_ADDRESS);
        console.log("Proxy (PrimarySaleClaimdropFactory):", PROXY_ADDRESS);
        console.log("New Implementation:", address(newImplementation));
        console.log("========================================");
        console.log("Upgrade complete!");
    }
}
