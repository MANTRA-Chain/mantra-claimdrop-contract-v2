// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Claimdrop} from "./Claimdrop.sol";

/**
 * @title PrimarySaleClaimdropFactory
 * @author MANTRA Finance
 * @notice Factory contract for deploying Claimdrop and PrimarySale contracts
 * @dev Manages deployment and tracking of Claimdrop instances and a single PrimarySale instance
 */
contract PrimarySaleClaimdropFactory is Initializable, OwnableUpgradeable, PausableUpgradeable {
    // ============ State Variables ============

    /// @notice Human-readable name of the factory
    string public name;

    /// @notice URL-friendly identifier
    string public slug;

    /// @notice Description of the factory's purpose
    string public description;

    /// @notice Array of all deployed Claimdrop contracts
    address[] public deployedClaimdrops;

    /// @notice Mapping to check if an address is a deployed Claimdrop
    mapping(address => bool) public isClaimdrop;

    /// @notice Address of the deployed PrimarySale contract (only one allowed)
    address public primarySale;

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

    /// @notice Emitted when PrimarySale is deployed
    /// @param primarySaleAddress Address of the newly deployed PrimarySale
    /// @param admin Admin of the PrimarySale
    event PrimarySaleSet(
        address indexed primarySaleAddress,
        address indexed admin
    );

    // ============ Errors ============

    error PrimarySaleAlreadyDeployed();
    error InvalidAddress();

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize factory with owner
    /// @param initialOwner Address of the initial owner
    /// @param name_ Human-readable name of the factory
    /// @param slug_ URL-friendly identifier
    /// @param description_ Description of the factory's purpose
    function initialize(
        address initialOwner,
        string memory name_,
        string memory slug_,
        string memory description_
    ) public initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();
        
        name = name_;
        slug = slug_;
        description = description_;
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

    /// @notice Set the PrimarySale contract address (only one allowed)
    /// @dev PrimarySale must be deployed externally to avoid contract size limits
    /// @param primarySale_ Address of the deployed PrimarySale contract
    function setPrimarySale(address primarySale_) external onlyOwner whenNotPaused {
        if (primarySale != address(0)) revert PrimarySaleAlreadyDeployed();
        if (primarySale_ == address(0)) revert InvalidAddress();

        primarySale = primarySale_;

        emit PrimarySaleSet(primarySale_, owner());
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

    /// @notice Get the deployed PrimarySale address
    /// @return Address of the PrimarySale contract (address(0) if not deployed)
    function getPrimarySale() external view returns (address) {
        return primarySale;
    }

    /// @notice Check if PrimarySale has been deployed
    /// @return True if PrimarySale exists
    function isPrimarySaleDeployed() external view returns (bool) {
        return primarySale != address(0);
    }

    /// @notice Update factory metadata
    /// @param name_ New name
    /// @param slug_ New slug
    /// @param description_ New description
    function updateMetadata(
        string memory name_,
        string memory slug_,
        string memory description_
    ) external onlyOwner {
        name = name_;
        slug = slug_;
        description = description_;
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
