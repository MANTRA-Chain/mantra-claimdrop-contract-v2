// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { PrimarySaleClaimdropFactory } from "../contracts/PrimarySaleClaimdropFactory.sol";
import { Claimdrop } from "../contracts/Claimdrop.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract PrimarySaleClaimdropFactoryTest is Test {
    PrimarySaleClaimdropFactory public factory;
    PrimarySaleClaimdropFactory public implementation;
    TransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    address public owner;
    address public user;
    address public proxyAdminOwner;
    address public mockPrimarySale;

    event ClaimdropDeployed(
        address indexed primarySaleAddress, address indexed claimdropAddress, address indexed owner, uint256 index
    );

    function setUp() public {
        owner = address(this);
        user = address(0x1);
        proxyAdminOwner = address(this);
        mockPrimarySale = address(0x999);

        // Deploy the implementation contract
        implementation = new PrimarySaleClaimdropFactory();

        // Prepare initialization data with metadata
        bytes memory initData = abi.encodeWithSelector(
            PrimarySaleClaimdropFactory.initialize.selector,
            owner,
            "Test Factory",
            "test-factory",
            "Test factory for unit tests"
        );

        // Deploy the proxy
        proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdminOwner), initData);

        // Get the ProxyAdmin that was created by the proxy
        // The proxy's admin is stored at ERC1967 admin slot
        bytes32 adminSlot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        address proxyAdminAddress = address(uint160(uint256(vm.load(address(proxy), adminSlot))));
        proxyAdmin = ProxyAdmin(proxyAdminAddress);

        // Wrap the proxy in the factory interface
        factory = PrimarySaleClaimdropFactory(address(proxy));

        // Set the PrimarySale address - THIS WAS MISSING
        factory.setPrimarySaleWithMetadata(mockPrimarySale, 100, 3, 48);
    }

    function testDeployClaimdrop() public {
        // Deploy a new claimdrop
        address claimdropAddress = factory.deployClaimdrop();

        // Verify it was deployed
        assertTrue(claimdropAddress != address(0));
        assertTrue(factory.isClaimdrop(claimdropAddress));

        // Verify the count
        assertEq(factory.getDeployedClaimdropsCount(), 1);

        // Verify the owner is the factory owner
        Claimdrop claimdrop = Claimdrop(claimdropAddress);
        assertEq(claimdrop.owner(), owner);
    }

    function testDeployMultipleClaimdrops() public {
        // Deploy multiple claimdrops
        address claimdrop1 = factory.deployClaimdrop();
        address claimdrop2 = factory.deployClaimdrop();
        address claimdrop3 = factory.deployClaimdrop();

        // Verify count
        assertEq(factory.getDeployedClaimdropsCount(), 3);

        // Verify all are tracked
        assertTrue(factory.isClaimdrop(claimdrop1));
        assertTrue(factory.isClaimdrop(claimdrop2));
        assertTrue(factory.isClaimdrop(claimdrop3));

        // Verify addresses are different
        assertTrue(claimdrop1 != claimdrop2);
        assertTrue(claimdrop2 != claimdrop3);
        assertTrue(claimdrop1 != claimdrop3);
    }

    function testGetAllDeployedClaimdrops() public {
        // Deploy some claimdrops
        address claimdrop1 = factory.deployClaimdrop();
        address claimdrop2 = factory.deployClaimdrop();

        // Get all deployed claimdrops
        address[] memory deployed = factory.getAllDeployedClaimdrops();

        assertEq(deployed.length, 2);
        assertEq(deployed[0], claimdrop1);
        assertEq(deployed[1], claimdrop2);
    }

    function testGetClaimdropAtIndex() public {
        // Deploy some claimdrops
        address claimdrop1 = factory.deployClaimdrop();
        address claimdrop2 = factory.deployClaimdrop();

        // Get by index
        assertEq(factory.getClaimdropAtIndex(0), claimdrop1);
        assertEq(factory.getClaimdropAtIndex(1), claimdrop2);
    }

    function testGetClaimdropAtIndexRevertsOutOfBounds() public {
        factory.deployClaimdrop();

        vm.expectRevert(PrimarySaleClaimdropFactory.IndexOutOfBounds.selector);
        factory.getClaimdropAtIndex(1);
    }

    function testDeployClaimdropEmitsEvent() public {
        vm.expectEmit(true, false, true, true);
        emit ClaimdropDeployed(mockPrimarySale, address(0), owner, 0);
        factory.deployClaimdrop();
    }

    function testOnlyOwnerCanDeploy() public {
        vm.prank(user);
        vm.expectRevert();
        factory.deployClaimdrop();
    }

    function testPauseUnpause() public {
        // Owner can pause
        factory.pause();

        // Cannot deploy when paused
        vm.expectRevert();
        factory.deployClaimdrop();

        // Owner can unpause
        factory.unpause();

        // Can deploy after unpause
        address claimdrop = factory.deployClaimdrop();
        assertTrue(claimdrop != address(0));
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(user);
        vm.expectRevert();
        factory.pause();
    }

    function testOnlyOwnerCanUnpause() public {
        factory.pause();

        vm.prank(user);
        vm.expectRevert();
        factory.unpause();
    }

    function testCannotReinitialize() public {
        vm.expectRevert();
        factory.initialize(user, "New Name", "new-slug", "New description");
    }

    function testUpgrade() public {
        // Deploy some claimdrops with the old implementation
        address claimdrop1 = factory.deployClaimdrop();
        assertEq(factory.getDeployedClaimdropsCount(), 1);

        // Deploy a new implementation
        PrimarySaleClaimdropFactory newImplementation = new PrimarySaleClaimdropFactory();

        // Use upgradeAndCall with empty data as required by OpenZeppelin v5.0.0
        vm.prank(proxyAdminOwner); // Need to be the owner of the proxy admin
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(newImplementation), "");

        // Verify state is preserved
        assertEq(factory.getDeployedClaimdropsCount(), 1);
        assertEq(factory.getClaimdropAtIndex(0), claimdrop1);
        assertTrue(factory.isClaimdrop(claimdrop1));

        // Verify functionality still works
        factory.deployClaimdrop();
        assertEq(factory.getDeployedClaimdropsCount(), 2);
    }

    function testOnlyProxyAdminCanUpgrade() public {
        PrimarySaleClaimdropFactory newImplementation = new PrimarySaleClaimdropFactory();

        // User cannot upgrade
        vm.prank(user);
        vm.expectRevert();
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(newImplementation), "");
    }

    function testProxyAdminOwnership() public view {
        // Verify proxy admin owner
        assertEq(proxyAdmin.owner(), proxyAdminOwner);
    }

    function testImplementationIsInitialized() public {
        // Try to initialize the implementation directly (should fail)
        vm.expectRevert();
        implementation.initialize(user, "Test", "test", "Test description");
    }

    function testMetadataFields() public view {
        // Verify metadata is set correctly
        assertEq(factory.name(), "Test Factory");
        assertEq(factory.slug(), "test-factory");
        assertEq(factory.description(), "Test factory for unit tests");
    }

    function testUpdateMetadata() public {
        // Update metadata
        factory.updateMetadata("New Name", "new-slug", "New description");

        // Verify updated metadata
        assertEq(factory.name(), "New Name");
        assertEq(factory.slug(), "new-slug");
        assertEq(factory.description(), "New description");
    }

    function testOnlyOwnerCanUpdateMetadata() public {
        vm.prank(user);
        vm.expectRevert();
        factory.updateMetadata("Hacked", "hacked", "Hacked description");
    }

    function testCannotDeployClaimdropWithoutPrimarySale() public {
        // Deploy a fresh factory without PrimarySale set
        PrimarySaleClaimdropFactory freshImplementation = new PrimarySaleClaimdropFactory();

        bytes memory initData = abi.encodeWithSelector(
            PrimarySaleClaimdropFactory.initialize.selector,
            owner,
            "Fresh Factory",
            "fresh-factory",
            "Fresh factory without PrimarySale"
        );

        TransparentUpgradeableProxy freshProxy =
            new TransparentUpgradeableProxy(address(freshImplementation), address(proxyAdmin), initData);

        PrimarySaleClaimdropFactory freshFactory = PrimarySaleClaimdropFactory(address(freshProxy));

        // Should revert because PrimarySale is not set
        vm.expectRevert(PrimarySaleClaimdropFactory.PrimarySaleNotSet.selector);
        freshFactory.deployClaimdrop();
    }

    function testGetPrimarySale() public view {
        assertEq(factory.getPrimarySale(), mockPrimarySale);
    }

    function testIsPrimarySaleDeployed() public view {
        assertTrue(factory.isPrimarySaleDeployed());
    }

    function testResetFactory() public {
        // Deploy some claimdrops
        address claimdrop1 = factory.deployClaimdrop();
        address claimdrop2 = factory.deployClaimdrop();

        // Verify state before reset
        assertEq(factory.getDeployedClaimdropsCount(), 2);
        assertTrue(factory.isClaimdrop(claimdrop1));
        assertTrue(factory.isClaimdrop(claimdrop2));
        assertEq(factory.getPrimarySale(), mockPrimarySale);
        assertTrue(factory.isPrimarySaleDeployed());

        // Reset factory
        factory.resetFactory();

        // Verify state after reset
        assertEq(factory.getDeployedClaimdropsCount(), 0);
        assertFalse(factory.isClaimdrop(claimdrop1));
        assertFalse(factory.isClaimdrop(claimdrop2));
        assertEq(factory.getPrimarySale(), address(0));
        assertFalse(factory.isPrimarySaleDeployed());
    }

    function testOnlyOwnerCanResetFactory() public {
        vm.prank(user);
        vm.expectRevert();
        factory.resetFactory();
    }

    function testCanDeployAfterReset() public {
        // Deploy and reset
        factory.deployClaimdrop();
        factory.resetFactory();

        // Set new PrimarySale
        address newPrimarySale = address(0x888);
        factory.setPrimarySaleWithMetadata(newPrimarySale, 100, 3, 48);

        // Should be able to deploy again
        address newClaimdrop = factory.deployClaimdrop();
        assertTrue(newClaimdrop != address(0));
        assertEq(factory.getDeployedClaimdropsCount(), 1);
        assertEq(factory.getPrimarySale(), newPrimarySale);
    }

    function testResetNotAllowedOnMainnet() public {
        // Simulate MANTRA mainnet (chain ID 5888)
        vm.chainId(5888);

        // Should revert when trying to reset on mainnet
        vm.expectRevert(PrimarySaleClaimdropFactory.ResetNotAllowedOnMainnet.selector);
        factory.resetFactory();
    }
}
