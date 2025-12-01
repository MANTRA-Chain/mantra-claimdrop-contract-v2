// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Claimdrop } from "./Claimdrop.sol";

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

    /// @notice Address of the receipt token
    address public receiptToken;

    /// @notice Address of the receipt token owner
    address public receiptTokenOwner;

    /// @notice Interest rate in basis points
    uint256 public rateInBps;

    /// @notice Interest-only period duration
    uint256 public interestOnlyPeriod;

    /// @notice Repayment period duration
    uint256 public repaymentPeriod;

    // ============ Events ============

    /// @notice Emitted when a new Claimdrop is deployed
    /// @param primarySaleAddress Address of the associated PrimarySale
    /// @param claimdropAddress Address of the newly deployed Claimdrop
    /// @param owner Owner of the Claimdrop (factory owner)
    /// @param index Index in the deployedClaimdrops array
    event ClaimdropDeployed(
        address indexed primarySaleAddress, address indexed claimdropAddress, address indexed owner, uint256 index
    );

    /// @notice Emitted when PrimarySale is set with metadata
    /// @param primarySaleAddress Address of the newly deployed PrimarySale
    /// @param admin Admin of the PrimarySale
    /// @param rateInBps Interest rate in basis points
    /// @param interestOnlyPeriod Interest-only period duration
    /// @param repaymentPeriod Repayment period duration
    event PrimarySaleSet(
        address indexed primarySaleAddress,
        address indexed admin,
        uint256 rateInBps,
        uint256 interestOnlyPeriod,
        uint256 repaymentPeriod
    );

    /// @notice Emitted when receipt token is updated
    /// @param receiptTokenAddress Address of the receipt token
    /// @param admin Admin who set the receipt token
    event ReceiptTokenSet(address indexed receiptTokenAddress, address indexed admin);

    /// @notice Emitted when receipt token owner is updated
    /// @param receiptTokenOwnerAddress Address of the receipt token owner
    /// @param admin Admin who set the receipt token owner
    event ReceiptTokenOwnerSet(address indexed receiptTokenOwnerAddress, address indexed admin);

    /// @notice Emitted when factory is reset
    event FactoryReset();

    // ============ Errors ============

    error PrimarySaleAlreadyDeployed();
    error InvalidAddress();
    error PrimarySaleNotSet();
    error ResetNotAllowedOnMainnet();
    error EmptyString();
    error StringTooLong();
    error InvalidSlugFormat();
    error IndexOutOfBounds();
    error NotERC20Token();

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
    )
        public
        initializer
    {
        __Ownable_init(initialOwner);
        __Pausable_init();
        _validateString(name_, 100);
        _validateSlug(slug_, 50);
        _validateString(description_, 500);
        name = name_;
        slug = slug_;
        description = description_;
    }

    // ============ External Functions ============

    /// @notice Deploy a new Claimdrop contract
    /// @dev Owner of the new Claimdrop will be the factory owner
    /// @dev Requires PrimarySale to be set before deploying Claimdrops
    /// @return claimdropAddress Address of the newly deployed Claimdrop
    function deployClaimdrop() external onlyOwner whenNotPaused returns (address claimdropAddress) {
        if (primarySale == address(0)) revert PrimarySaleNotSet();

        // Deploy new Claimdrop with factory owner as the owner
        Claimdrop claimdrop = new Claimdrop(owner());
        claimdropAddress = address(claimdrop);

        // Track the deployed contract
        deployedClaimdrops.push(claimdropAddress);
        isClaimdrop[claimdropAddress] = true;

        emit ClaimdropDeployed(primarySale, claimdropAddress, owner(), deployedClaimdrops.length - 1);
    }

    /// @notice Set the PrimarySale contract address with metadata
    /// @dev PrimarySale must be deployed externally to avoid contract size limits
    /// @dev This is the only way to set primarySale, rateInBps, interestOnlyPeriod, and repaymentPeriod
    /// @param primarySale_ Address of the deployed PrimarySale contract
    /// @param rateInBps_ Interest rate in basis points
    /// @param interestOnlyPeriod_ Interest-only period duration
    /// @param repaymentPeriod_ Repayment period duration
    function setPrimarySaleWithMetadata(
        address primarySale_,
        uint256 rateInBps_,
        uint256 interestOnlyPeriod_,
        uint256 repaymentPeriod_
    )
        external
        onlyOwner
        whenNotPaused
    {
        if (primarySale != address(0)) revert PrimarySaleAlreadyDeployed();
        if (primarySale_ == address(0)) revert InvalidAddress();

        primarySale = primarySale_;
        rateInBps = rateInBps_;
        interestOnlyPeriod = interestOnlyPeriod_;
        repaymentPeriod = repaymentPeriod_;

        emit PrimarySaleSet(primarySale_, owner(), rateInBps_, interestOnlyPeriod_, repaymentPeriod_);
    }

    /// @notice Set the receipt token address
    /// @param receiptToken_ Address of the receipt token contract
    function setReceiptToken(address receiptToken_) external onlyOwner {
        if (receiptToken_ == address(0)) revert InvalidAddress();

        // Validate it's an ERC-20 token by checking if it implements totalSupply()
        try IERC20(receiptToken_).totalSupply() returns (uint256) {
            // Successfully called totalSupply, it's likely an ERC-20
            receiptToken = receiptToken_;
            emit ReceiptTokenSet(receiptToken_, owner());
        } catch {
            revert NotERC20Token();
        }
    }

    /// @notice Set the receipt token owner address
    /// @param receiptTokenOwner_ Address of the receipt token owner
    function setReceiptTokenOwner(address receiptTokenOwner_) external onlyOwner {
        if (receiptTokenOwner_ == address(0)) revert InvalidAddress();

        receiptTokenOwner = receiptTokenOwner_;
        emit ReceiptTokenOwnerSet(receiptTokenOwner_, owner());
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
        if (index >= deployedClaimdrops.length) revert IndexOutOfBounds();
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
    function updateMetadata(string memory name_, string memory slug_, string memory description_) external onlyOwner {
        _validateString(name_, 100);
        _validateSlug(slug_, 50);
        _validateString(description_, 500);
        name = name_;
        slug = slug_;
        description = description_;
    }

    /// @notice Reset factory state for testing purposes
    /// @dev Clears all deployed Claimdrops and resets PrimarySale
    /// @dev Only callable on testnets - reverts on MANTRA Mainnet (chain ID 5888)
    /// @dev WARNING: This is intended for testing only.
    function resetFactory() external onlyOwner {
        // Block reset on MANTRA Mainnet (chain ID 5888)
        if (block.chainid == 5888) {
            revert ResetNotAllowedOnMainnet();
        }

        // Clear all deployed claimdrops
        for (uint256 i = 0; i < deployedClaimdrops.length; i++) {
            delete isClaimdrop[deployedClaimdrops[i]];
        }
        delete deployedClaimdrops;

        // Reset primary sale
        primarySale = address(0);

        // Reset receipt token
        receiptToken = address(0);

        // Reset receipt token owner
        receiptTokenOwner = address(0);

        // Reset rate and periods
        rateInBps = 0;
        interestOnlyPeriod = 0;
        repaymentPeriod = 0;

        emit FactoryReset();
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

    // ============ Internal Functions ============

    /// @notice Validate string length
    /// @param str String to validate
    /// @param maxLength Maximum allowed length
    function _validateString(string memory str, uint256 maxLength) internal pure {
        bytes memory strBytes = bytes(str);
        if (strBytes.length == 0) revert EmptyString();
        if (strBytes.length > maxLength) revert StringTooLong();
    }

    /// @notice Validate slug is URL-friendly (lowercase letters, numbers, hyphens only)
    /// @param slug_ Slug to validate
    /// @param maxLength Maximum allowed length
    function _validateSlug(string memory slug_, uint256 maxLength) internal pure {
        bytes memory slugBytes = bytes(slug_);
        if (slugBytes.length == 0) revert EmptyString();
        if (slugBytes.length > maxLength) revert StringTooLong();

        // Check each character is lowercase letter (a-z), number (0-9), or hyphen (-)
        for (uint256 i = 0; i < slugBytes.length; i++) {
            bytes1 char = slugBytes[i];
            bool isLowercase = char >= 0x61 && char <= 0x7A; // a-z
            bool isNumber = char >= 0x30 && char <= 0x39; // 0-9
            bool isHyphen = char == 0x2D; // -

            if (!isLowercase && !isNumber && !isHyphen) {
                revert InvalidSlugFormat();
            }
        }
    }
}
