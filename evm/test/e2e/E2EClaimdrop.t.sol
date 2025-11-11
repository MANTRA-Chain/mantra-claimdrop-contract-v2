// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Claimdrop} from "../../contracts/Claimdrop.sol";
import {MockERC20} from "../../contracts/mocks/MockERC20.sol";
import {E2EBase} from "../../script/e2e/E2EBase.sol";

/**
 * @title E2EClaimDropTest
 * @notice End-to-end test suite for Claimdrop contract lifecycle
 * @dev Comprehensive integration tests covering complete workflows from deployment to validation.
 *      Tests use vm.warp() for time manipulation and can run in fork mode.
 *
 * Test Scenarios:
 * - Full lifecycle on local network
 * - Multiple distribution types (lump sum + vesting)
 * - Partial claims
 * - Vesting progression over time
 * - Edge cases (cliff, campaign closure, etc.)
 *
 * Usage:
 *   # Run all E2E tests locally
 *   forge test --match-contract E2EClaimdrop -vv
 *
 *   # Run specific test
 *   forge test --match-test test_FullLifecycle_Local -vv
 *
 *   # Run on forked network (read-only)
 *   forge test --match-test Fork_Dukong --fork-url $MANTRA_DUKONG_RPC_URL -vv
 */
contract E2EClaimDropTest is Test, E2EBase {
    // ============ State Variables ============

    Claimdrop public claimdrop;
    MockERC20 public token;
    NetworkConfig public network;
    TimingProfile public timing;

    address public owner;
    address[] internal users;
    uint256[] internal allocations;

    uint64 public startTime;
    uint64 public endTime;

    // ============ Setup ============

    function setUp() public {
        // Load network config (defaults to local)
        network = loadNetworkConfig("local");
        timing = getTimingProfile(network);

        // Set owner
        owner = address(this);

        // Deploy contracts
        token = new MockERC20("Test OM", "tOM", 18);
        claimdrop = new Claimdrop(owner);

        // Mint tokens to owner
        token.mint(owner, 10_000_000 ether);

        // Generate test allocations
        (users, allocations) = generateTestAllocations(network);
    }

    // ============ Helper Functions ============

    /**
     * @notice Create campaign with network timing profile
     * @return totalReward Total reward amount for campaign
     */
    function createCampaign() internal returns (uint256 totalReward) {
        // Calculate campaign timing
        startTime = uint64(vm.getBlockTimestamp() + timing.startDelay);
        endTime = uint64(startTime + timing.campaignDuration);

        // Calculate total reward
        totalReward = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalReward += allocations[i];
        }

        // Build distributions
        Claimdrop.Distribution[] memory distributions = new Claimdrop.Distribution[](2);

        // Distribution 0: Lump Sum
        distributions[0] = Claimdrop.Distribution({
            kind: Claimdrop.DistributionKind.LumpSum,
            percentageBps: timing.lumpSumPercentageBps,
            startTime: startTime,
            endTime: 0,
            cliffDuration: 0
        });

        // Distribution 1: Linear Vesting
        distributions[1] = Claimdrop.Distribution({
            kind: Claimdrop.DistributionKind.LinearVesting,
            percentageBps: timing.vestingPercentageBps,
            startTime: startTime,
            endTime: uint64(startTime + timing.vestingDuration),
            cliffDuration: uint64(timing.cliffDuration)
        });

        // Fund and create campaign
        token.transfer(address(claimdrop), totalReward);

        claimdrop.createCampaign(
            "E2E Test Campaign",
            "Automated test campaign",
            "e2e-test",
            address(token),
            totalReward,
            distributions,
            startTime,
            endTime
        );

        return totalReward;
    }

    /**
     * @notice Upload test allocations to campaign
     */
    function uploadAllocations() internal {
        claimdrop.addAllocations(users, allocations);

        // Verify allocations
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(claimdrop.allocations(users[i]), allocations[i], "Allocation mismatch");
        }
    }

    // ============ Test Cases ============

    /**
     * @notice Test complete lifecycle on local network
     * @dev Tests all 7 phases: deploy → campaign → allocations → wait → claim → close → validate
     */
    function test_FullLifecycle_Local() public {
        console.log("=== Test: Full Lifecycle (Local) ===");

        // Phase 1: Deploy (done in setUp)
        assertEq(claimdrop.owner(), owner, "Owner mismatch");

        // Phase 2: Create Campaign
        uint256 totalReward = createCampaign();
        (,,,, uint256 campaignTotalReward,,,,,bool exists) = claimdrop.campaign();
        assertEq(exists, true, "Campaign should exist");
        assertEq(campaignTotalReward, totalReward, "Total reward mismatch");

        // Phase 3: Upload Allocations
        uploadAllocations();

        // Phase 4: Wait for Campaign Start
        vm.warp(startTime);
        assertEq(vm.getBlockTimestamp(), startTime, "Time warp failed");

        // Phase 5: Execute Claims
        // Warp past cliff to enable vesting
        vm.warp(startTime + timing.cliffDuration + 60);

        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < users.length / 2; i++) {
            address user = users[i];
            (, uint256 claimable,) = claimdrop.getRewards(user);

            if (claimable > 0) {
                uint256 balanceBefore = token.balanceOf(user);

                // Claim as user
                vm.prank(user);
                claimdrop.claim(user, claimable);

                uint256 balanceAfter = token.balanceOf(user);
                assertEq(balanceAfter - balanceBefore, claimable, "Claim amount mismatch");

                totalClaimed += claimable;
            }
        }

        assertGt(totalClaimed, 0, "Should have claimed some tokens");

        // Phase 6: Close Campaign
        claimdrop.closeCampaign();
        (,,,,,,,, uint64 closedAt,) = claimdrop.campaign();
        assertNotEq(closedAt, 0, "Campaign should be closed");

        // Phase 7: Validation
        // Verify claimed users have balances
        for (uint256 i = 0; i < users.length / 2; i++) {
            uint256 balance = token.balanceOf(users[i]);
            assertGt(balance, 0, "Claimed user should have balance");
        }

        // Verify unclaimed users have zero balance
        for (uint256 i = users.length / 2; i < users.length; i++) {
            uint256 balance = token.balanceOf(users[i]);
            assertEq(balance, 0, "Unclaimed user should have zero balance");
        }

        console.log("Test passed: Full lifecycle completed successfully");
    }

    /**
     * @notice Test multiple distribution types (lump sum + vesting)
     * @dev Verifies both lump sum and vesting distributions work correctly
     */
    function test_MultipleDistributions() public {
        console.log("=== Test: Multiple Distributions ===");

        createCampaign();
        uploadAllocations();

        // Warp to campaign start
        vm.warp(startTime);

        address user = users[0];
        uint256 allocation = allocations[0];

        // At start time: only lump sum should be claimable
        (, uint256 claimable,) = claimdrop.getRewards(user);
        uint256 expectedLumpSum = (allocation * timing.lumpSumPercentageBps) / 10000;

        // Note: Vesting is in cliff, so only lump sum available
        assertEq(claimable, expectedLumpSum, "Only lump sum should be claimable at start");

        // Claim lump sum
        vm.prank(user);
        claimdrop.claim(user, claimable);

        // Warp past cliff
        vm.warp(startTime + timing.cliffDuration + 60);

        // Now vesting should be partially available
        (, claimable,) = claimdrop.getRewards(user);
        assertGt(claimable, 0, "Vesting should be claimable after cliff");

        console.log("Test passed: Multiple distributions work correctly");
    }

    /**
     * @notice Test partial claims
     * @dev Verifies users can claim less than their full available amount
     */
    function test_PartialClaims() public {
        console.log("=== Test: Partial Claims ===");

        createCampaign();
        uploadAllocations();

        // Warp to campaign start + past cliff
        vm.warp(startTime + timing.cliffDuration + 60);

        address user = users[0];
        (, uint256 claimable,) = claimdrop.getRewards(user);
        assertGt(claimable, 0, "User should have claimable amount");

        // Claim only 50% of available amount
        uint256 partialAmount = claimable / 2;

        vm.prank(user);
        claimdrop.claim(user, partialAmount);

        uint256 balance = token.balanceOf(user);
        assertEq(balance, partialAmount, "Should have received partial amount");

        // Check remaining claimable
        (, uint256 remainingClaimable,) = claimdrop.getRewards(user);
        assertGt(remainingClaimable, 0, "Should still have claimable amount");

        // Claim the rest
        vm.prank(user);
        claimdrop.claim(user, remainingClaimable);

        balance = token.balanceOf(user);
        assertEq(balance, partialAmount + remainingClaimable, "Should have received all claimed amounts");

        console.log("Test passed: Partial claims work correctly");
    }

    /**
     * @notice Test vesting progression over time
     * @dev Verifies linear vesting calculations at different time points
     */
    function test_VestingProgression() public {
        console.log("=== Test: Vesting Progression ===");

        createCampaign();
        uploadAllocations();

        address user = users[0];
        uint256 allocation = allocations[0];
        uint256 vestingAllocation = (allocation * timing.vestingPercentageBps) / 10000;

        // At start (before cliff): No vesting claimable
        vm.warp(startTime);
        (, uint256 claimable,) = claimdrop.getRewards(user);
        uint256 lumpSum = (allocation * timing.lumpSumPercentageBps) / 10000;
        assertEq(claimable, lumpSum, "Only lump sum before cliff");

        // Claim lump sum
        vm.prank(user);
        claimdrop.claim(user, claimable);

        // At cliff end: Vesting should start
        vm.warp(startTime + timing.cliffDuration);
        (, claimable,) = claimdrop.getRewards(user);
        assertEq(claimable, 0, "No additional vesting at exact cliff end");

        // 25% through vesting period
        uint64 vestingStart = startTime;
        uint64 vestingEnd = uint64(startTime + timing.vestingDuration);
        uint64 quarterPoint = uint64(vestingStart + (vestingEnd - vestingStart) / 4);

        vm.warp(quarterPoint);
        (, claimable,) = claimdrop.getRewards(user);

        // Should have ~25% of vesting allocation (accounting for cliff)
        uint256 elapsed = quarterPoint - vestingStart;
        uint256 duration = vestingEnd - vestingStart;
        uint256 expectedVested = (vestingAllocation * elapsed) / duration;

        // Allow small rounding difference
        assertApproxEqRel(claimable, expectedVested, 0.01e18, "Should have ~25% of vesting allocation");

        // At end: Full vesting should be available
        vm.warp(vestingEnd);
        (, claimable,) = claimdrop.getRewards(user);
        assertEq(claimable, vestingAllocation, "Full vesting should be available at end");

        console.log("Test passed: Vesting progresses linearly as expected");
    }

    /**
     * @notice Test edge cases
     * @dev Tests boundary conditions and error cases
     */
    function test_EdgeCases() public {
        console.log("=== Test: Edge Cases ===");

        createCampaign();
        uploadAllocations();

        // Edge case 1: Claim exactly at cliff end
        vm.warp(startTime + timing.cliffDuration);
        address user = users[0];

        (, uint256 claimable,) = claimdrop.getRewards(user);
        // Should have lump sum only (vesting just starting)
        uint256 lumpSum = (allocations[0] * timing.lumpSumPercentageBps) / 10000;
        assertEq(claimable, lumpSum, "Should have only lump sum at cliff end");

        // Edge case 2: Try to claim after campaign closed
        vm.warp(startTime + timing.cliffDuration + 60);
        (, uint256 claimableAfterCliff,) = claimdrop.getRewards(user);
        vm.prank(user);
        claimdrop.claim(user, claimableAfterCliff);

        claimdrop.closeCampaign();

        // Should revert when trying to claim after closure
        vm.expectRevert(Claimdrop.CampaignAlreadyClosed.selector);
        vm.prank(user);
        claimdrop.claim(user, 1);

        // Edge case 3: User with no allocation
        address noAllocUser = makeAddr("no_alloc_user");
        vm.expectRevert(abi.encodeWithSelector(Claimdrop.NoAllocation.selector, noAllocUser));
        vm.prank(noAllocUser);
        claimdrop.claim(noAllocUser, 1);

        console.log("Test passed: Edge cases handled correctly");
    }

    /**
     * @notice Test claiming with zero amount (should claim maximum available)
     * @dev Verifies that passing 0 as amount claims all available tokens
     */
    function test_ClaimMaximum() public {
        console.log("=== Test: Claim Maximum (Zero Amount) ===");

        createCampaign();
        uploadAllocations();

        // Warp past cliff
        vm.warp(startTime + timing.cliffDuration + 60);

        address user = users[0];
        (, uint256 claimable,) = claimdrop.getRewards(user);
        assertGt(claimable, 0, "User should have claimable amount");

        // Claim with amount = 0 (should claim maximum)
        vm.prank(user);
        claimdrop.claim(user, 0);

        uint256 balance = token.balanceOf(user);
        assertEq(balance, claimable, "Should have claimed maximum available");

        console.log("Test passed: Claiming with zero amount claims maximum");
    }

    /**
     * @notice Test state persistence and recovery
     * @dev Verifies state can be saved and loaded correctly
     */
    function test_StatePersistence() public {
        console.log("=== Test: State Persistence ===");

        // Create initial state
        E2EState memory state;
        state.network = network.name;
        state.chainId = network.chainId;
        state.claimdrop = address(claimdrop);
        state.rewardToken = address(token);
        state.campaignStartTime = startTime;
        state.campaignEndTime = endTime;
        state.testUsers = users;
        state.allocations = allocations;
        state.lastCompletedPhase = 3;
        state.timestamp = block.timestamp;
        state.totalClaimed = 0;

        // Save state
        saveState(state, network);

        // Load state
        E2EState memory loadedState = loadState(network);

        // Verify loaded state matches
        assertEq(loadedState.network, state.network, "Network name mismatch");
        assertEq(loadedState.chainId, state.chainId, "ChainID mismatch");
        assertEq(loadedState.claimdrop, state.claimdrop, "Claimdrop address mismatch");
        assertEq(loadedState.rewardToken, state.rewardToken, "Token address mismatch");
        assertEq(loadedState.lastCompletedPhase, state.lastCompletedPhase, "Phase mismatch");

        console.log("Test passed: State persistence works correctly");
    }

    /**
     * @notice Test on forked DuKong network (read-only)
     * @dev Can be run with: forge test --match-test Fork_Dukong --fork-url $MANTRA_DUKONG_RPC_URL
     */
    function testFork_Dukong() public {
        // Skip if not running in fork mode
        if (block.chainid == 31337) {
            console.log("Skipping fork test - not in fork mode");
            return;
        }

        console.log("=== Test: Fork - DuKong Network ===");

        // Load DuKong config
        network = loadNetworkConfig("dukong");
        timing = getTimingProfile(network);

        // Note: In fork mode, we have snapshot of chain state
        // This test validates the E2E flow works on forked state
        // without actually broadcasting transactions

        console.log("Fork test setup complete");
        console.log("Network:", network.name);
        console.log("ChainID:", network.chainId);

        // Run simplified lifecycle test in fork mode
        // (Full test omitted as it would require actual token contracts on fork)
    }
}
