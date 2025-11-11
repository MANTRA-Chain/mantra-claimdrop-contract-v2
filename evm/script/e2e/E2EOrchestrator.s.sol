// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Claimdrop} from "../../contracts/Claimdrop.sol";
import {MockERC20} from "../../contracts/mocks/MockERC20.sol";
import {E2EBase} from "./E2EBase.sol";

/**
 * @title E2EOrchestrator
 * @notice Complete end-to-end lifecycle orchestration for Claimdrop contract
 * @dev Executes all 7 phases of the Claimdrop lifecycle in a single command:
 *      1. Deploy Contract
 *      2. Create Campaign
 *      3. Upload Allocations
 *      4. Wait for Campaign Start
 *      5. Execute Claims
 *      6. Close Campaign
 *      7. Validation
 *
 * Usage:
 *   # Local network (fast, 1-2 minutes)
 *   NETWORK=local forge script script/e2e/E2EOrchestrator.s.sol:E2EOrchestrator --broadcast -vv
 *
 *   # DuKong testnet (realistic timing, 1-2 hours)
 *   NETWORK=dukong REWARD_TOKEN=0x... forge script script/e2e/E2EOrchestrator.s.sol:E2EOrchestrator --broadcast -vv
 *
 * Environment Variables:
 *   - NETWORK: Target network (local, dukong, canary, mainnet) - auto-detected if not set
 *   - REWARD_TOKEN: ERC20 token address (required for testnet, auto-deployed on local)
 *   - PRIVATE_KEY: Deployer private key (required for testnet)
 *   - USE_NETWORK_PROFILE: Use network timing profile (default: true)
 *
 * Output:
 *   - State file: out/e2e-state-{network}.json
 *   - Report file: out/e2e-report-{network}-{timestamp}.md
 *   - Console logs with progress and transaction details
 */
contract E2EOrchestrator is E2EBase {
    // ============ State Variables ============

    NetworkConfig internal network;
    TimingProfile internal timing;
    E2EState internal state;

    Claimdrop internal claimdrop;
    MockERC20 internal token;

    address[] internal testUsers;
    uint256[] internal testAllocations;

    uint256 internal startTimestamp;
    uint256 internal totalGasUsed;

    // ============ Main Entry Point ============

    /**
     * @notice Main orchestration function - executes all 7 phases
     * @dev Saves state after each phase for recovery
     * @return claimdropAddress Address of deployed Claimdrop contract
     */
    function run() external returns (address claimdropAddress) {
        startTimestamp = block.timestamp;

        console.log("");
        console.log("=======================================================");
        console.log("  E2E Orchestrator - Complete Claimdrop Lifecycle");
        console.log("=======================================================");
        console.log("");

        // Load network configuration
        network = getNetworkConfig();
        logNetworkInfo(network);

        timing = getTimingProfile(network);
        logTimingProfile(timing);

        // Initialize state
        state.network = network.name;
        state.chainId = network.chainId;
        state.timestamp = block.timestamp;

        // Execute phases
        phase1_DeployContract();
        phase2_CreateCampaign();
        phase3_UploadAllocations();
        phase4_WaitForCampaignStart();
        phase5_ExecuteClaims();
        phase6_CloseCampaign();
        phase7_Validation();

        // Generate final report
        generateFinalReport();

        console.log("");
        console.log("=======================================================");
        console.log("  E2E Orchestration Complete!");
        console.log("=======================================================");
        uint256 duration = block.timestamp - startTimestamp;
        console.log("Total Duration (seconds):", duration);
        console.log("Total Duration (minutes):", duration / 60);
        console.log("Report:", getReportFilePath(network));
        console.log("=======================================================");
        console.log("");

        return address(claimdrop);
    }

    // ============ Phase 1: Deploy Contract ============

    /**
     * @notice Phase 1 - Deploy Claimdrop contract and reward token
     * @dev On local: Deploys MockERC20
     *      On testnet: Uses REWARD_TOKEN env var
     */
    function phase1_DeployContract() internal {
        logPhaseHeader(1, 7, "Deploy Contract");

        // Get deployer
        address deployer = getDeployer();
        console.log("Deployer:", deployer);
        console.log("Deployer Balance:", deployer.balance / 1e18, "OM");

        vm.startBroadcast();

        // Deploy Claimdrop
        claimdrop = new Claimdrop(deployer);
        console.log("Claimdrop deployed:", address(claimdrop));

        // Deploy/get reward token
        address tokenAddress = getRewardToken(network);
        token = MockERC20(tokenAddress);
        console.log("Reward token:", address(token));

        vm.stopBroadcast();

        // Update state
        state.claimdrop = address(claimdrop);
        state.rewardToken = address(token);
        state.lastCompletedPhase = 1;
        state.timestamp = block.timestamp;
        saveState(state, network);

        logPhaseComplete(1, 7);
    }

    // ============ Phase 2: Create Campaign ============

    /**
     * @notice Phase 2 - Create campaign with network-appropriate timing
     * @dev Uses timing profile from network config for realistic test scenarios
     */
    function phase2_CreateCampaign() internal {
        logPhaseHeader(2, 7, "Create Campaign");

        // Calculate campaign timing
        uint64 startTime = uint64(vm.getBlockTimestamp() + timing.startDelay);
        uint64 endTime = uint64(startTime + timing.campaignDuration);

        // Calculate total reward needed
        (testUsers, testAllocations) = generateTestAllocations(network);
        uint256 totalReward = 0;
        for (uint256 i = 0; i < testAllocations.length; i++) {
            totalReward += testAllocations[i];
        }

        console.log("Campaign Parameters:");
        console.log("  Start Time:", startTime);
        console.log("  Start Delay (seconds):", timing.startDelay);
        console.log("  End Time:", endTime);
        console.log("  Duration (seconds):", timing.campaignDuration);
        console.log("  Total Reward:", totalReward / 1e18, "OM");

        // Build distributions
        Claimdrop.Distribution[] memory distributions = new Claimdrop.Distribution[](2);

        // Distribution 0: Lump Sum (30%)
        distributions[0] = Claimdrop.Distribution({
            kind: Claimdrop.DistributionKind.LumpSum,
            percentageBps: timing.lumpSumPercentageBps,
            startTime: startTime,
            endTime: 0, // LumpSum doesn't need end time
            cliffDuration: 0 // LumpSum doesn't need cliff
        });

        // Distribution 1: Linear Vesting (70%)
        distributions[1] = Claimdrop.Distribution({
            kind: Claimdrop.DistributionKind.LinearVesting,
            percentageBps: timing.vestingPercentageBps,
            startTime: startTime,
            endTime: uint64(startTime + timing.vestingDuration),
            cliffDuration: uint64(timing.cliffDuration)
        });

        console.log("Distributions:");
        console.log("  [0] LumpSum (bps):", timing.lumpSumPercentageBps);
        console.log("  [1] Vesting (bps):", timing.vestingPercentageBps);
        console.log("  [1] Cliff (seconds):", timing.cliffDuration);

        vm.startBroadcast();

        // Fund the contract with reward tokens
        if (network.chainId == 31337) {
            // Local: Mint and transfer
            token.mint(getDeployer(), totalReward);
        }
        token.transfer(address(claimdrop), totalReward);
        console.log("Contract funded with", totalReward / 1e18, "tokens");

        // Create campaign
        claimdrop.createCampaign(
            "E2E Test Campaign",
            "Automated end-to-end test campaign",
            "e2e-test",
            address(token),
            totalReward,
            distributions,
            startTime,
            endTime
        );

        vm.stopBroadcast();

        console.log("Campaign created successfully!");

        // Update state
        state.campaignStartTime = startTime;
        state.campaignEndTime = endTime;
        state.lastCompletedPhase = 2;
        state.timestamp = block.timestamp;
        saveState(state, network);

        logPhaseComplete(2, 7);
    }

    // ============ Phase 3: Upload Allocations ============

    /**
     * @notice Phase 3 - Upload test user allocations
     * @dev Uploads 10 test users with varying allocation amounts
     */
    function phase3_UploadAllocations() internal {
        logPhaseHeader(3, 7, "Upload Allocations");

        console.log("Uploading allocations for", testUsers.length, "users");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < testAllocations.length; i++) {
            totalAmount += testAllocations[i];
            console.log("  User", i, testUsers[i]);
            console.log("    Allocation:", testAllocations[i] / 1e18, "OM");
        }

        console.log("Total Allocations:", totalAmount / 1e18, "OM");

        vm.startBroadcast();

        // Upload allocations (single batch, small test set)
        claimdrop.addAllocations(testUsers, testAllocations);

        vm.stopBroadcast();

        console.log("Allocations uploaded successfully!");

        // Verify allocations were stored correctly
        for (uint256 i = 0; i < testUsers.length; i++) {
            uint256 allocation = claimdrop.allocations(testUsers[i]);
            require(allocation == testAllocations[i], "Allocation verification failed");
        }
        console.log("Allocation verification passed!");

        // Update state
        state.testUsers = testUsers;
        state.allocations = testAllocations;
        state.lastCompletedPhase = 3;
        state.timestamp = block.timestamp;
        saveState(state, network);

        logPhaseComplete(3, 7);
    }

    // ============ Phase 4: Wait for Campaign Start ============

    /**
     * @notice Phase 4 - Wait for campaign to start
     * @dev Local: Uses vm.warp() for instant time jump
     *      Testnet: Documents waiting pattern (manual intervention needed)
     */
    function phase4_WaitForCampaignStart() internal {
        logPhaseHeader(4, 7, "Wait for Campaign Start");

        uint64 startTime = state.campaignStartTime;
        uint256 currentTime = vm.getBlockTimestamp();

        console.log("Current Time:", currentTime);
        console.log("Campaign Start:", startTime);

        if (currentTime >= startTime) {
            console.log("Campaign has already started!");
        } else {
            uint256 waitTime = startTime - currentTime;
            console.log("Waiting (seconds):", waitTime);
            console.log("Waiting (minutes):", waitTime / 60);

            // Wait for campaign start (network-aware)
            waitForTimestamp(startTime, network);
        }

        // Verify we're at or past start time
        if (network.chainId == 31337) {
            require(vm.getBlockTimestamp() >= startTime, "Failed to reach campaign start time");
            console.log("Time warped successfully to:", vm.getBlockTimestamp());
        }

        // Update state
        state.lastCompletedPhase = 4;
        state.timestamp = block.timestamp;
        saveState(state, network);

        logPhaseComplete(4, 7);
    }

    // ============ Phase 5: Execute Claims ============

    /**
     * @notice Phase 5 - Execute claims for test users
     * @dev Claims for subset of users to test partial claiming scenario
     */
    function phase5_ExecuteClaims() internal {
        logPhaseHeader(5, 7, "Execute Claims");

        // Warp slightly past cliff to enable vesting claims
        if (network.chainId == 31337 && timing.cliffDuration > 0) {
            warpForward(timing.cliffDuration + 60, network); // 60 seconds past cliff
            console.log("Warped past cliff period");
        }

        uint256 totalClaimed = 0;

        // Claim for first 5 users (partial test)
        uint256 claimCount = testUsers.length / 2;
        console.log("Executing claims for", claimCount, "users");

        for (uint256 i = 0; i < claimCount; i++) {
            address user = testUsers[i];
            (, uint256 claimable,) = claimdrop.getRewards(user);

            if (claimable > 0) {
                console.log("");
                console.log("Claiming for user", i);
                console.log("  Address:", user);
                console.log("  Claimable:", claimable / 1e18, "OM");

                vm.startBroadcast();

                // User claims to their own address
                vm.stopBroadcast();

                // Broadcast as user (simulate user claiming)
                vm.startBroadcast(user);
                claimdrop.claim(user, claimable);
                vm.stopBroadcast();

                // Verify claim
                uint256 balance = token.balanceOf(user);
                console.log("  Balance after claim:", balance / 1e18, "OM");

                totalClaimed += claimable;
            } else {
                console.log("User", i, "has no claimable amount (cliff period or already claimed)");
            }
        }

        console.log("");
        console.log("Claims executed successfully!");
        console.log("Total Claimed:", totalClaimed / 1e18, "OM");
        console.log("Users Claimed:", claimCount);

        // Update state
        state.totalClaimed = totalClaimed;
        state.lastCompletedPhase = 5;
        state.timestamp = block.timestamp;
        saveState(state, network);

        logPhaseComplete(5, 7);
    }

    // ============ Phase 6: Close Campaign ============

    /**
     * @notice Phase 6 - Close campaign and return unclaimed tokens
     * @dev Only owner can close campaign
     */
    function phase6_CloseCampaign() internal {
        logPhaseHeader(6, 7, "Close Campaign");

        // Get deployer (owner)
        address owner = getDeployer();

        // Check contract balance before close
        uint256 balanceBefore = token.balanceOf(address(claimdrop));
        console.log("Contract balance before close:", balanceBefore / 1e18, "OM");

        vm.startBroadcast();

        // Close campaign (returns unclaimed tokens to owner)
        claimdrop.closeCampaign();

        vm.stopBroadcast();

        console.log("Campaign closed successfully!");

        // Verify campaign is closed
        (,,,,,,,, uint64 closedAt,) = claimdrop.campaign();
        require(closedAt != 0, "Campaign close verification failed");
        console.log("Campaign closed at:", closedAt);

        // Update state
        state.lastCompletedPhase = 6;
        state.timestamp = block.timestamp;
        saveState(state, network);

        logPhaseComplete(6, 7);
    }

    // ============ Phase 7: Validation ============

    /**
     * @notice Phase 7 - Comprehensive validation of final state
     * @dev Verifies all state is consistent and correct
     */
    function phase7_Validation() internal {
        logPhaseHeader(7, 7, "Validation");

        bool allValidationsPassed = true;

        // 1. Verify campaign is closed
        console.log("Validating campaign state...");
        if (!verifyCampaignState(claimdrop, true)) {
            logError("Validation", "Campaign should be closed");
            allValidationsPassed = false;
        } else {
            console.log("Campaign state: PASS");
        }

        // 2. Verify allocations still exist
        console.log("");
        console.log("Validating allocations...");
        for (uint256 i = 0; i < testUsers.length; i++) {
            if (!verifyAllocation(claimdrop, testUsers[i], testAllocations[i])) {
                logError("Validation", string.concat("Allocation mismatch for user ", vm.toString(i)));
                allValidationsPassed = false;
            }
        }
        console.log("Allocations: PASS");

        // 3. Verify claimed users have token balances
        console.log("");
        console.log("Validating user balances...");
        uint256 claimCount = testUsers.length / 2;
        for (uint256 i = 0; i < claimCount; i++) {
            uint256 balance = token.balanceOf(testUsers[i]);
            if (balance == 0) {
                logError("Validation", string.concat("User ", vm.toString(i), " should have non-zero balance"));
                allValidationsPassed = false;
            } else {
                console.log("  User", i);
                console.log("    Balance:", balance / 1e18, "OM");
            }
        }

        // 4. Verify unclaimed users have zero balance
        console.log("");
        console.log("Validating unclaimed users...");
        for (uint256 i = claimCount; i < testUsers.length; i++) {
            uint256 balance = token.balanceOf(testUsers[i]);
            if (balance != 0) {
                logError("Validation", string.concat("Unclaimed user ", vm.toString(i), " should have zero balance"));
                allValidationsPassed = false;
            }
        }
        console.log("Unclaimed users: PASS");

        // 5. Verify contract state
        console.log("");
        console.log("Validating contract state...");
        (,, , , uint256 totalReward,,, uint256 claimed, uint64 closedAt,) = claimdrop.campaign();
        console.log("  Total Reward:", totalReward / 1e18, "OM");
        console.log("  Total Claimed:", claimed / 1e18, "OM");
        console.log("  Campaign Closed:", closedAt != 0);

        if (allValidationsPassed) {
            console.log("");
            console.log("=== ALL VALIDATIONS PASSED ===");
        } else {
            console.log("");
            console.log("!!! SOME VALIDATIONS FAILED !!!");
        }

        // Update state
        state.lastCompletedPhase = 7;
        state.timestamp = block.timestamp;
        saveState(state, network);

        require(allValidationsPassed, "Validation failed - check logs for details");

        logPhaseComplete(7, 7);
    }

    // ============ Report Generation ============

    /**
     * @notice Generate comprehensive markdown report
     * @dev Creates detailed report with all transaction details and results
     */
    function generateFinalReport() internal {
        console.log("");
        console.log("Generating final report...");

        string memory report = generateReportHeader(network);

        // Contract Addresses
        report = string.concat(
            report,
            "## Deployed Contracts\n\n",
            "- **Claimdrop:** ",
            formatExplorerLink(network, address(claimdrop)),
            "\n",
            "- **Reward Token:** ",
            formatExplorerLink(network, address(token)),
            "\n\n"
        );

        // Campaign Configuration
        (
            string memory name,
            ,
            ,
            ,
            uint256 totalReward,
            uint64 startTime,
            uint64 endTime,
            uint256 claimed,
            uint64 closedAt,
        ) = claimdrop.campaign();
        report = string.concat(
            report,
            "## Campaign Configuration\n\n",
            "- **Name:** ",
            name,
            "\n",
            "- **Total Reward:** ",
            vm.toString(totalReward / 1e18),
            " OM\n",
            "- **Start Time:** ",
            vm.toString(startTime),
            "\n",
            "- **End Time:** ",
            vm.toString(endTime),
            "\n",
            "- **Total Claimed:** ",
            vm.toString(claimed / 1e18),
            " OM\n",
            "- **Closed At:** ",
            vm.toString(closedAt),
            "\n\n"
        );

        // Test Users Summary
        report = string.concat(
            report,
            "## Test Users\n\n",
            "Generated ",
            vm.toString(testUsers.length),
            " test users with allocations:\n\n"
        );

        for (uint256 i = 0; i < testUsers.length && i < 5; i++) {
            report = string.concat(
                report,
                "- User ",
                vm.toString(i),
                ": ",
                vm.toString(testUsers[i]),
                " -> ",
                vm.toString(testAllocations[i] / 1e18),
                " OM\n"
            );
        }

        report = string.concat(report, "\n*(Showing first 5 users)*\n\n");

        // Execution Summary
        uint256 duration = block.timestamp - startTimestamp;
        report = string.concat(
            report,
            "## Execution Summary\n\n",
            "- **Total Duration:** ",
            vm.toString(duration),
            " seconds (", vm.toString(duration / 60),
            " minutes )\n",
            "- **Phases Completed:** 7/7\n",
            "- **Status:** Success\n\n"
        );

        // Write report to file
        string memory reportPath = getReportFilePath(network);
        vm.writeFile(reportPath, report);

        console.log("Report generated:", reportPath);
    }

    // ============ Helper Functions ============

    /**
     * @notice Get deployer address based on environment
     * @return deployer Address of deployer
     */
    function getDeployer() internal view returns (address deployer) {
        if (network.chainId == 31337) {
            // Local: Use default Anvil account
            // In script context, msg.sender is already set by forge
            return msg.sender;
        } else {
            // Testnet: Derive from PRIVATE_KEY
            uint256 privateKey = vm.envUint("PRIVATE_KEY");
            return vm.addr(privateKey);
        }
    }
}
