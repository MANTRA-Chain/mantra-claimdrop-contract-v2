// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @title E2ENetworkConfig
 * @notice Network configuration and detection for multi-network E2E testing
 * @dev Loads network configs from config/networks.json and provides network-aware utilities
 *
 * Usage:
 *   1. Inherit from this contract in your scripts
 *   2. Call getNetworkConfig() to load config based on NETWORK env var or auto-detect
 *   3. Use timing profile functions to get network-appropriate test parameters
 *
 * Environment Variables:
 *   - NETWORK: Target network name (local, dukong, canary, mainnet)
 *   - MANTRA_DUKONG_RPC_URL: DuKong testnet RPC endpoint
 *   - MANTRA_CANARY_RPC_URL: Canary staging network RPC endpoint
 *   - MANTRA_MAINNET_RPC_URL: Mainnet RPC endpoint
 */
contract E2ENetworkConfig is Script {
    using stdJson for string;

    /// @notice Network configuration structure
    struct NetworkConfig {
        string name;
        uint256 chainId;
        string rpcUrl;
        string explorerUrl;
        string explorerApiUrl;
        string faucetUrl;
        string profile;
        uint256 blockTime;
        string description;
    }

    /// @notice Timing profile for network-specific test durations
    struct TimingProfile {
        string name;
        string description;
        uint256 campaignDuration;
        uint256 vestingDuration;
        uint256 startDelay;
        uint256 cliffDuration;
        uint16 lumpSumPercentageBps;
        uint16 vestingPercentageBps;
    }

    /// @notice Path to network configuration file
    string internal constant CONFIG_PATH = "./config/networks.json";

    /// @notice Cached network configurations
    mapping(string => NetworkConfig) internal networkConfigs;

    /// @notice Cached timing profiles
    mapping(string => TimingProfile) internal timingProfiles;

    /// @notice Whether configs have been loaded
    bool internal configsLoaded;

    /**
     * @notice Get network configuration (auto-detect or from NETWORK env var)
     * @return config Network configuration
     */
    function getNetworkConfig() internal returns (NetworkConfig memory config) {
        // Check if NETWORK env var is set
        string memory networkName = vm.envOr("NETWORK", string(""));

        if (bytes(networkName).length > 0) {
            // Load config for specified network
            config = loadNetworkConfig(networkName);
        } else {
            // Auto-detect from chain ID
            config = detectNetworkByChainId();
        }

        // Validate network
        validateNetwork(config);

        return config;
    }

    /**
     * @notice Load network configuration by name
     * @param networkName Network identifier (local, dukong, canary, mainnet)
     * @return config Network configuration
     */
    function loadNetworkConfig(string memory networkName) internal returns (NetworkConfig memory config) {
        // Load configs if not already loaded
        if (!configsLoaded) {
            loadAllConfigs();
        }

        // Check if network exists in cache
        config = networkConfigs[networkName];

        if (bytes(config.name).length == 0) {
            // Network not found, try to load from JSON
            config = parseNetworkFromJson(networkName);
            require(bytes(config.name).length > 0, string.concat("Network '", networkName, "' not found in config"));

            // Cache for future use
            networkConfigs[networkName] = config;
        }

        // Resolve environment variables in rpcUrl
        config.rpcUrl = resolveEnvVar(config.rpcUrl);

        return config;
    }

    /**
     * @notice Detect network configuration from current chain ID
     * @return config Network configuration matching current chain
     */
    function detectNetworkByChainId() internal returns (NetworkConfig memory config) {
        uint256 chainId = block.chainid;

        console.log("Auto-detecting network from ChainID:", chainId);

        // Map chain ID to network name
        if (chainId == 31337) {
            return loadNetworkConfig("local");
        } else if (chainId == 5887) {
            return loadNetworkConfig("dukong");
        } else if (chainId == 7888) {
            return loadNetworkConfig("canary");
        } else if (chainId == 5888) {
            return loadNetworkConfig("mainnet");
        } else {
            revert(
                string.concat(
                    "Unknown ChainID: ",
                    vm.toString(chainId),
                    ". Set NETWORK env var or add network to config/networks.json"
                )
            );
        }
    }

    /**
     * @notice Validate that connected RPC matches expected network
     * @param config Network configuration to validate
     */
    function validateNetwork(NetworkConfig memory config) internal view {
        uint256 actualChainId = block.chainid;

        if (actualChainId != config.chainId) {
            console.log("ERROR: ChainID mismatch!");
            console.log("Expected ChainID:", config.chainId);
            console.log("Expected Network:", config.name);
            console.log("Actual ChainID:", actualChainId);
            revert(
                string.concat(
                    "ChainID mismatch: expected ",
                    vm.toString(config.chainId),
                    " (",
                    config.name,
                    "), got ",
                    vm.toString(actualChainId),
                    ". Check your RPC_URL."
                )
            );
        }

        console.log("Network validated:");
        console.log("  Name:", config.name);
        console.log("  ChainID:", config.chainId);
        console.log("  Profile:", config.profile);
    }

    /**
     * @notice Get timing profile for network
     * @param config Network configuration
     * @return profile Timing profile for the network
     */
    function getTimingProfile(NetworkConfig memory config) internal returns (TimingProfile memory profile) {
        return getTimingProfileByName(config.profile);
    }

    /**
     * @notice Get timing profile by name
     * @param profileName Profile identifier (fast, testnet, staging, mainnet)
     * @return profile Timing profile
     */
    function getTimingProfileByName(string memory profileName) internal returns (TimingProfile memory profile) {
        // Load configs if not already loaded
        if (!configsLoaded) {
            loadAllConfigs();
        }

        // Check cache
        profile = timingProfiles[profileName];

        if (bytes(profile.name).length == 0) {
            // Not cached, load from JSON
            profile = parseProfileFromJson(profileName);
            require(
                bytes(profile.name).length > 0, string.concat("Profile '", profileName, "' not found in config")
            );

            // Cache for future use
            timingProfiles[profileName] = profile;
        }

        return profile;
    }

    /**
     * @notice Load all network configs and profiles from JSON
     */
    function loadAllConfigs() internal {
        // Load config file
        string memory configJson = vm.readFile(CONFIG_PATH);

        // Parse and cache all networks
        string[] memory networkNames = new string[](4);
        networkNames[0] = "local";
        networkNames[1] = "dukong";
        networkNames[2] = "canary";
        networkNames[3] = "mainnet";

        for (uint256 i = 0; i < networkNames.length; i++) {
            NetworkConfig memory config = parseNetworkFromJsonString(configJson, networkNames[i]);
            if (bytes(config.name).length > 0) {
                networkConfigs[networkNames[i]] = config;
            }
        }

        // Parse and cache all profiles
        string[] memory profileNames = new string[](4);
        profileNames[0] = "fast";
        profileNames[1] = "testnet";
        profileNames[2] = "staging";
        profileNames[3] = "mainnet";

        for (uint256 i = 0; i < profileNames.length; i++) {
            TimingProfile memory profile = parseProfileFromJsonString(configJson, profileNames[i]);
            if (bytes(profile.name).length > 0) {
                timingProfiles[profileNames[i]] = profile;
            }
        }

        configsLoaded = true;
        console.log("Loaded network configurations from", CONFIG_PATH);
    }

    /**
     * @notice Parse network configuration from JSON file
     * @param networkName Network identifier
     * @return config Parsed network configuration
     */
    function parseNetworkFromJson(string memory networkName) internal view returns (NetworkConfig memory config) {
        string memory configJson = vm.readFile(CONFIG_PATH);
        return parseNetworkFromJsonString(configJson, networkName);
    }

    /**
     * @notice Parse network configuration from JSON string
     * @param configJson JSON string
     * @param networkName Network identifier
     * @return config Parsed network configuration
     */
    function parseNetworkFromJsonString(string memory configJson, string memory networkName)
        internal
        pure
        returns (NetworkConfig memory config)
    {
        string memory basePath = string.concat(".networks.", networkName);

        // Check if network exists
        try vm.parseJsonString(configJson, string.concat(basePath, ".name")) returns (string memory name) {
            config.name = name;
            config.chainId = abi.decode(vm.parseJson(configJson, string.concat(basePath, ".chainId")), (uint256));
            config.rpcUrl = abi.decode(vm.parseJson(configJson, string.concat(basePath, ".rpcUrl")), (string));
            config.explorerUrl =
                abi.decode(vm.parseJson(configJson, string.concat(basePath, ".explorerUrl")), (string));
            config.explorerApiUrl =
                abi.decode(vm.parseJson(configJson, string.concat(basePath, ".explorerApiUrl")), (string));
            config.faucetUrl = abi.decode(vm.parseJson(configJson, string.concat(basePath, ".faucetUrl")), (string));
            config.profile = abi.decode(vm.parseJson(configJson, string.concat(basePath, ".profile")), (string));
            config.blockTime = abi.decode(vm.parseJson(configJson, string.concat(basePath, ".blockTime")), (uint256));
            config.description =
                abi.decode(vm.parseJson(configJson, string.concat(basePath, ".description")), (string));
        } catch {
            // Network doesn't exist in config
            config.name = "";
        }

        return config;
    }

    /**
     * @notice Parse timing profile from JSON file
     * @param profileName Profile identifier
     * @return profile Parsed timing profile
     */
    function parseProfileFromJson(string memory profileName) internal view returns (TimingProfile memory profile) {
        string memory configJson = vm.readFile(CONFIG_PATH);
        return parseProfileFromJsonString(configJson, profileName);
    }

    /**
     * @notice Parse timing profile from JSON string
     * @param configJson JSON string
     * @param profileName Profile identifier
     * @return profile Parsed timing profile
     */
    function parseProfileFromJsonString(string memory configJson, string memory profileName)
        internal
        pure
        returns (TimingProfile memory profile)
    {
        string memory basePath = string.concat(".profiles.", profileName);

        // Check if profile exists
        try vm.parseJsonString(configJson, string.concat(basePath, ".name")) returns (string memory name) {
            profile.name = name;
            profile.description =
                abi.decode(vm.parseJson(configJson, string.concat(basePath, ".description")), (string));
            profile.campaignDuration =
                abi.decode(vm.parseJson(configJson, string.concat(basePath, ".campaignDuration")), (uint256));
            profile.vestingDuration =
                abi.decode(vm.parseJson(configJson, string.concat(basePath, ".vestingDuration")), (uint256));
            profile.startDelay = abi.decode(vm.parseJson(configJson, string.concat(basePath, ".startDelay")), (uint256));
            profile.cliffDuration =
                abi.decode(vm.parseJson(configJson, string.concat(basePath, ".cliffDuration")), (uint256));
            profile.lumpSumPercentageBps =
                uint16(abi.decode(vm.parseJson(configJson, string.concat(basePath, ".lumpSumPercentageBps")), (uint256)));
            profile.vestingPercentageBps =
                uint16(abi.decode(vm.parseJson(configJson, string.concat(basePath, ".vestingPercentageBps")), (uint256)));
        } catch {
            // Profile doesn't exist in config
            profile.name = "";
        }

        return profile;
    }

    /**
     * @notice Resolve environment variable placeholders in string
     * @param value String potentially containing ${VAR_NAME} placeholders
     * @return resolved String with environment variables resolved
     */
    function resolveEnvVar(string memory value) internal view returns (string memory resolved) {
        // Check if value contains ${...}
        bytes memory valueBytes = bytes(value);

        // Simple implementation: check for specific known patterns
        if (keccak256(valueBytes) == keccak256(bytes("${MANTRA_DUKONG_RPC_URL}"))) {
            resolved = vm.envOr("MANTRA_DUKONG_RPC_URL", string("https://evm.dukong.mantrachain.io"));
        } else if (keccak256(valueBytes) == keccak256(bytes("${MANTRA_CANARY_RPC_URL}"))) {
            resolved = vm.envOr("MANTRA_CANARY_RPC_URL", string("https://evm.canary.mantrachain.dev"));
        } else if (keccak256(valueBytes) == keccak256(bytes("${MANTRA_MAINNET_RPC_URL}"))) {
            resolved = vm.envOr("MANTRA_MAINNET_RPC_URL", string("https://evm.mantrachain.io"));
        } else {
            // No environment variable, return as-is
            resolved = value;
        }

        return resolved;
    }

    /**
     * @notice Log network information for debugging
     * @param config Network configuration
     */
    function logNetworkInfo(NetworkConfig memory config) internal view {
        console.log("=== Network Information ===");
        console.log("Name:", config.name);
        console.log("ChainID:", config.chainId);
        console.log("RPC URL:", config.rpcUrl);
        console.log("Explorer:", config.explorerUrl);
        console.log("Profile:", config.profile);
        console.log("Block Time (seconds):", config.blockTime);
        console.log("Description:", config.description);
        if (bytes(config.faucetUrl).length > 0) {
            console.log("Faucet:", config.faucetUrl);
        }
        console.log("===========================");
    }

    /**
     * @notice Log timing profile information
     * @param profile Timing profile
     */
    function logTimingProfile(TimingProfile memory profile) internal view {
        console.log("=== Timing Profile ===");
        console.log("Name:", profile.name);
        console.log("Description:", profile.description);
        console.log("Campaign Duration (seconds):", profile.campaignDuration);
        console.log("Vesting Duration (seconds):", profile.vestingDuration);
        console.log("Start Delay (seconds):", profile.startDelay);
        console.log("Cliff Duration (seconds):", profile.cliffDuration);
        console.log("Lump Sum Percentage (bps):", profile.lumpSumPercentageBps);
        console.log("Vesting Percentage (bps):", profile.vestingPercentageBps);
        console.log("======================");
    }

    /**
     * @notice Get explorer transaction URL for network
     * @param config Network configuration
     * @param txHash Transaction hash
     * @return url Full explorer URL
     */
    function getExplorerTxUrl(NetworkConfig memory config, bytes32 txHash)
        internal
        pure
        returns (string memory url)
    {
        if (bytes(config.explorerUrl).length == 0) {
            return "";
        }

        return string.concat(config.explorerUrl, "/tx/", vm.toString(txHash));
    }

    /**
     * @notice Get explorer address URL for network
     * @param config Network configuration
     * @param addr Address to view
     * @return url Full explorer URL
     */
    function getExplorerAddressUrl(NetworkConfig memory config, address addr)
        internal
        pure
        returns (string memory url)
    {
        if (bytes(config.explorerUrl).length == 0) {
            return "";
        }

        return string.concat(config.explorerUrl, "/address/", vm.toString(addr));
    }
}
