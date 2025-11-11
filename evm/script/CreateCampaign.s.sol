// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Claimdrop} from "../contracts/Claimdrop.sol";
import {E2ENetworkConfig} from "./e2e/E2ENetworkConfig.sol";

/**
 * @title CreateCampaign
 * @notice Multi-network script to create a campaign on deployed Claimdrop contract
 * @dev Run with: NETWORK=<network> forge script script/CreateCampaign.s.sol:CreateCampaign --rpc-url $RPC_URL --broadcast
 *
 * Network-Aware Mode (Recommended for E2E Testing):
 *   - Set NETWORK env var (local, dukong, canary, mainnet)
 *   - Set USE_NETWORK_PROFILE=true to use network's timing profile
 *   - Timing automatically adapted based on network (fast for local, realistic for testnet/mainnet)
 *
 * Manual Configuration Mode (Production Campaigns):
 *   - Set all campaign parameters via environment variables (see below)
 *   - Timing fully controlled by user
 *
 * Required environment variables:
 * - CLAIMDROP_ADDRESS: Address of deployed Claimdrop contract
 * - CAMPAIGN_NAME: Name of the campaign
 * - CAMPAIGN_DESCRIPTION: Description of the campaign
 * - CAMPAIGN_TYPE: Type identifier (e.g., "airdrop")
 * - REWARD_TOKEN: Address of ERC20 reward token
 * - TOTAL_REWARD: Total reward amount in wei
 *
 * Timing Configuration (if not using USE_NETWORK_PROFILE):
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
 * Example (Network-Aware):
 * NETWORK=dukong USE_NETWORK_PROFILE=true CLAIMDROP_ADDRESS=0x123... REWARD_TOKEN=0x456...
 *
 * Example (Manual):
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
contract CreateCampaign is Script, E2ENetworkConfig {
    function run() external {
        // Load and validate network configuration
        NetworkConfig memory network = getNetworkConfig();
        console.log("Network:", network.name);

        // Check if using network profile for timing
        bool useNetworkProfile = vm.envOr("USE_NETWORK_PROFILE", false);

        // Load required parameters
        address claimdropAddress = vm.envAddress("CLAIMDROP_ADDRESS");
        string memory name = vm.envOr("CAMPAIGN_NAME", string("Test Campaign"));
        string memory description = vm.envOr("CAMPAIGN_DESCRIPTION", string("E2E test campaign"));
        string memory campaignType = vm.envOr("CAMPAIGN_TYPE", string("airdrop"));
        address rewardToken = vm.envAddress("REWARD_TOKEN");
        uint256 totalReward = vm.envUint("TOTAL_REWARD");

        uint64 startTime;
        uint64 endTime;

        if (useNetworkProfile) {
            // Use network timing profile
            TimingProfile memory timing = getTimingProfile(network);
            console.log("Using network timing profile:", timing.name);
            logTimingProfile(timing);

            startTime = uint64(block.timestamp + timing.startDelay);
            endTime = uint64(startTime + timing.campaignDuration);

            console.log("");
            console.log("Calculated campaign timing:");
            console.log("Start time:", startTime);
            console.log("End time:", endTime);
        } else {
            // Use manual timing from env vars
            startTime = uint64(vm.envUint("CAMPAIGN_START_TIME"));
            endTime = uint64(vm.envUint("CAMPAIGN_END_TIME"));
        }

        console.log("");
        console.log("=== Creating Campaign ===");
        console.log("Claimdrop address:", claimdropAddress);
        console.log("Campaign name:", name);
        console.log("Reward token:", rewardToken);
        console.log("Total reward:", totalReward);
        console.log("Start time:", startTime);
        console.log("End time:", endTime);

        // Build distributions array
        Claimdrop.Distribution[] memory distributions;

        if (useNetworkProfile) {
            // Use network timing profile for distributions
            TimingProfile memory timing = getTimingProfile(network);
            distributions = buildDistributionsFromProfile(timing, startTime, endTime);
        } else {
            // Build from env vars
            distributions = new Claimdrop.Distribution[](0);

            // Load first distribution (always required)
            if (bytes(vm.envOr("DIST_0_KIND", string(""))).length > 0) {
                distributions = addDistribution(distributions, 0);
            }

            // Load second distribution if present
            if (bytes(vm.envOr("DIST_1_KIND", string(""))).length > 0) {
                distributions = addDistribution(distributions, 1);
            }

            require(distributions.length > 0, "At least one distribution required");
        }

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

    /**
     * @notice Build distributions from timing profile
     * @param timing Timing profile
     * @param campaignStartTime Campaign start timestamp
     * @param campaignEndTime Campaign end timestamp
     * @return distributions Array of distribution configurations
     */
    function buildDistributionsFromProfile(
        TimingProfile memory timing,
        uint64 campaignStartTime,
        uint64 campaignEndTime
    ) internal pure returns (Claimdrop.Distribution[] memory distributions) {
        distributions = new Claimdrop.Distribution[](2);

        // Distribution 0: Lump Sum
        distributions[0] = Claimdrop.Distribution({
            kind: Claimdrop.DistributionKind.LumpSum,
            percentageBps: timing.lumpSumPercentageBps,
            startTime: campaignStartTime,
            endTime: 0, // LumpSum doesn't have end time
            cliffDuration: 0 // LumpSum doesn't have cliff
        });

        // Distribution 1: Linear Vesting
        distributions[1] = Claimdrop.Distribution({
            kind: Claimdrop.DistributionKind.LinearVesting,
            percentageBps: timing.vestingPercentageBps,
            startTime: campaignStartTime,
            endTime: uint64(campaignStartTime + timing.vestingDuration),
            cliffDuration: uint64(timing.cliffDuration)
        });

        return distributions;
    }
}
