// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Claimdrop} from "../../contracts/Claimdrop.sol";
import {MockERC20} from "../../contracts/mocks/MockERC20.sol";
import {E2ENetworkConfig} from "./E2ENetworkConfig.sol";

/**
 * @title E2EBase
 * @notice Shared utilities and helpers for E2E orchestration and testing
 * @dev Abstract base contract providing common functionality for both script-based
 *      orchestration and test-based validation. Inherits network configuration
 *      capabilities and adds E2E-specific utilities.
 *
 * Key Features:
 * - Deterministic test user generation
 * - Network-aware time manipulation (vm.warp for local, delay patterns for testnet)
 * - Mock token deployment for local testing
 * - State persistence (save/load execution state)
 * - Validation helpers (balance checks, claimable calculations)
 * - Report generation utilities
 *
 * Usage Pattern:
 *   contract MyE2EScript is E2EBase {
 *       function run() public {
 *           NetworkConfig memory network = getNetworkConfig();
 *           (address[] memory users, uint256[] memory amounts) = generateTestAllocations(network);
 *           // ... use helpers ...
 *       }
 *   }
 */
abstract contract E2EBase is Script, E2ENetworkConfig {
    using stdJson for string;

    // ============ Constants ============

    /// @notice Number of test users to generate
    uint256 internal constant TEST_USER_COUNT = 10;

    /// @notice Minimum allocation amount (100 OM)
    uint256 internal constant MIN_ALLOCATION = 100 ether;

    /// @notice Maximum allocation amount (1000 OM)
    uint256 internal constant MAX_ALLOCATION = 1000 ether;

    /// @notice State file directory
    string internal constant STATE_DIR = "./out";

    /// @notice Report file directory
    string internal constant REPORT_DIR = "./out";

    // ============ Structs ============

    /// @notice Execution state for persistence and recovery
    struct E2EState {
        string network;
        uint256 chainId;
        address claimdrop;
        address rewardToken;
        uint64 campaignStartTime;
        uint64 campaignEndTime;
        address[] testUsers;
        uint256[] allocations;
        uint8 lastCompletedPhase;
        uint256 timestamp;
        uint256 totalClaimed;
    }

    /// @notice Validation result structure
    struct ValidationResult {
        bool success;
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 expectedClaimable;
        uint256 actualClaimable;
        uint256 contractBalance;
        string[] errors;
    }

    // ============ Test User Generation ============

    /**
     * @notice Generate deterministic test users and allocations
     * @param network Network configuration (used for total reward calculation)
     * @return users Array of test user addresses
     * @return amounts Array of allocation amounts (varies from MIN to MAX)
     */
    function generateTestAllocations(NetworkConfig memory network)
        internal
        returns (address[] memory users, uint256[] memory amounts)
    {
        users = new address[](TEST_USER_COUNT);
        amounts = new uint256[](TEST_USER_COUNT);

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < TEST_USER_COUNT; i++) {
            // Generate deterministic address using makeAddr
            string memory label = string.concat("e2e_user_", vm.toString(i));
            users[i] = makeAddr(label);

            // Vary allocation amounts: 100, 200, 300, ..., 1000 OM
            // This creates a realistic distribution for testing
            amounts[i] = MIN_ALLOCATION + (i * (MAX_ALLOCATION - MIN_ALLOCATION) / (TEST_USER_COUNT - 1));
            totalAmount += amounts[i];
        }

        console.log("Generated test allocations:");
        console.log("  Users:", TEST_USER_COUNT);
        console.log("  Total Amount:", totalAmount / 1e18, "OM");
        console.log("  Min Allocation:", MIN_ALLOCATION / 1e18, "OM");
        console.log("  Max Allocation:", MAX_ALLOCATION / 1e18, "OM");

        return (users, amounts);
    }

    /**
     * @notice Get test user address by index
     * @param index User index (0-9)
     * @return user Test user address
     */
    function getTestUser(uint256 index) internal returns (address user) {
        require(index < TEST_USER_COUNT, "Invalid user index");
        string memory label = string.concat("e2e_user_", vm.toString(index));
        return makeAddr(label);
    }

    // ============ Token Deployment ============

    /**
     * @notice Deploy mock ERC20 token for local testing
     * @dev Only deploys on local network (ChainID 31337), reverts on other networks
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial token supply
     * @return token Deployed MockERC20 token
     */
    function deployMockToken(string memory name, string memory symbol, uint256 initialSupply)
        internal
        returns (MockERC20 token)
    {
        require(
            block.chainid == 31337,
            "deployMockToken: Only supported on local network. Use existing token or set REWARD_TOKEN env var."
        );

        console.log("Deploying mock ERC20 token...");
        console.log("  Name:", name);
        console.log("  Symbol:", symbol);
        console.log("  Supply:", initialSupply / 1e18, symbol);

        token = new MockERC20(name, symbol, 18);
        token.mint(msg.sender, initialSupply);

        console.log("Mock token deployed:", address(token));

        return token;
    }

    /**
     * @notice Get reward token address (deploy mock on local, use env var on testnet)
     * @param network Network configuration
     * @return tokenAddress Address of reward token
     */
    function getRewardToken(NetworkConfig memory network) internal returns (address tokenAddress) {
        if (network.chainId == 31337) {
            // Local: Deploy mock token
            MockERC20 mockToken = deployMockToken("Test OM", "tOM", 10_000_000 ether);
            return address(mockToken);
        } else {
            // Testnet/Mainnet: Use env var
            tokenAddress = vm.envAddress("REWARD_TOKEN");
            require(tokenAddress != address(0), "REWARD_TOKEN env var not set");
            console.log("Using reward token from env:", tokenAddress);
            return tokenAddress;
        }
    }

    // ============ Time Manipulation ============

    /**
     * @notice Wait until specified timestamp (network-aware)
     * @dev On local (ChainID 31337): Uses vm.warp() for instant time jump
     *      On testnet/mainnet: Documents waiting pattern (scripts can't actually sleep)
     * @param targetTime Target timestamp to wait for
     * @param network Network configuration
     */
    function waitForTimestamp(uint64 targetTime, NetworkConfig memory network) internal {
        uint256 currentTime = vm.getBlockTimestamp(); // Use vm.getBlockTimestamp() for via-ir compatibility

        if (currentTime >= targetTime) {
            console.log("Already past target time, no waiting needed");
            return;
        }

        uint256 waitTime = targetTime - currentTime;

        if (network.chainId == 31337) {
            // Local network: instant time warp
            console.log("Warping time forward:", waitTime, "seconds");
            vm.warp(targetTime);
            console.log("Time warped to:", vm.getBlockTimestamp());
        } else {
            // Testnet/Mainnet: Document waiting pattern
            console.log("");
            console.log("=== Waiting for Campaign Start ===");
            console.log("Current time:", currentTime);
            console.log("Target time:", targetTime);
            console.log("Wait duration (seconds):", waitTime);
            console.log("Wait duration (minutes):", waitTime / 60);
            console.log("");
            console.log("NOTE: Scripts cannot automatically wait on live networks.");
            console.log("Please wait for the specified duration, then continue to next phase.");
            console.log("You can monitor progress on block explorer:", network.explorerUrl);
            console.log("================================");
            console.log("");

            // Note: In a real orchestrator, this phase would need to be split
            // or run in a separate transaction after manual waiting
        }
    }

    /**
     * @notice Warp to campaign start time (local only, safe wrapper)
     * @param startTime Campaign start timestamp
     * @param network Network configuration
     */
    function warpToCampaignStart(uint64 startTime, NetworkConfig memory network) internal {
        if (network.chainId == 31337) {
            console.log("Warping to campaign start time:", startTime);
            vm.warp(startTime);
            require(vm.getBlockTimestamp() >= startTime, "Time warp failed");
        } else {
            console.log("Skipping time warp on live network");
        }
    }

    /**
     * @notice Warp forward by duration (local only)
     * @param duration Seconds to warp forward
     * @param network Network configuration
     */
    function warpForward(uint256 duration, NetworkConfig memory network) internal {
        if (network.chainId == 31337) {
            uint256 newTime = vm.getBlockTimestamp() + duration;
            console.log("Warping forward:", duration, "seconds to", newTime);
            vm.warp(newTime);
        }
    }

    // ============ Validation Helpers ============

    /**
     * @notice Calculate expected claimable amount for user at current time
     * @param allocation User's total allocation
     * @param distributions Campaign distribution configurations
     * @param campaignStartTime Campaign start timestamp
     * @param claims User's claim records (amount claimed per distribution slot)
     * @return claimable Total claimable amount across all distributions
     */
    function calculateExpectedClaimable(
        uint256 allocation,
        Claimdrop.Distribution[] memory distributions,
        uint64 campaignStartTime,
        uint256[] memory claims
    ) internal view returns (uint256 claimable) {
        uint256 currentTime = vm.getBlockTimestamp();
        claimable = 0;

        for (uint256 i = 0; i < distributions.length; i++) {
            Claimdrop.Distribution memory dist = distributions[i];
            uint256 slotAllocation = (allocation * dist.percentageBps) / 10000;
            uint256 slotClaimable = 0;

            if (dist.kind == Claimdrop.DistributionKind.LumpSum) {
                // Lump sum: all available at start time
                if (currentTime >= dist.startTime) {
                    slotClaimable = slotAllocation;
                }
            } else if (dist.kind == Claimdrop.DistributionKind.LinearVesting) {
                // Linear vesting with optional cliff
                if (currentTime < dist.startTime + dist.cliffDuration) {
                    // Still in cliff period
                    slotClaimable = 0;
                } else if (currentTime >= dist.endTime) {
                    // Fully vested
                    slotClaimable = slotAllocation;
                } else {
                    // Partially vested: linear calculation
                    uint256 elapsed = currentTime - dist.startTime;
                    uint256 duration = dist.endTime - dist.startTime;
                    slotClaimable = (slotAllocation * elapsed) / duration;
                }
            }

            // Subtract already claimed amount
            if (i < claims.length) {
                if (slotClaimable > claims[i]) {
                    claimable += slotClaimable - claims[i];
                }
            } else {
                claimable += slotClaimable;
            }
        }

        return claimable;
    }

    /**
     * @notice Verify allocation matches expected value
     * @param claimdrop Claimdrop contract
     * @param user User address
     * @param expectedAmount Expected allocation amount
     * @return success Whether allocation matches
     */
    function verifyAllocation(Claimdrop claimdrop, address user, uint256 expectedAmount)
        internal
        view
        returns (bool success)
    {
        uint256 actualAmount = claimdrop.allocations(user);
        if (actualAmount != expectedAmount) {
            console.log("Allocation mismatch for", user);
            console.log("  Expected:", expectedAmount);
            console.log("  Actual:", actualAmount);
            return false;
        }
        return true;
    }

    /**
     * @notice Verify token balance matches expected value
     * @param token ERC20 token
     * @param user User address
     * @param expectedBalance Expected balance
     * @return success Whether balance matches
     */
    function verifyBalance(MockERC20 token, address user, uint256 expectedBalance)
        internal
        view
        returns (bool success)
    {
        uint256 actualBalance = token.balanceOf(user);
        if (actualBalance != expectedBalance) {
            console.log("Balance mismatch for", user);
            console.log("  Expected:", expectedBalance);
            console.log("  Actual:", actualBalance);
            return false;
        }
        return true;
    }

    /**
     * @notice Verify campaign state
     * @param claimdrop Claimdrop contract
     * @param expectedClosed Whether campaign should be closed
     * @return success Whether campaign state matches
     */
    function verifyCampaignState(Claimdrop claimdrop, bool expectedClosed) internal view returns (bool success) {
        // Get closedAt field from campaign (field 9 out of 10 returned by getter)
        (,,,,,,,, uint64 closedAt,) = claimdrop.campaign();
        bool isClosed = closedAt != 0;

        if (isClosed != expectedClosed) {
            console.log("Campaign state mismatch");
            console.log("  Expected closed:", expectedClosed);
            console.log("  Actual closed:", isClosed);
            return false;
        }
        return true;
    }

    // ============ State Persistence ============

    /**
     * @notice Get state file path for network
     * @param network Network configuration
     * @return path Full path to state file
     */
    function getStateFilePath(NetworkConfig memory network) internal pure returns (string memory path) {
        return string.concat(STATE_DIR, "/e2e-state-", network.name, ".json");
    }

    /**
     * @notice Save E2E execution state to JSON file
     * @param state Execution state to save
     * @param network Network configuration
     */
    function saveState(E2EState memory state, NetworkConfig memory network) internal {
        string memory json = "state";

        // Serialize state fields
        vm.serializeString(json, "network", state.network);
        vm.serializeUint(json, "chainId", state.chainId);
        vm.serializeAddress(json, "claimdrop", state.claimdrop);
        vm.serializeAddress(json, "rewardToken", state.rewardToken);
        vm.serializeUint(json, "campaignStartTime", state.campaignStartTime);
        vm.serializeUint(json, "campaignEndTime", state.campaignEndTime);

        // Serialize arrays
        string memory usersJson = "";
        for (uint256 i = 0; i < state.testUsers.length; i++) {
            usersJson = vm.serializeAddress("users", vm.toString(i), state.testUsers[i]);
        }
        vm.serializeString(json, "testUsers", usersJson);

        string memory allocationsJson = "";
        for (uint256 i = 0; i < state.allocations.length; i++) {
            allocationsJson = vm.serializeUint("allocations", vm.toString(i), state.allocations[i]);
        }
        vm.serializeString(json, "allocations", allocationsJson);

        vm.serializeUint(json, "lastCompletedPhase", state.lastCompletedPhase);
        vm.serializeUint(json, "timestamp", state.timestamp);
        string memory finalJson = vm.serializeUint(json, "totalClaimed", state.totalClaimed);

        // Write to file
        string memory filePath = getStateFilePath(network);
        vm.writeFile(filePath, finalJson);
        console.log("State saved to:", filePath);
    }

    /**
     * @notice Load E2E execution state from JSON file
     * @param network Network configuration
     * @return state Loaded execution state
     */
    function loadState(NetworkConfig memory network) internal view returns (E2EState memory state) {
        string memory filePath = getStateFilePath(network);

        try vm.readFile(filePath) returns (string memory json) {
            state.network = abi.decode(vm.parseJson(json, ".network"), (string));
            state.chainId = abi.decode(vm.parseJson(json, ".chainId"), (uint256));
            state.claimdrop = abi.decode(vm.parseJson(json, ".claimdrop"), (address));
            state.rewardToken = abi.decode(vm.parseJson(json, ".rewardToken"), (address));
            state.campaignStartTime = uint64(abi.decode(vm.parseJson(json, ".campaignStartTime"), (uint256)));
            state.campaignEndTime = uint64(abi.decode(vm.parseJson(json, ".campaignEndTime"), (uint256)));
            state.lastCompletedPhase = uint8(abi.decode(vm.parseJson(json, ".lastCompletedPhase"), (uint256)));
            state.timestamp = abi.decode(vm.parseJson(json, ".timestamp"), (uint256));
            state.totalClaimed = abi.decode(vm.parseJson(json, ".totalClaimed"), (uint256));

            console.log("State loaded from:", filePath);
            console.log("  Last completed phase:", state.lastCompletedPhase);
        } catch {
            console.log("No existing state file found");
            state.lastCompletedPhase = 0;
        }

        return state;
    }

    // ============ Report Generation ============

    /**
     * @notice Get report file path for network
     * @param network Network configuration
     * @return path Full path to report file
     */
    function getReportFilePath(NetworkConfig memory network) internal view returns (string memory path) {
        // Include timestamp in filename for multiple runs
        string memory timestamp = vm.toString(block.timestamp);
        return string.concat(REPORT_DIR, "/e2e-report-", network.name, "-", timestamp, ".md");
    }

    /**
     * @notice Generate markdown report header
     * @param network Network configuration
     * @return header Markdown header string
     */
    function generateReportHeader(NetworkConfig memory network) internal view returns (string memory header) {
        header = string.concat(
            "# E2E Orchestration Report\n\n",
            "**Network:** ",
            network.name,
            "\n",
            "**ChainID:** ",
            vm.toString(network.chainId),
            "\n",
            "**Profile:** ",
            network.profile,
            "\n",
            "**Timestamp:** ",
            vm.toString(block.timestamp),
            "\n\n"
        );
        return header;
    }

    /**
     * @notice Format explorer link for address
     * @param network Network configuration
     * @param addr Address to link
     * @return link Formatted markdown link
     */
    function formatExplorerLink(NetworkConfig memory network, address addr) internal pure returns (string memory link) {
        if (bytes(network.explorerUrl).length == 0) {
            return vm.toString(addr);
        }
        string memory url = getExplorerAddressUrl(network, addr);
        return string.concat("[", vm.toString(addr), "](", url, ")");
    }

    // ============ Logging Helpers ============

    /**
     * @notice Log phase header
     * @param phaseNum Current phase number
     * @param totalPhases Total number of phases
     * @param description Phase description
     */
    function logPhaseHeader(uint256 phaseNum, uint256 totalPhases, string memory description) internal view {
        console.log("");
        console.log("=================================================");
        console.log(string.concat("Phase ", vm.toString(phaseNum), "/", vm.toString(totalPhases), ": ", description));
        console.log("=================================================");
    }

    /**
     * @notice Log phase completion
     * @param phaseNum Completed phase number
     * @param totalPhases Total number of phases
     */
    function logPhaseComplete(uint256 phaseNum, uint256 totalPhases) internal view {
        console.log(string.concat("Phase ", vm.toString(phaseNum), "/", vm.toString(totalPhases), " Complete"));
        console.log("");
    }

    /**
     * @notice Log error message
     * @param context Error context
     * @param message Error message
     */
    function logError(string memory context, string memory message) internal view {
        console.log("");
        console.log("ERROR in", context);
        console.log(message);
        console.log("");
    }
}
