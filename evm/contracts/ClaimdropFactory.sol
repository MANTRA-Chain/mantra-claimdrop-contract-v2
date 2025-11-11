// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Claimdrop} from "./Claimdrop.sol";

/**
 * @title ClaimdropFactory
 * @author MANTRA Finance
 * @notice Factory contract for deploying Claimdrop contracts
 * @dev Manages deployment and tracking of Claimdrop instances
 */
contract ClaimdropFactory is Initializable, OwnableUpgradeable, PausableUpgradeable {
    // ============ State Variables ============

    /// @notice Array of all deployed Claimdrop contracts
    address[] public deployedClaimdrops;

    /// @notice Mapping to check if an address is a deployed Claimdrop
    mapping(address => bool) public isClaimdrop;

    // ============ Events ============

    /// @notice Emitted when a new Claimdrop is deployed
    /// @param claimdropAddress Address of the newly deployed Claimdrop
    /// @param owner Owner of the Claimdrop (factory owner)
    /// @param index Index in the deployedClaimdrops array
    event ClaimdropDeployed(
        address indexed claimdropAddress,
        address indexed owner,
        uint256 index
    );

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize factory with owner
    /// @param initialOwner Address of the initial owner
    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();
    }

    // ============ External Functions ============

    /// @notice Deploy a new Claimdrop contract
    /// @dev Owner of the new Claimdrop will be the factory owner
    /// @return claimdropAddress Address of the newly deployed Claimdrop
    function deployClaimdrop() external onlyOwner whenNotPaused returns (address claimdropAddress) {
        // Deploy new Claimdrop with factory owner as the owner
        Claimdrop claimdrop = new Claimdrop(owner());
        claimdropAddress = address(claimdrop);

        // Track the deployed contract
        deployedClaimdrops.push(claimdropAddress);
        isClaimdrop[claimdropAddress] = true;

        emit ClaimdropDeployed(claimdropAddress, owner(), deployedClaimdrops.length - 1);
    }

    /// @notice Get the total number of deployed Claimdrops
    /// @return count Total number of deployed Claimdrops
    function getDeployedClaimdropsCount() external view returns (uint256 count) {
        return deployedClaimdrops.length;
    }

    /// @notice Get all deployed Claimdrop addresses
    /// @return addresses Array of all deployed Claimdrop addresses
    function getAllDeployedClaimdrops() external view returns (address[] memory addresses) {
        return deployedClaimdrops;
    }

    /// @notice Get a specific deployed Claimdrop by index
    /// @param index Index in the deployedClaimdrops array
    /// @return claimdropAddress Address of the Claimdrop at the given index
    function getClaimdropAtIndex(uint256 index) external view returns (address claimdropAddress) {
        require(index < deployedClaimdrops.length, "Index out of bounds");
        return deployedClaimdrops[index];
    }

    // ============ Owner Functions ============

    /// @notice Pause the factory
    /// @dev Only owner can pause
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the factory
    /// @dev Only owner can unpause
    function unpause() external onlyOwner {
        _unpause();
    }
}
