// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Claimdrop} from "../contracts/Claimdrop.sol";

/**
 * @title CreateCampaign
 * @notice Script to create a campaign on deployed Claimdrop contract
 * @dev Run with: forge script script/CreateCampaign.s.sol:CreateCampaign --rpc-url $RPC_URL --broadcast
 *
 * Required environment variables:
 * - CLAIMDROP_ADDRESS: Address of deployed Claimdrop contract
 * - CAMPAIGN_NAME: Name of the campaign
 * - CAMPAIGN_DESCRIPTION: Description of the campaign
 * - CAMPAIGN_TYPE: Type identifier (e.g., "airdrop")
 * - REWARD_TOKEN: Address of ERC20 reward token
 * - TOTAL_REWARD: Total reward amount in wei
 * - CAMPAIGN_START_TIME: Unix timestamp for campaign start
 * - CAMPAIGN_END_TIME: Unix timestamp for campaign end
 *
 * Distribution configuration (supports up to 2 distributions):
 * - DIST_0_KIND: "LinearVesting" or "LumpSum"
 * - DIST_0_PERCENTAGE_BPS: Percentage in basis points (e.g., 3000 = 30%)
 * - DIST_0_START_TIME: Distribution start timestamp
 * - DIST_0_END_TIME: Distribution end timestamp (0 for LumpSum)
 * - DIST_0_CLIFF_DURATION: Cliff duration in seconds (0 for no cliff)
 *
 * Optional second distribution (DIST_1_*) with same parameters
 *
 * Example:
 * CLAIMDROP_ADDRESS=0x123...
 * CAMPAIGN_NAME="MANTRA Airdrop Q1 2025"
 * CAMPAIGN_DESCRIPTION="Quarterly token distribution"
 * CAMPAIGN_TYPE="airdrop"
 * REWARD_TOKEN=0x456...
 * TOTAL_REWARD=1000000000000000000000000
 * CAMPAIGN_START_TIME=1735689600
 * CAMPAIGN_END_TIME=1767225600
 * DIST_0_KIND="LumpSum"
 * DIST_0_PERCENTAGE_BPS=3000
 * DIST_0_START_TIME=1735689600
 * DIST_0_END_TIME=0
 * DIST_0_CLIFF_DURATION=0
 * DIST_1_KIND="LinearVesting"
 * DIST_1_PERCENTAGE_BPS=7000
 * DIST_1_START_TIME=1735689600
 * DIST_1_END_TIME=1767225600
 * DIST_1_CLIFF_DURATION=2592000
 */
contract CreateCampaign is Script {
    function run() external {
        // Load required parameters
        address claimdropAddress = vm.envAddress("CLAIMDROP_ADDRESS");
        string memory name = vm.envString("CAMPAIGN_NAME");
        string memory description = vm.envString("CAMPAIGN_DESCRIPTION");
        string memory campaignType = vm.envString("CAMPAIGN_TYPE");
        address rewardToken = vm.envAddress("REWARD_TOKEN");
        uint256 totalReward = vm.envUint("TOTAL_REWARD");
        uint64 startTime = uint64(vm.envUint("CAMPAIGN_START_TIME"));
        uint64 endTime = uint64(vm.envUint("CAMPAIGN_END_TIME"));

        console.log("=== Creating Campaign ===");
        console.log("Claimdrop address:", claimdropAddress);
        console.log("Campaign name:", name);
        console.log("Reward token:", rewardToken);
        console.log("Total reward:", totalReward);
        console.log("Start time:", startTime);
        console.log("End time:", endTime);

        // Build distributions array
        Claimdrop.Distribution[] memory distributions = new Claimdrop.Distribution[](0);

        // Load first distribution (always required)
        if (bytes(vm.envOr("DIST_0_KIND", string(""))).length > 0) {
            distributions = addDistribution(distributions, 0);
        }

        // Load second distribution if present
        if (bytes(vm.envOr("DIST_1_KIND", string(""))).length > 0) {
            distributions = addDistribution(distributions, 1);
        }

        require(distributions.length > 0, "At least one distribution required");

        // Validate percentages sum to 100%
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < distributions.length; i++) {
            totalPercentage += distributions[i].percentageBps;
            console.log("Distribution", i, ":");
            console.log(
                "  Kind:",
                distributions[i].kind == Claimdrop.DistributionKind.LinearVesting ? "LinearVesting" : "LumpSum"
            );
            console.log("  Percentage:", distributions[i].percentageBps, "bps");
            console.log("  Start time:", distributions[i].startTime);
            console.log("  End time:", distributions[i].endTime);
            console.log("  Cliff duration:", distributions[i].cliffDuration);
        }

        require(totalPercentage == 10000, "Percentages must sum to 10000 (100%)");

        // Get Claimdrop contract
        Claimdrop claimdrop = Claimdrop(claimdropAddress);

        // Create campaign
        vm.startBroadcast();

        claimdrop.createCampaign(
            name, description, campaignType, rewardToken, totalReward, distributions, startTime, endTime
        );

        vm.stopBroadcast();

        console.log("");
        console.log("Campaign created successfully!");
    }

    /**
     * @notice Add a distribution to the array
     * @param distributions Current distributions array
     * @param index Distribution index (0 or 1)
     * @return Updated distributions array
     */
    function addDistribution(Claimdrop.Distribution[] memory distributions, uint256 index)
        internal
        view
        returns (Claimdrop.Distribution[] memory)
    {
        // Create prefix for env vars
        string memory prefix = index == 0 ? "DIST_0_" : "DIST_1_";

        // Load distribution parameters
        string memory kindStr = vm.envString(string.concat(prefix, "KIND"));
        uint16 percentageBps = uint16(vm.envUint(string.concat(prefix, "PERCENTAGE_BPS")));
        uint64 distStartTime = uint64(vm.envUint(string.concat(prefix, "START_TIME")));
        uint64 distEndTime = uint64(vm.envUint(string.concat(prefix, "END_TIME")));
        uint64 cliffDuration = uint64(vm.envUint(string.concat(prefix, "CLIFF_DURATION")));

        // Convert kind string to enum
        Claimdrop.DistributionKind kind;
        if (keccak256(bytes(kindStr)) == keccak256(bytes("LinearVesting"))) {
            kind = Claimdrop.DistributionKind.LinearVesting;
        } else if (keccak256(bytes(kindStr)) == keccak256(bytes("LumpSum"))) {
            kind = Claimdrop.DistributionKind.LumpSum;
        } else {
            revert("Invalid distribution kind. Must be 'LinearVesting' or 'LumpSum'");
        }

        // Create new array with one more element
        Claimdrop.Distribution[] memory newDistributions = new Claimdrop.Distribution[](distributions.length + 1);

        // Copy existing distributions
        for (uint256 i = 0; i < distributions.length; i++) {
            newDistributions[i] = distributions[i];
        }

        // Add new distribution
        newDistributions[distributions.length] = Claimdrop.Distribution({
            kind: kind,
            percentageBps: percentageBps,
            startTime: distStartTime,
            endTime: distEndTime,
            cliffDuration: cliffDuration
        });

        return newDistributions;
    }
}
