// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../../contracts/mocks/MockERC20.sol";

/**
 * @title DeployMockToken
 * @notice Simple script to deploy a MockERC20 token for E2E testing
 * @dev Mints 10 million tokens to deployer
 */
contract DeployMockToken is Script {
    function run() external returns (address tokenAddress) {
        // Get deployer from PRIVATE_KEY
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        console.log("Deploying MockERC20 token...");
        console.log("Deployer:", deployer);
        console.log("Deployer Balance:", deployer.balance / 1e18, "OM");

        vm.startBroadcast(privateKey);

        // Deploy token
        MockERC20 token = new MockERC20("Test OM Token", "tOM", 18);
        console.log("MockERC20 deployed:", address(token));

        // Mint 10 million tokens to deployer
        uint256 initialSupply = 10_000_000 ether;
        token.mint(deployer, initialSupply);
        console.log("Minted", initialSupply / 1e18, "tOM to deployer");

        vm.stopBroadcast();

        console.log("");
        console.log("MockERC20 Token Address:", address(token));
        console.log("Add this to your .env file:");
        console.log("REWARD_TOKEN=", address(token));
        console.log("");

        return address(token);
    }
}
