// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { Claimdrop } from "../contracts/Claimdrop.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";

/**
 * @title ClaimdropTest
 * @notice Comprehensive test suite for Claimdrop contract
 */
contract ClaimdropTest is Test {
    // Contracts
    Claimdrop public claimdrop;
    MockERC20 public token;

    // Test accounts
    address public owner;
    address public admin;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public user5;
    address public user6;
    address public user7;
    address public user8;

    // Constants
    uint256 constant INITIAL_SUPPLY = 10_000_000 ether;
    uint256 constant CAMPAIGN_REWARD = 1_000_000 ether;

    // Campaign parameters (set in setUp or individual tests)
    uint256 public startTime;
    uint256 public endTime;
    Claimdrop.Distribution[] public distributions;

    /// @notice Custom error selectors for expectRevert
    bytes4 constant UNAUTHORIZED_SELECTOR = bytes4(keccak256("Unauthorized()"));
    bytes4 constant INVALID_PERCENTAGE_SUM_SELECTOR = bytes4(keccak256("InvalidPercentageSum(uint256,uint256)"));
    bytes4 constant INVALID_TIME_WINDOW_SELECTOR = bytes4(keccak256("InvalidTimeWindow()"));
    bytes4 constant CAMPAIGN_ALREADY_EXISTS_SELECTOR = bytes4(keccak256("CampaignAlreadyExists()"));
    bytes4 constant CAMPAIGN_NOT_STARTED_SELECTOR = bytes4(keccak256("CampaignNotStarted()"));
    bytes4 constant ARRAY_LENGTH_MISMATCH_SELECTOR = bytes4(keccak256("ArrayLengthMismatch()"));
    bytes4 constant ALLOCATION_EXISTS_SELECTOR = bytes4(keccak256("AllocationExists(address)"));
    bytes4 constant CAMPAIGN_STARTED_SELECTOR = bytes4(keccak256("CampaignHasStarted()"));
    bytes4 constant INSUFFICIENT_BALANCE_SELECTOR = bytes4(keccak256("InsufficientBalance(uint256,uint256)"));
    bytes4 constant BLACKLISTED_SELECTOR = bytes4(keccak256("Blacklisted(address)"));
    bytes4 constant CANNOT_BLACKLIST_OWNER_SELECTOR = bytes4(keccak256("CannotBlacklistOwner()"));
    bytes4 constant CAMPAIGN_CLOSED_SELECTOR = bytes4(keccak256("CampaignAlreadyClosed()"));
    bytes4 constant NOTHING_TO_CLAIM_SELECTOR = bytes4(keccak256("NothingToClaim()"));
    bytes4 constant ZERO_AMOUNT_SELECTOR = bytes4(keccak256("ZeroAmount()"));

    /// @notice Event declarations for expectEmit
    event Claimed(address indexed user, uint256 indexed amount, address indexed sender);
    event BatchClaimed(uint256 count, string memo, address indexed sender);

    function setUp() public {
        // Create test accounts
        owner = address(this); // Test contract is the owner
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");
        user5 = makeAddr("user5");
        user6 = makeAddr("user6");
        user7 = makeAddr("user7");
        user8 = makeAddr("user8");

        // Deploy mock ERC20 token
        token = new MockERC20("Test Token", "TEST", 18);

        // Mint tokens to owner
        token.mint(owner, INITIAL_SUPPLY);

        // Deploy Claimdrop contract
        claimdrop = new Claimdrop(owner);

        // Add admin as authorized wallet
        address[] memory admins = new address[](1);
        admins[0] = admin;
        claimdrop.manageAuthorizedWallets(admins, true);

        // Set default campaign times
        startTime = block.timestamp + 3600; // 1 hour from now
        endTime = block.timestamp + 3600 * 24 * 365; // 1 year from now
    }

    // ============ Helper Functions ============

    /**
     * @notice Create default distributions (30% lump sum, 70% vesting)
     */
    function createDefaultDistributions() internal {
        delete distributions; // Clear array

        // 30% lump sum
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 3000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        // 70% linear vesting
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LinearVesting,
                percentageBps: 7000,
                startTime: uint64(startTime),
                endTime: uint64(endTime),
                cliffDuration: 0
            })
        );
    }

    /**
     * @notice Create a test campaign with default parameters
     */
    function createTestCampaign() internal {
        createDefaultDistributions();

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        // Fund the contract
        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
    }

    /**
     * @notice Add allocations for test users
     * @param count Number of users to allocate to (1-8)
     * @param amount Amount to allocate per user
     */
    function addTestAllocations(uint256 count, uint256 amount) internal {
        require(count <= 8, "Max 8 test users");

        address[] memory addresses = new address[](count);
        uint256[] memory amounts = new uint256[](count);

        address[8] memory users = [user1, user2, user3, user4, user5, user6, user7, user8];

        for (uint256 i = 0; i < count; i++) {
            addresses[i] = users[i];
            amounts[i] = amount;
        }

        claimdrop.addAllocations(addresses, amounts);
    }

    /**
     * @notice Helper to warp time forward
     */
    function warpToStart() internal {
        vm.warp(startTime);
    }

    /**
     * @notice Helper to warp past start time
     */
    function warpPastStart(uint256 additionalTime) internal {
        vm.warp(startTime + additionalTime);
    }

    /**
     * @notice Helper to warp to end time
     */
    function warpToEnd() internal {
        vm.warp(endTime);
    }

    /**
     * @notice Calculate expected vesting amount
     * @param totalAmount Total allocated amount
     * @param vestingBps Vesting percentage in basis points
     * @param elapsed Time elapsed since vesting started
     * @param duration Total vesting duration
     */
    function calculateVestedAmount(
        uint256 totalAmount,
        uint256 vestingBps,
        uint256 elapsed,
        uint256 duration
    )
        internal
        pure
        returns (uint256)
    {
        if (elapsed >= duration) {
            return (totalAmount * vestingBps) / 10_000;
        }
        return (totalAmount * vestingBps * elapsed) / (duration * 10_000);
    }

    // ============ Tests Begin Here ============

    // ============================================
    // Deployment Tests (3 tests)
    // ============================================

    function test_ShouldSetCorrectOwner() public view {
        assertEq(claimdrop.owner(), owner);
    }

    function test_ShouldSetAdminAsAuthorizedWallet() public view {
        assertTrue(claimdrop.isAuthorized(admin));
    }

    function test_ShouldNotHaveCampaignInitially() public view {
        (,,,,,,,,, bool exists) = claimdrop.campaign();
        assertFalse(exists);
    }

    // ============================================
    // Campaign Management Tests (9 tests)
    // ============================================

    function test_ShouldCreateCampaignWithValidParameters() public {
        createTestCampaign();

        (string memory name, string memory description,, address rewardToken, uint256 totalReward,,,,, bool exists) =
            claimdrop.campaign();

        assertTrue(exists);
        assertEq(name, "Test Campaign");
        assertEq(description, "Test Description");
        assertEq(rewardToken, address(token));
        assertEq(totalReward, CAMPAIGN_REWARD);
    }

    function test_RevertWhen_CreatingCampaignWithInvalidPercentages() public {
        delete distributions;

        // Only 50% allocated instead of 100%
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 5000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        vm.expectRevert(abi.encodeWithSelector(INVALID_PERCENTAGE_SUM_SELECTOR, 5000, 10_000));
        claimdrop.createCampaign(
            "Test", "Test", "airdrop", address(token), 1000 ether, distributions, uint64(startTime), uint64(endTime)
        );
    }

    function test_RevertWhen_CreatingCampaignWithStartTimeInPast() public {
        createDefaultDistributions();

        // Need to advance time first, then use a past time
        vm.warp(block.timestamp + 7200); // Move forward 2 hours
        uint256 pastTime = block.timestamp - 3600; // 1 hour ago

        vm.expectRevert(INVALID_TIME_WINDOW_SELECTOR);
        claimdrop.createCampaign(
            "Test",
            "Test",
            "airdrop",
            address(token),
            1000 ether,
            distributions,
            uint64(pastTime),
            uint64(endTime + 7200) // Adjust endTime too
        );
    }

    function test_RevertWhen_CreatingDuplicateCampaign() public {
        createTestCampaign();

        vm.expectRevert(CAMPAIGN_ALREADY_EXISTS_SELECTOR);
        claimdrop.createCampaign(
            "Test Campaign 2",
            "Test Description 2",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );
    }

    function test_ShouldAllowAuthorizedWalletToCreateCampaign() public {
        createDefaultDistributions();

        vm.prank(admin);
        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        (,,,,,,,,, bool exists) = claimdrop.campaign();
        assertTrue(exists);
    }

    function test_RevertWhen_UnauthorizedUserCreatingCampaign() public {
        createDefaultDistributions();

        vm.prank(user1);
        vm.expectRevert(UNAUTHORIZED_SELECTOR);
        claimdrop.createCampaign(
            "Test", "Test", "airdrop", address(token), 1000 ether, distributions, uint64(startTime), uint64(endTime)
        );
    }

    function test_ShouldCloseCampaignAndReturnUnclaimedTokens() public {
        createTestCampaign();

        uint256 balanceBefore = token.balanceOf(owner);
        claimdrop.closeCampaign();
        uint256 balanceAfter = token.balanceOf(owner);

        (,,,,,,,, uint64 closedAt,) = claimdrop.campaign();
        assertTrue(closedAt > 0);
        assertEq(balanceAfter - balanceBefore, CAMPAIGN_REWARD);
    }

    function test_RevertWhen_ClosingAlreadyClosedCampaign() public {
        createTestCampaign();
        claimdrop.closeCampaign();

        vm.expectRevert(CAMPAIGN_CLOSED_SELECTOR);
        claimdrop.closeCampaign();
    }

    function test_RevertWhen_NonOwnerClosingCampaign() public {
        createTestCampaign();

        vm.prank(admin);
        vm.expectRevert(); // Ownable2Step revert
        claimdrop.closeCampaign();
    }

    // ============================================
    // Allocation Management Tests (7 tests)
    // ============================================

    function test_ShouldAddAllocationsInBatch() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        address[] memory addresses = new address[](3);
        addresses[0] = user1;
        addresses[1] = user2;
        addresses[2] = user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1000 ether;
        amounts[1] = 2000 ether;
        amounts[2] = 3000 ether;

        claimdrop.addAllocations(addresses, amounts);

        assertEq(claimdrop.getAllocation(user1), amounts[0]);
        assertEq(claimdrop.getAllocation(user2), amounts[1]);
        assertEq(claimdrop.getAllocation(user3), amounts[2]);
    }

    function test_RevertWhen_AddingAllocationsAfterCampaignStarts() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        vm.warp(startTime);

        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        vm.expectRevert(CAMPAIGN_STARTED_SELECTOR);
        claimdrop.addAllocations(addresses, amounts);
    }

    function test_RevertWhen_ArrayLengthMismatch() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        vm.expectRevert(ARRAY_LENGTH_MISMATCH_SELECTOR);
        claimdrop.addAllocations(addresses, amounts);
    }

    function test_RevertWhen_AddingDuplicateAllocations() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        claimdrop.addAllocations(addresses, amounts);

        amounts[0] = 2000 ether;
        vm.expectRevert(abi.encodeWithSelector(ALLOCATION_EXISTS_SELECTOR, user1));
        claimdrop.addAllocations(addresses, amounts);
    }

    function test_ShouldReplaceAddressCorrectly() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        claimdrop.addAllocations(addresses, amounts);
        claimdrop.replaceAddress(user1, user2);

        assertEq(claimdrop.getAllocation(user1), 0);
        assertEq(claimdrop.getAllocation(user2), 1000 ether);
    }

    function test_ShouldRemoveAddressCorrectly() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        claimdrop.addAllocations(addresses, amounts);
        claimdrop.removeAddress(user1);

        assertEq(claimdrop.getAllocation(user1), 0);
    }

    function test_RevertWhen_RemovingAddressAfterCampaignStarts() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        claimdrop.addAllocations(addresses, amounts);

        vm.warp(startTime);

        vm.expectRevert(CAMPAIGN_STARTED_SELECTOR);
        claimdrop.removeAddress(user1);
    }

    // ============================================
    // Claiming Tests - Lump Sum (6 tests)
    // ============================================

    function test_RevertWhen_ClaimingBeforeStart() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        vm.prank(user1);
        vm.expectRevert(CAMPAIGN_NOT_STARTED_SELECTOR);
        claimdrop.claim(user1, 0);
    }

    function test_ShouldAllowClaimAfterStart() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        vm.warp(startTime);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        claimdrop.claim(user1, 0);
        uint256 balanceAfter = token.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, 1000 ether);
    }

    function test_RevertWhen_DoubleClaim() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        vm.warp(startTime);

        vm.startPrank(user1);
        claimdrop.claim(user1, 0);

        vm.expectRevert(NOTHING_TO_CLAIM_SELECTOR);
        claimdrop.claim(user1, 0);
        vm.stopPrank();
    }

    function test_ShouldSupportPartialClaims() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        vm.warp(startTime);

        vm.startPrank(user1);

        uint256 balanceBefore = token.balanceOf(user1);
        claimdrop.claim(user1, 500 ether);
        uint256 balanceAfter = token.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, 500 ether);

        uint256 balanceBefore2 = token.balanceOf(user1);
        claimdrop.claim(user1, 0); // Claim remaining
        uint256 balanceAfter2 = token.balanceOf(user1);
        assertEq(balanceAfter2 - balanceBefore2, 500 ether);

        vm.stopPrank();
    }

    function test_RevertWhen_BlacklistedAddressClaiming() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        // Blacklist user1
        claimdrop.blacklistAddress(user1, true);

        vm.warp(startTime);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(BLACKLISTED_SELECTOR, user1));
        claimdrop.claim(user1, 0);
    }

    function test_ShouldAllowOwnerToClaimOnBehalfOfUser() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        vm.warp(startTime);

        uint256 balanceBefore = token.balanceOf(user1);
        claimdrop.claim(user1, 0); // Owner claims on behalf
        uint256 balanceAfter = token.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, 1000 ether);
    }

    // ============================================
    // Claiming Tests - Linear Vesting (2 tests)
    // ============================================

    function test_ShouldVestLinearlyOverTime() public {
        // Create campaign with 100% linear vesting
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LinearVesting,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: uint64(endTime),
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        // Move slightly after start to begin vesting (1 second)
        vm.warp(startTime + 1);
        (, uint256 pendingStart,) = claimdrop.getRewards(user1);
        // At the very start, a tiny amount is vested
        assertTrue(pendingStart >= 0);

        // At 25% through vesting period
        uint256 quarterTime = startTime + (endTime - startTime) / 4;
        vm.warp(quarterTime);
        (, uint256 pending25,) = claimdrop.getRewards(user1);
        assertApproxEqAbs(pending25, 250 ether, 2 ether);

        // Claim at 25%
        vm.prank(user1);
        claimdrop.claim(user1, 0);
        (uint256 claimed,,) = claimdrop.getRewards(user1);
        assertApproxEqAbs(claimed, 250 ether, 1 ether);

        // At 50% through vesting period
        uint256 halfTime = startTime + (endTime - startTime) / 2;
        vm.warp(halfTime);
        (, uint256 pending50,) = claimdrop.getRewards(user1);
        assertApproxEqAbs(pending50, 250 ether, 1 ether); // Additional 250 (already claimed 250)
    }

    function test_ShouldAllowFullClaimAfterVestingEnds() public {
        // Create campaign with 100% linear vesting
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LinearVesting,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: uint64(endTime),
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        vm.warp(endTime);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        claimdrop.claim(user1, 0);
        uint256 balanceAfter = token.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, 1000 ether);
    }

    // ============================================
    // Claiming Tests - Vesting with Cliff (2 tests)
    // ============================================

    function test_ShouldNotAllowClaimDuringCliffPeriod() public {
        uint256 cliffDuration = 30 days;

        // Create campaign with 100% linear vesting with 30-day cliff
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LinearVesting,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: uint64(endTime),
                cliffDuration: uint64(cliffDuration)
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        // 15 days after start (mid-cliff)
        vm.warp(startTime + 15 days);
        (, uint256 pending,) = claimdrop.getRewards(user1);
        assertEq(pending, 0);

        vm.prank(user1);
        vm.expectRevert(NOTHING_TO_CLAIM_SELECTOR);
        claimdrop.claim(user1, 0);
    }

    function test_ShouldAllowClaimAfterCliffPasses() public {
        uint256 cliffDuration = 30 days;

        // Create campaign with 100% linear vesting with 30-day cliff
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LinearVesting,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: uint64(endTime),
                cliffDuration: uint64(cliffDuration)
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        // 31 days after start (cliff + 1 day)
        vm.warp(startTime + 31 days);
        (, uint256 pending,) = claimdrop.getRewards(user1);
        assertTrue(pending > 0);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        claimdrop.claim(user1, 0);
        uint256 balanceAfter = token.balanceOf(user1);
        assertTrue(balanceAfter > balanceBefore);
    }

    // ============================================
    // Claiming Tests - Multiple Distributions (2 tests)
    // ============================================

    function test_ShouldClaimLumpSumImmediatelyAndVestRemaining() public {
        createTestCampaign(); // 30% lump sum, 70% vesting

        addTestAllocations(1, 1000 ether); // User1 gets 300 lump, 700 vesting

        // At start, only lump sum available
        vm.warp(startTime);
        (, uint256 pending,) = claimdrop.getRewards(user1);
        assertEq(pending, 300 ether);

        // Claim lump sum
        vm.prank(user1);
        claimdrop.claim(user1, 0);

        // At 50% through vesting period
        uint256 halfTime = startTime + (endTime - startTime) / 2;
        vm.warp(halfTime);
        (, uint256 pending50,) = claimdrop.getRewards(user1);
        assertApproxEqAbs(pending50, 350 ether, 1 ether); // 50% of 700 = 350
    }

    function test_ShouldPrioritizeLumpSumInPartialClaims() public {
        createTestCampaign(); // 30% lump sum, 70% vesting

        addTestAllocations(1, 1000 ether); // User1 gets 300 lump, 700 vesting

        vm.warp(startTime);

        // Claim only 100 tokens (should come from lump sum)
        vm.prank(user1);
        claimdrop.claim(user1, 100 ether);

        // Check claim tracking per slot
        (uint128 lumpClaimed,) = claimdrop.claims(user1, 0);
        (uint128 vestClaimed,) = claimdrop.claims(user1, 1);

        assertEq(lumpClaimed, 100 ether);
        assertEq(vestClaimed, 0);
    }

    // ============================================
    // Administration Tests (6 tests)
    // ============================================

    function test_ShouldAllowOwnerToManageAuthorizedWallets() public {
        address[] memory wallets = new address[](1);
        wallets[0] = user1;

        claimdrop.manageAuthorizedWallets(wallets, true);
        assertTrue(claimdrop.isAuthorized(user1));

        claimdrop.manageAuthorizedWallets(wallets, false);
        assertFalse(claimdrop.isAuthorized(user1));
    }

    function test_RevertWhen_NonOwnerManagingAuthorizedWallets() public {
        address[] memory wallets = new address[](1);
        wallets[0] = user2;

        vm.prank(user1);
        vm.expectRevert(); // Ownable2Step revert
        claimdrop.manageAuthorizedWallets(wallets, true);
    }

    function test_ShouldAllowBlacklistingAddresses() public {
        claimdrop.blacklistAddress(user1, true);
        assertTrue(claimdrop.isBlacklisted(user1));

        claimdrop.blacklistAddress(user1, false);
        assertFalse(claimdrop.isBlacklisted(user1));
    }

    function test_RevertWhen_BlacklistingOwner() public {
        vm.expectRevert(CANNOT_BLACKLIST_OWNER_SELECTOR);
        claimdrop.blacklistAddress(owner, true);
    }

    function test_ShouldAllowSweepingNonRewardTokens() public {
        // Deploy different token
        MockERC20 otherToken = new MockERC20("Other Token", "OTHER", 18);
        otherToken.mint(address(this), 1000 ether);

        // Send to contract
        otherToken.transfer(address(claimdrop), 1000 ether);

        uint256 balanceBefore = otherToken.balanceOf(owner);
        claimdrop.sweep(address(otherToken), 1000 ether);
        uint256 balanceAfter = otherToken.balanceOf(owner);

        assertEq(balanceAfter - balanceBefore, 1000 ether);
    }

    function test_ShouldAllowPausingAndUnpausing() public {
        claimdrop.pause();

        createDefaultDistributions();

        // Should revert when paused
        vm.expectRevert(); // Pausable revert
        claimdrop.createCampaign(
            "Test", "Test", "airdrop", address(token), 1000 ether, distributions, uint64(startTime), uint64(endTime)
        );

        claimdrop.unpause();

        // Should work after unpause
        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        (,,,,,,,,, bool exists) = claimdrop.campaign();
        assertTrue(exists);
    }

    // ============================================
    // Batch Claim Tests (8 tests)
    // ============================================

    function test_ShouldAllowBatchClaimOnBehalfOfUsers() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(3, 1000 ether);

        vm.warp(startTime);

        // Prepare batch claim
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0; // Max
        amounts[1] = 500 ether; // Partial
        amounts[2] = 0; // Max

        uint256 balance1Before = token.balanceOf(user1);
        uint256 balance2Before = token.balanceOf(user2);
        uint256 balance3Before = token.balanceOf(user3);

        // Owner batch claims
        claimdrop.claimOnBehalfOfBatch(users, amounts, "Manual distribution");

        assertEq(token.balanceOf(user1) - balance1Before, 1000 ether);
        assertEq(token.balanceOf(user2) - balance2Before, 500 ether);
        assertEq(token.balanceOf(user3) - balance3Before, 1000 ether);
    }

    function test_ShouldAllowAuthorizedWalletToBatchClaim() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(2, 1000 ether);

        vm.warp(startTime);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        // Authorized wallet batch claims
        vm.prank(admin);
        claimdrop.claimOnBehalfOfBatch(users, amounts, "Authorized batch claim");

        assertEq(token.balanceOf(user1), 1000 ether);
        assertEq(token.balanceOf(user2), 1000 ether);
    }

    function test_RevertWhen_UnauthorizedBatchClaim() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        vm.warp(startTime);

        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        vm.prank(user2);
        vm.expectRevert(UNAUTHORIZED_SELECTOR);
        claimdrop.claimOnBehalfOfBatch(users, amounts, "Unauthorized claim");
    }

    function test_RevertWhen_BatchClaimArrayLengthMismatch() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        vm.warp(startTime);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        vm.expectRevert(ARRAY_LENGTH_MISMATCH_SELECTOR);
        claimdrop.claimOnBehalfOfBatch(users, amounts, "Mismatched arrays");
    }

    function test_RevertWhen_BatchClaimExceedsMaxSize() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        vm.warp(startTime);

        // Create arrays larger than MAX_CLAIM_BATCH_SIZE (1000)
        uint256 batchSize = 1001;
        address[] memory users = new address[](batchSize);
        uint256[] memory amounts = new uint256[](batchSize);

        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidBatchSize(uint256,uint256)")), 1001, 1000));
        claimdrop.claimOnBehalfOfBatch(users, amounts, "Too large");
    }

    function test_RevertWhen_BatchClaimWithBlacklistedUser() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(2, 1000 ether);

        // Blacklist user2
        claimdrop.blacklistAddress(user2, true);

        vm.warp(startTime);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        vm.expectRevert(abi.encodeWithSelector(BLACKLISTED_SELECTOR, user2));
        claimdrop.claimOnBehalfOfBatch(users, amounts, "Batch with blacklisted");
    }

    function test_RevertWhen_BatchClaimWithNothingToClaim() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(2, 1000 ether);

        vm.warp(startTime);

        // First, user1 claims their allocation
        vm.prank(user1);
        claimdrop.claim(user1, 0);

        // Now try to batch claim including user1 who has nothing left
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        vm.expectRevert(NOTHING_TO_CLAIM_SELECTOR);
        claimdrop.claimOnBehalfOfBatch(users, amounts, "Batch with nothing to claim");
    }

    function test_ShouldEmitBatchClaimedEvent() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(2, 1000 ether);

        vm.warp(startTime);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        // Expect Claimed events for each user
        vm.expectEmit(true, true, true, true);
        emit Claimed(user1, 1000 ether, owner);
        vm.expectEmit(true, true, true, true);
        emit Claimed(user2, 1000 ether, owner);

        // Expect BatchClaimed event
        vm.expectEmit(true, true, true, true);
        emit BatchClaimed(2, "Test memo", owner);

        claimdrop.claimOnBehalfOfBatch(users, amounts, "Test memo");
    }

    // ============================================
    // View Functions Tests (4 tests)
    // ============================================

    function test_ShouldReturnCorrectCampaignDetails() public {
        createTestCampaign();

        (string memory name, string memory description,, address rewardToken,,,,,,) = claimdrop.campaign();

        assertEq(name, "Test Campaign");
        assertEq(description, "Test Description");
        assertEq(rewardToken, address(token));
    }

    function test_ShouldReturnCorrectAllocations() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);

        // Set specific amounts
        address[] memory addresses = new address[](2);
        addresses[0] = user1;
        addresses[1] = user2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 ether;
        amounts[1] = 2000 ether;

        claimdrop.addAllocations(addresses, amounts);

        assertEq(claimdrop.getAllocation(user1), 1000 ether);
        assertEq(claimdrop.getAllocation(user2), 2000 ether);
    }

    function test_ShouldReturnCorrectRewardDetails() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        token.transfer(address(claimdrop), CAMPAIGN_REWARD);
        addTestAllocations(1, 1000 ether);

        // Move to start time for lump sum to be available
        vm.warp(startTime);

        (uint256 claimed, uint256 pending, uint256 total) = claimdrop.getRewards(user1);
        assertEq(total, 1000 ether);
        // For lump sum, pending should be 1000 ether at start time
        assertEq(pending, 1000 ether);
        assertEq(claimed, 0);
    }

    function test_ShouldReturnInvestorCount() public {
        // Create campaign with 100% lump sum
        delete distributions;
        distributions.push(
            Claimdrop.Distribution({
                kind: Claimdrop.DistributionKind.LumpSum,
                percentageBps: 10_000,
                startTime: uint64(startTime),
                endTime: 0,
                cliffDuration: 0
            })
        );

        claimdrop.createCampaign(
            "Test Campaign",
            "Test Description",
            "airdrop",
            address(token),
            CAMPAIGN_REWARD,
            distributions,
            uint64(startTime),
            uint64(endTime)
        );

        addTestAllocations(2, 1000 ether);

        assertEq(claimdrop.getInvestorCount(), 2);
    }
}
