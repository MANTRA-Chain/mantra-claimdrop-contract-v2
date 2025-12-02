// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Allowlist } from "@primary-sale/Allowlist.sol";

/**
 * @title Claimdrop
 * @author MANTRA Finance
 * @notice Token distribution contract with vesting capabilities
 * @dev Supports lump sum distributions and linear vesting with cliff periods
 *
 * FEATURES:
 * - Campaign management (create/close)
 * - Batch allocation uploads (up to 3000 per batch)
 * - Multiple distribution types (lump sum + linear vesting)
 * - Partial claims supported
 * - Cliff periods for vesting
 * - Blacklist functionality
 * - Authorized wallet management
 * - Rounding dust recovery
 * - Emergency pause functionality
 *
 * LIMITATIONS:
 * - Fee-on-transfer (FOT) tokens are NOT supported
 * - Rebasing tokens are NOT supported
 * - Only standard ERC20 tokens should be used as rewardToken
 *
 * SECURITY:
 * - Reentrancy protection on all external calls
 * - Owner protection (cannot be blacklisted)
 * - Two-step ownership transfer
 * - Pausable for emergency situations
 * - Comprehensive access control
 */
contract Claimdrop is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // ============ Constants ============

    /// @notice Maximum allocations per batch upload
    uint256 public constant MAX_ALLOCATION_BATCH_SIZE = 3000;

    /// @notice Maximum authorized wallets per batch operation
    uint256 public constant MAX_AUTHORIZED_WALLETS_BATCH_SIZE = 1000;

    /// @notice Maximum claims per batch operation
    uint256 public constant MAX_CLAIM_BATCH_SIZE = 1000;

    /// @notice Basis points representing 100%
    uint256 public constant BASIS_POINTS_TOTAL = 10_000;

    /// @notice Maximum campaign duration (10 years)
    uint256 public constant MAX_CAMPAIGN_DURATION = 365 days * 10;

    /// @notice Maximum number of distributions per campaign
    uint256 public constant MAX_DISTRIBUTIONS = 10;

    /// @notice Minimum percentage per distribution (1%)
    uint256 public constant MIN_DISTRIBUTION_BPS = 100;

    // ============ Enums ============

    /// @notice Type of distribution
    enum DistributionKind {
        LinearVesting, // Tokens vest linearly over time
        LumpSum // Tokens released at specific time

    }

    // ============ Structs ============

    /// @notice Distribution configuration
    struct Distribution {
        DistributionKind kind; // Type of distribution
        uint16 percentageBps; // Percentage in basis points (10000 = 100%)
        uint64 startTime; // Distribution start timestamp
        uint64 endTime; // Distribution end timestamp (0 for LumpSum)
        uint64 cliffDuration; // Cliff duration in seconds (0 for no cliff)
    }

    /// @notice Campaign configuration and state
    struct Campaign {
        string name; // Campaign name
        string description; // Campaign description
        string campaignType; // Campaign type identifier
        address rewardToken; // ERC20 token address
        uint256 totalReward; // Total tokens to distribute
        Distribution[] distributions; // Array of distribution types
        uint64 startTime; // Campaign start timestamp
        uint64 endTime; // Campaign end timestamp
        uint256 claimed; // Total amount claimed so far
        uint64 closedAt; // Campaign closure timestamp (0 if open)
        bool exists; // Campaign was created
        address allowlistContract; // Optional allowlist contract (address(0) = disabled)
    }

    /// @notice Claim record for a specific distribution slot
    struct Claim {
        uint128 amountClaimed; // Amount claimed from this slot
        uint64 timestamp; // Last claim timestamp
    }

    // ============ State Variables ============

    /// @notice Current active campaign
    Campaign public campaign;

    /// @notice Allocation per address
    mapping(address => uint256) public allocations;

    /// @notice Claims per address per distribution slot
    /// @dev address => distributionSlot => Claim
    mapping(address => mapping(uint256 => Claim)) public claims;

    /// @notice Blacklisted addresses (cannot claim)
    mapping(address => bool) public blacklist;

    /// @notice Authorized wallets (can perform admin actions)
    mapping(address => bool) public authorizedWallets;

    /// @notice List of investors (for iteration - be careful with gas)
    address[] private _investors;

    /// @notice Track if address has allocation (for O(1) check)
    mapping(address => bool) private _hasAllocation;

    /// @notice Track address position in _investors array for O(1) removal
    mapping(address => uint256) private _investorIndex;

    /// @notice Total amount allocated across all investors
    uint256 public totalAllocated;

    // ============ Events ============

    /// @notice Emitted when a campaign is created
    event CampaignCreated(
        string name, address indexed rewardToken, uint256 totalReward, uint64 startTime, uint64 endTime
    );

    /// @notice Emitted when a campaign is closed
    event CampaignClosed(uint64 indexed closedAt, uint256 refundedAmount, address indexed recipient);

    /// @notice Emitted when allocations are added
    event AllocationsAdded(uint256 indexed count, uint256 indexed totalAmount);

    /// @notice Emitted when tokens are claimed
    event Claimed(address indexed user, uint256 indexed amount, address indexed sender);

    /// @notice Emitted when batch claim is completed
    event BatchClaimed(uint256 count, string memo, address indexed sender);

    /// @notice Emitted when an address is replaced
    event AddressReplaced(address indexed oldAddress, address indexed newAddress, uint256 indexed allocation);

    /// @notice Emitted when an address is removed
    event AddressRemoved(address indexed addr, uint256 indexed allocation);

    /// @notice Emitted when blacklist status changes
    event BlacklistUpdated(address indexed addr, bool indexed blacklisted);

    /// @notice Emitted when authorized wallet status changes
    event AuthorizedWalletUpdated(address indexed wallet, bool indexed authorized);

    /// @notice Emitted when tokens are swept
    event Swept(address indexed token, address indexed recipient, uint256 amount);

    // ============ Errors ============

    error CampaignAlreadyExists();
    error CampaignNotFound();
    error CampaignNotStarted();
    error CampaignAlreadyClosed();
    error CampaignNotEnded();
    error CampaignHasStarted();
    error InvalidTimeWindow();
    error CampaignDurationTooLong(uint256 duration, uint256 maxDuration);
    error InvalidDistributions();
    error InvalidPercentageSum(uint256 actual, uint256 expected);
    error InvalidBatchSize(uint256 actual, uint256 max);
    error ArrayLengthMismatch();
    error NoAllocation(address addr);
    error AllocationExists(address addr);
    error Blacklisted(address addr);
    error NotOnAllowlist(address addr);
    error CannotBlacklistOwner();
    error NothingToClaim();
    error ExceedsClaimable(uint256 requested, uint256 available);
    error ExceedsAllocation(uint256 claimed, uint256 allocation);
    error InsufficientBalance(uint256 required, uint256 available);
    error CannotSweepRewardToken();
    error ZeroAmount();
    error ZeroAddress();
    error Unauthorized();
    error LumpSumStartAfterCampaignEnd(uint256 distributionIndex);
    error InvalidVestingPeriod(uint256 distributionIndex);
    error SameAddress();
    error TooManyDistributions(uint256 count, uint256 max);
    error DistributionPercentageTooLow(uint256 index, uint256 bps, uint256 min);
    error DistributionOutsideCampaign(uint256 index);
    error InsufficientCampaignFunding(uint256 required, uint256 balance);
    error AllocationExceedsTotalReward(uint256 totalAllocated, uint256 totalReward);
    error CampaignStillActive();
    error CliffExceedsVestingPeriod(uint256 index);

    // ============ Modifiers ============

    /// @notice Restrict to owner or authorized wallet
    modifier onlyAuthorized() {
        if (msg.sender != owner() && !authorizedWallets[msg.sender]) {
            revert Unauthorized();
        }
        _;
    }

    // ============ Constructor ============

    /// @notice Initialize contract with owner
    /// @param initialOwner Address of the initial owner
    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }

    // ============ Campaign Management ============

    /// @notice Create a new campaign
    /// @param name Campaign name
    /// @param description Campaign description
    /// @param campaignType Campaign type identifier
    /// @param rewardToken ERC20 token address for rewards
    /// @param totalReward Total amount of tokens to distribute
    /// @param distributions Array of distribution configurations
    /// @param startTime Campaign start timestamp
    /// @param endTime Campaign end timestamp
    /// @param allowlistContract Optional allowlist contract address (address(0) to disable)
    /// @dev IMPORTANT: Fee-on-transfer (FOT) tokens are NOT supported.
    ///      Using FOT tokens will cause accounting mismatches where users
    ///      receive less than the recorded claim amount.
    function createCampaign(
        string calldata name,
        string calldata description,
        string calldata campaignType,
        address rewardToken,
        uint256 totalReward,
        Distribution[] calldata distributions,
        uint64 startTime,
        uint64 endTime,
        address allowlistContract
    )
        external
        onlyAuthorized
        whenNotPaused
    {
        if (campaign.exists) revert CampaignAlreadyExists();
        if (rewardToken == address(0)) revert ZeroAddress();
        if (totalReward == 0) revert ZeroAmount();
        if (distributions.length == 0) revert InvalidDistributions();

        // Validate campaign parameters
        _validateCampaignParams(distributions, startTime, endTime);

        // Validate sufficient funding
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        if (balance < totalReward) {
            revert InsufficientCampaignFunding(totalReward, balance);
        }

        // Create campaign
        campaign.name = name;
        campaign.description = description;
        campaign.campaignType = campaignType;
        campaign.rewardToken = rewardToken;
        campaign.totalReward = totalReward;
        campaign.startTime = startTime;
        campaign.endTime = endTime;
        campaign.claimed = 0;
        campaign.closedAt = 0;
        campaign.exists = true;
        campaign.allowlistContract = allowlistContract;

        // Copy distributions
        delete campaign.distributions;
        for (uint256 i = 0; i < distributions.length; i++) {
            campaign.distributions.push(distributions[i]);
        }

        emit CampaignCreated(name, rewardToken, totalReward, startTime, endTime);
    }

    /// @notice Close the campaign and return unclaimed tokens to owner
    /// @dev Requires campaign to have reached endTime to prevent early closure
    function closeCampaign() external onlyOwner nonReentrant {
        if (!campaign.exists) revert CampaignNotFound();
        if (campaign.closedAt != 0) revert CampaignAlreadyClosed();
        if (block.timestamp < campaign.endTime) revert CampaignStillActive();

        // Query current balance
        uint256 refund = IERC20(campaign.rewardToken).balanceOf(address(this));

        // Transfer unclaimed tokens to owner
        if (refund > 0) {
            IERC20(campaign.rewardToken).safeTransfer(owner(), refund);
        }

        // Mark campaign as closed
        campaign.closedAt = uint64(block.timestamp);

        emit CampaignClosed(campaign.closedAt, refund, owner());
    }

    // ============ Allocation Management ============

    /// @notice Add allocations in batch
    /// @param addresses Array of addresses
    /// @param amounts Array of allocation amounts
    function addAllocations(
        address[] calldata addresses,
        uint256[] calldata amounts
    )
        external
        onlyAuthorized
        whenNotPaused
    {
        if (!campaign.exists) revert CampaignNotFound();
        if (block.timestamp >= campaign.startTime) revert CampaignHasStarted();
        if (addresses.length != amounts.length) revert ArrayLengthMismatch();
        if (addresses.length == 0 || addresses.length > MAX_ALLOCATION_BATCH_SIZE) {
            revert InvalidBatchSize(addresses.length, MAX_ALLOCATION_BATCH_SIZE);
        }

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < addresses.length; i++) {
            address addr = addresses[i];
            uint256 amount = amounts[i];

            if (addr == address(0)) revert ZeroAddress();
            if (amount == 0) revert ZeroAmount();
            if (allocations[addr] != 0) revert AllocationExists(addr);

            allocations[addr] = amount;
            totalAmount += amount;

            // Track investor
            if (!_hasAllocation[addr]) {
                _investorIndex[addr] = _investors.length;
                _investors.push(addr);
                _hasAllocation[addr] = true;
            }
        }

        // Validate total allocations don't exceed campaign reward
        uint256 newTotalAllocated = totalAllocated + totalAmount;
        if (newTotalAllocated > campaign.totalReward) {
            revert AllocationExceedsTotalReward(newTotalAllocated, campaign.totalReward);
        }
        totalAllocated = newTotalAllocated;

        emit AllocationsAdded(addresses.length, totalAmount);
    }

    /// @notice Replace an address (migrate allocation and claims)
    /// @param oldAddress Address to replace
    /// @param newAddress New address
    function replaceAddress(address oldAddress, address newAddress) external onlyAuthorized {
        if (oldAddress == address(0) || newAddress == address(0)) {
            revert ZeroAddress();
        }
        if (oldAddress == newAddress) {
            revert SameAddress();
        }

        uint256 allocation = allocations[oldAddress];
        if (allocation == 0) revert NoAllocation(oldAddress);
        if (allocations[newAddress] != 0) revert AllocationExists(newAddress);

        // Transfer allocation
        allocations[newAddress] = allocation;
        delete allocations[oldAddress];

        // Transfer claims
        for (uint256 i = 0; i < campaign.distributions.length; i++) {
            claims[newAddress][i] = claims[oldAddress][i];
            delete claims[oldAddress][i];
        }

        // Transfer blacklist status
        if (blacklist[oldAddress]) {
            blacklist[newAddress] = true;
            delete blacklist[oldAddress];
        }

        // Update investor tracking (replace in array, don't push/pop)
        uint256 index = _investorIndex[oldAddress];
        _investors[index] = newAddress;
        _investorIndex[newAddress] = index;
        delete _investorIndex[oldAddress];

        _hasAllocation[newAddress] = true;
        _hasAllocation[oldAddress] = false;

        emit AddressReplaced(oldAddress, newAddress, allocation);
    }

    /// @notice Remove an address allocation
    /// @param addr Address to remove
    function removeAddress(address addr) external onlyAuthorized {
        if (!campaign.exists) revert CampaignNotFound();
        if (block.timestamp >= campaign.startTime) revert CampaignHasStarted();

        uint256 allocation = allocations[addr];
        if (allocation == 0) revert NoAllocation(addr);

        delete allocations[addr];

        // Decrement total allocated
        totalAllocated -= allocation;

        // Remove from _investors array using swap-and-pop
        uint256 index = _investorIndex[addr];
        uint256 lastIndex = _investors.length - 1;

        if (index != lastIndex) {
            address lastInvestor = _investors[lastIndex];
            _investors[index] = lastInvestor;
            _investorIndex[lastInvestor] = index;
        }

        _investors.pop();
        delete _investorIndex[addr];
        _hasAllocation[addr] = false;

        emit AddressRemoved(addr, allocation);
    }

    // ============ Claiming ============

    /// @notice Claim tokens
    /// @param receiver Address to receive tokens
    /// @param amount Amount to claim (0 for maximum available)
    function claim(address receiver, uint256 amount) external nonReentrant whenNotPaused {
        if (msg.sender != owner() && msg.sender != receiver) revert Unauthorized();
        _claim(receiver, amount, msg.sender);
    }

    /// @notice Claim tokens on behalf of multiple users
    /// @param users Array of user addresses
    /// @param amounts Array of amounts to claim (0 for maximum available)
    /// @param memo Memo describing the reason for batch claim
    /// @dev Skips users with nothing to claim while still reverting for security-critical errors
    ///      (blacklisted, no allocation, insufficient balance). This prevents griefing where
    ///      a single user can block the entire batch by pre-claiming.
    function claimOnBehalfOfBatch(
        address[] calldata users,
        uint256[] calldata amounts,
        string calldata memo
    )
        external
        onlyAuthorized
        nonReentrant
        whenNotPaused
    {
        if (users.length != amounts.length) revert ArrayLengthMismatch();
        if (users.length == 0 || users.length > MAX_CLAIM_BATCH_SIZE) {
            revert InvalidBatchSize(users.length, MAX_CLAIM_BATCH_SIZE);
        }

        uint256 successCount = 0;
        for (uint256 i = 0; i < users.length; i++) {
            if (_tryClaimForBatch(users[i], amounts[i], msg.sender)) {
                successCount++;
            }
        }

        emit BatchClaimed(successCount, memo, msg.sender);
    }

    // ============ Administration ============

    /// @notice Update blacklist status for an address
    /// @param addr Address to blacklist/unblacklist
    /// @param blacklisted Blacklist status
    function blacklistAddress(address addr, bool blacklisted) external onlyAuthorized {
        if (addr == owner()) revert CannotBlacklistOwner();

        blacklist[addr] = blacklisted;

        emit BlacklistUpdated(addr, blacklisted);
    }

    /// @notice Manage authorized wallets in batch
    /// @param addresses Array of addresses
    /// @param authorized Authorization status
    function manageAuthorizedWallets(address[] calldata addresses, bool authorized) external onlyOwner {
        if (addresses.length == 0 || addresses.length > MAX_AUTHORIZED_WALLETS_BATCH_SIZE) {
            revert InvalidBatchSize(addresses.length, MAX_AUTHORIZED_WALLETS_BATCH_SIZE);
        }

        for (uint256 i = 0; i < addresses.length; i++) {
            address addr = addresses[i];
            if (addr == address(0)) revert ZeroAddress();

            authorizedWallets[addr] = authorized;

            emit AuthorizedWalletUpdated(addr, authorized);
        }
    }

    /// @notice Sweep non-reward tokens from contract
    /// @param token Token address to sweep
    /// @param amount Amount to sweep
    function sweep(address token, uint256 amount) external onlyOwner nonReentrant {
        // Prevent sweeping reward token if campaign exists and is not closed
        if (campaign.exists && campaign.closedAt == 0 && token == campaign.rewardToken) {
            revert CannotSweepRewardToken();
        }

        if (amount == 0) revert ZeroAmount();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance(amount, balance);

        IERC20(token).safeTransfer(owner(), amount);

        emit Swept(token, owner(), amount);
    }

    /// @notice Pause contract (emergency)
    function pause() external onlyAuthorized {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() external onlyAuthorized {
        _unpause();
    }

    // ============ View Functions ============

    /// @notice Get campaign details
    /// @return Campaign struct
    function getCampaign() external view returns (Campaign memory) {
        return campaign;
    }

    /// @notice Get allocation for an address
    /// @param addr Address to query
    /// @return Allocation amount
    function getAllocation(address addr) external view returns (uint256) {
        return allocations[addr];
    }

    /// @notice Get claims for an address
    /// @param addr Address to query
    /// @return Array of claimed amounts per slot
    function getClaims(address addr) external view returns (uint256[] memory) {
        uint256[] memory claimedPerSlot = new uint256[](campaign.distributions.length);

        for (uint256 i = 0; i < campaign.distributions.length; i++) {
            claimedPerSlot[i] = claims[addr][i].amountClaimed;
        }

        return claimedPerSlot;
    }

    /// @notice Get reward details for an address
    /// @param addr Address to query
    /// @return claimed Total claimed
    /// @return pending Total claimable now
    /// @return total Total allocation
    /// @dev Pending amount uses closedAt as effective time when campaign is closed
    function getRewards(address addr) external view returns (uint256 claimed, uint256 pending, uint256 total) {
        total = allocations[addr];
        claimed = _getTotalClaimedForAddress(addr);

        // Allow pending calculation even after closure (vesting frozen at closedAt)
        if (campaign.exists && block.timestamp >= campaign.startTime) {
            (pending,) = _computeClaimableAmount(addr, total);
        } else {
            pending = 0;
        }
    }

    /// @notice Check if address is blacklisted
    /// @param addr Address to check
    /// @return Blacklist status
    function isBlacklisted(address addr) external view returns (bool) {
        return blacklist[addr];
    }

    /// @notice Check if address is authorized
    /// @param addr Address to check
    /// @return Authorization status
    function isAuthorized(address addr) external view returns (bool) {
        return addr == owner() || authorizedWallets[addr];
    }

    /// @notice Get number of investors
    /// @return Number of investors
    function getInvestorCount() external view returns (uint256) {
        return _investors.length;
    }

    // ============ Internal Functions ============

    /// @notice Validate campaign parameters
    /// @param distributions Array of distributions
    /// @param startTime Campaign start time
    /// @param endTime Campaign end time
    function _validateCampaignParams(
        Distribution[] calldata distributions,
        uint64 startTime,
        uint64 endTime
    )
        internal
        view
    {
        // Validate time window
        if (startTime <= block.timestamp) revert InvalidTimeWindow();
        if (endTime <= startTime) revert InvalidTimeWindow();

        // Validate campaign duration
        uint256 duration = endTime - startTime;
        if (duration > MAX_CAMPAIGN_DURATION) {
            revert CampaignDurationTooLong(duration, MAX_CAMPAIGN_DURATION);
        }

        // Validate distribution count
        if (distributions.length > MAX_DISTRIBUTIONS) {
            revert TooManyDistributions(distributions.length, MAX_DISTRIBUTIONS);
        }

        // Validate percentages sum to 100% and each meets minimum
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < distributions.length; i++) {
            // Check minimum percentage
            if (distributions[i].percentageBps < MIN_DISTRIBUTION_BPS) {
                revert DistributionPercentageTooLow(i, distributions[i].percentageBps, MIN_DISTRIBUTION_BPS);
            }

            totalPercentage += distributions[i].percentageBps;

            // Validate distribution times
            if (distributions[i].kind == DistributionKind.LinearVesting) {
                // Validate vesting period is positive
                if (distributions[i].endTime <= distributions[i].startTime) {
                    revert InvalidVestingPeriod(i);
                }
                // Validate cliff is strictly less than vesting period
                uint256 vestingPeriod = distributions[i].endTime - distributions[i].startTime;
                if (distributions[i].cliffDuration >= vestingPeriod) {
                    revert CliffExceedsVestingPeriod(i);
                }
                // Validate vesting is within campaign bounds
                if (distributions[i].startTime < startTime || distributions[i].endTime > endTime) {
                    revert DistributionOutsideCampaign(i);
                }
            } else {
                // LumpSum: startTime must be within campaign window
                if (distributions[i].startTime < startTime || distributions[i].startTime > endTime) {
                    revert DistributionOutsideCampaign(i);
                }
            }
        }

        if (totalPercentage != BASIS_POINTS_TOTAL) {
            revert InvalidPercentageSum(totalPercentage, BASIS_POINTS_TOTAL);
        }
    }

    /// @notice Compute claimable amount for an address
    /// @param user User address
    /// @param allocation User's total allocation
    /// @return claimable Total claimable amount
    /// @return slotAmounts Array of claimable per slot
    /// @dev When campaign is closed, vesting calculations freeze at closedAt timestamp
    function _computeClaimableAmount(
        address user,
        uint256 allocation
    )
        internal
        view
        returns (uint256 claimable, uint256[] memory slotAmounts)
    {
        slotAmounts = new uint256[](campaign.distributions.length);
        claimable = 0;

        // Determine effective timestamp (freeze at closedAt if closed)
        uint256 effectiveTime = block.timestamp;
        if (campaign.closedAt != 0 && campaign.closedAt < block.timestamp) {
            effectiveTime = campaign.closedAt;
        }

        for (uint256 i = 0; i < campaign.distributions.length; i++) {
            Distribution storage dist = campaign.distributions[i];

            // Skip if distribution hasn't started (use effectiveTime)
            if (effectiveTime < dist.startTime) continue;

            // Skip if cliff hasn't passed (use effectiveTime)
            if (dist.cliffDuration > 0 && effectiveTime < dist.startTime + dist.cliffDuration) {
                continue;
            }

            uint256 slotAmount;
            Claim storage prevClaim = claims[user][i];

            if (dist.kind == DistributionKind.LinearVesting) {
                slotAmount = _calculateLinearVestingWithTime(dist, allocation, prevClaim, effectiveTime);
            } else {
                slotAmount = _calculateLumpSum(dist, allocation, prevClaim);
            }

            slotAmounts[i] = slotAmount;
            claimable += slotAmount;
        }

        // Handle rounding dust if all distributions ended
        if (_distributionTypesEnded()) {
            uint256 totalClaimed = _getTotalClaimedForAddress(user);
            uint256 expectedRemaining = allocation - totalClaimed;
            // Only add dust if there's a discrepancy (rounding error)
            // claimable should equal expectedRemaining, but might be slightly less due to rounding
            if (expectedRemaining > claimable && expectedRemaining - claimable > 0) {
                uint256 dust = expectedRemaining - claimable;
                // Add dust to the first non-zero slot, or slot 0
                uint256 dustSlot = _findSlotForDust(slotAmounts);
                slotAmounts[dustSlot] += dust;
                claimable += dust;
            }
        }

        return (claimable, slotAmounts);
    }

    /// @notice Calculate linear vesting amount using current block.timestamp
    /// @param dist Distribution configuration
    /// @param allocation Total allocation
    /// @param prevClaim Previous claim record
    /// @return Claimable amount for this distribution
    function _calculateLinearVesting(
        Distribution storage dist,
        uint256 allocation,
        Claim storage prevClaim
    )
        internal
        view
        returns (uint256)
    {
        return _calculateLinearVestingWithTime(dist, allocation, prevClaim, block.timestamp);
    }

    /// @notice Calculate linear vesting amount with specified timestamp
    /// @param dist Distribution configuration
    /// @param allocation Total allocation
    /// @param prevClaim Previous claim record
    /// @param currentTime The effective timestamp to use for calculation
    /// @return Claimable amount for this distribution
    /// @dev This allows vesting calculations to use closedAt as effective time when campaign is closed
    function _calculateLinearVestingWithTime(
        Distribution storage dist,
        uint256 allocation,
        Claim storage prevClaim,
        uint256 currentTime
    )
        internal
        view
        returns (uint256)
    {
        // Calculate allocation for this distribution
        uint256 distributionAllocation = (allocation * dist.percentageBps) / BASIS_POINTS_TOTAL;

        // Calculate vesting duration
        uint256 duration = dist.endTime - dist.startTime;
        if (duration == 0) return 0;

        // Calculate elapsed time (capped at duration)
        uint256 elapsed = currentTime - dist.startTime;
        if (elapsed > duration) elapsed = duration;

        // Calculate vested amount
        uint256 vested = (distributionAllocation * elapsed) / duration;

        // Subtract already claimed
        uint256 alreadyClaimed = prevClaim.amountClaimed;
        if (vested <= alreadyClaimed) return 0;

        return vested - alreadyClaimed;
    }

    /// @notice Calculate lump sum amount
    /// @param dist Distribution configuration
    /// @param allocation Total allocation
    /// @param prevClaim Previous claim record
    /// @return Claimable amount for this distribution
    function _calculateLumpSum(
        Distribution storage dist,
        uint256 allocation,
        Claim storage prevClaim
    )
        internal
        view
        returns (uint256)
    {
        // Calculate allocation for this distribution
        uint256 distributionAllocation = (allocation * dist.percentageBps) / BASIS_POINTS_TOTAL;

        // Return full amount minus already claimed
        uint256 alreadyClaimed = prevClaim.amountClaimed;
        if (distributionAllocation <= alreadyClaimed) return 0;

        return distributionAllocation - alreadyClaimed;
    }

    /// @notice Check if all distributions have ended
    /// @return True if all distributions ended
    /// @dev When campaign is closed, uses closedAt as effective time
    function _distributionTypesEnded() internal view returns (bool) {
        if (!campaign.exists) return false;

        // Determine effective timestamp (freeze at closedAt if closed)
        uint256 effectiveTime = block.timestamp;
        if (campaign.closedAt != 0 && campaign.closedAt < block.timestamp) {
            effectiveTime = campaign.closedAt;
        }

        for (uint256 i = 0; i < campaign.distributions.length; i++) {
            Distribution storage dist = campaign.distributions[i];

            if (dist.kind == DistributionKind.LinearVesting) {
                if (effectiveTime < dist.endTime) return false;
            } else {
                // LumpSum
                if (effectiveTime < dist.startTime) return false;
            }
        }

        return true;
    }

    /// @notice Get total claimed amount for an address
    /// @param addr Address to query
    /// @return Total claimed amount
    function _getTotalClaimedForAddress(address addr) internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < campaign.distributions.length; i++) {
            total += claims[addr][i].amountClaimed;
        }
        return total;
    }

    /// @notice Find slot index for dust amount
    /// @param slotAmounts Array of slot amounts
    /// @return Slot index
    function _findSlotForDust(uint256[] memory slotAmounts) internal pure returns (uint256) {
        // Find first non-zero slot, or return 0
        for (uint256 i = 0; i < slotAmounts.length; i++) {
            if (slotAmounts[i] > 0) return i;
        }
        return 0;
    }

    /// @notice Distribute claim amount to slots (lump sum priority)
    /// @param amount Amount to distribute
    /// @param slotAmounts Available amounts per slot
    /// @return distribution Distribution per slot
    function _distributeToSlots(
        uint256 amount,
        uint256[] memory slotAmounts
    )
        internal
        view
        returns (uint256[] memory distribution)
    {
        distribution = new uint256[](campaign.distributions.length);
        uint256 remaining = amount;

        // Phase 1: Distribute to LumpSum slots
        for (uint256 i = 0; i < campaign.distributions.length; i++) {
            if (campaign.distributions[i].kind != DistributionKind.LumpSum) continue;

            uint256 available = slotAmounts[i];
            if (available == 0) continue;

            uint256 toDistribute = remaining < available ? remaining : available;
            distribution[i] = toDistribute;
            remaining -= toDistribute;

            if (remaining == 0) return distribution;
        }

        // Phase 2: Distribute to LinearVesting slots
        for (uint256 i = 0; i < campaign.distributions.length; i++) {
            if (campaign.distributions[i].kind != DistributionKind.LinearVesting) {
                continue;
            }

            uint256 available = slotAmounts[i];
            if (available == 0) continue;

            uint256 toDistribute = remaining < available ? remaining : available;
            distribution[i] = toDistribute;
            remaining -= toDistribute;

            if (remaining == 0) return distribution;
        }

        return distribution;
    }

    /// @notice Internal claim logic
    /// @param receiver Address to receive tokens
    /// @param amount Amount to claim (0 for maximum available)
    /// @param sender Address initiating the claim
    /// @dev Claims are allowed after campaign closure for already-vested amounts.
    ///      Vesting calculations freeze at closedAt timestamp.
    function _claim(address receiver, uint256 amount, address sender) internal {
        if (!campaign.exists) revert CampaignNotFound();
        if (block.timestamp < campaign.startTime) revert CampaignNotStarted();
        // Note: CampaignAlreadyClosed check removed to allow claims for already-vested amounts
        // Vesting calculations use closedAt as effective time when closed
        if (blacklist[receiver]) revert Blacklisted(receiver);

        // Check allowlist if configured
        if (campaign.allowlistContract != address(0)) {
            if (!Allowlist(campaign.allowlistContract).isAllowed(receiver)) {
                revert NotOnAllowlist(receiver);
            }
        }

        uint256 allocation = allocations[receiver];
        if (allocation == 0) revert NoAllocation(receiver);

        // Compute claimable amount
        (uint256 claimable, uint256[] memory slotAmounts) = _computeClaimableAmount(receiver, allocation);

        if (claimable == 0) revert NothingToClaim();

        // Determine claim amount
        uint256 claimAmount = amount == 0 ? claimable : amount;
        if (claimAmount > claimable) {
            revert ExceedsClaimable(claimAmount, claimable);
        }

        // Validate contract balance
        uint256 contractBalance = IERC20(campaign.rewardToken).balanceOf(address(this));
        if (contractBalance < claimAmount) {
            revert InsufficientBalance(claimAmount, contractBalance);
        }

        // Distribute to slots
        uint256[] memory distribution = _distributeToSlots(claimAmount, slotAmounts);

        // Update claims
        for (uint256 i = 0; i < distribution.length; i++) {
            if (distribution[i] > 0) {
                Claim storage existingClaim = claims[receiver][i];
                claims[receiver][i] = Claim({
                    amountClaimed: (uint256(existingClaim.amountClaimed) + distribution[i]).toUint128(),
                    timestamp: uint64(block.timestamp)
                });
            }
        }

        // Update campaign claimed amount
        campaign.claimed += claimAmount;

        // Validate invariant
        uint256 totalClaimed = _getTotalClaimedForAddress(receiver);
        if (totalClaimed > allocation) {
            revert ExceedsAllocation(totalClaimed, allocation);
        }

        // Transfer tokens
        IERC20(campaign.rewardToken).safeTransfer(receiver, claimAmount);

        emit Claimed(receiver, claimAmount, sender);
    }

    /// @notice Internal claim logic for batch operations (skips instead of reverting for zero claimable)
    /// @param receiver Address to receive tokens
    /// @param amount Amount to claim (0 for maximum available)
    /// @param sender Address initiating the claim
    /// @return success Whether the claim was processed (false if nothing to claim)
    /// @dev Security-critical reverts are preserved: campaign checks, blacklist, no allocation, insufficient balance
    function _tryClaimForBatch(address receiver, uint256 amount, address sender) internal returns (bool success) {
        if (!campaign.exists) revert CampaignNotFound();
        if (block.timestamp < campaign.startTime) revert CampaignNotStarted();
        // Note: CampaignAlreadyClosed check removed to allow claims for already-vested amounts
        // Vesting calculations use closedAt as effective time when closed
        if (blacklist[receiver]) revert Blacklisted(receiver);

        // Check allowlist if configured
        if (campaign.allowlistContract != address(0)) {
            if (!Allowlist(campaign.allowlistContract).isAllowed(receiver)) {
                revert NotOnAllowlist(receiver);
            }
        }

        uint256 allocation = allocations[receiver];
        if (allocation == 0) revert NoAllocation(receiver);

        // Compute claimable amount
        (uint256 claimable, uint256[] memory slotAmounts) = _computeClaimableAmount(receiver, allocation);

        // Skip if nothing to claim (return false instead of reverting)
        if (claimable == 0) {
            return false;
        }

        // Determine claim amount - cap to claimable instead of reverting
        uint256 claimAmount = amount == 0 ? claimable : amount;
        if (claimAmount > claimable) {
            claimAmount = claimable;
        }

        // Validate contract balance
        uint256 contractBalance = IERC20(campaign.rewardToken).balanceOf(address(this));
        if (contractBalance < claimAmount) {
            revert InsufficientBalance(claimAmount, contractBalance);
        }

        // Distribute to slots
        uint256[] memory distribution = _distributeToSlots(claimAmount, slotAmounts);

        // Update claims
        for (uint256 i = 0; i < distribution.length; i++) {
            if (distribution[i] > 0) {
                Claim storage existingClaim = claims[receiver][i];
                claims[receiver][i] = Claim({
                    amountClaimed: (uint256(existingClaim.amountClaimed) + distribution[i]).toUint128(),
                    timestamp: uint64(block.timestamp)
                });
            }
        }

        // Update campaign claimed amount
        campaign.claimed += claimAmount;

        // Validate invariant
        uint256 totalClaimed = _getTotalClaimedForAddress(receiver);
        if (totalClaimed > allocation) {
            revert ExceedsAllocation(totalClaimed, allocation);
        }

        // Transfer tokens
        IERC20(campaign.rewardToken).safeTransfer(receiver, claimAmount);

        emit Claimed(receiver, claimAmount, sender);
        return true;
    }
}
