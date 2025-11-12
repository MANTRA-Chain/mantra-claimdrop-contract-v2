// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PrimarySaleClaimdropFactory} from "../contracts/PrimarySaleClaimdropFactory.sol";
import {Claimdrop} from "../contracts/Claimdrop.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract PrimarySaleClaimdropFactoryTest is Test {
    PrimarySaleClaimdropFactory public factory;
    PrimarySaleClaimdropFactory public implementation;
    TransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    address public owner;
    address public user;
    address public proxyAdminOwner;

    event ClaimdropDeployed(
        address indexed claimdropAddress,
        address indexed owner,
        uint256 index
    );

    function setUp() public {
        owner = address(this);
        user = address(0x1);
        proxyAdminOwner = address(this);

        // Deploy the implementation contract
        implementation = new PrimarySaleClaimdropFactory();

        // Deploy ProxyAdmin (no constructor args in newer versions)
        proxyAdmin = new ProxyAdmin();

        // Prepare initialization data with metadata
        bytes memory initData = abi.encodeWithSelector(
            PrimarySaleClaimdropFactory.initialize.selector,
            owner,
            "Test Factory",
            "test-factory",
            "Test factory for unit tests"
        );

        // Deploy the proxy
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        // Wrap the proxy in the factory interface
        factory = PrimarySaleClaimdropFactory(address(proxy));
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

        vm.expectRevert("Index out of bounds");
        factory.getClaimdropAtIndex(1);
    }

    function testDeployClaimdropEmitsEvent() public {
        vm.expectEmit(false, true, false, true);
        emit ClaimdropDeployed(address(0), owner, 0);
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

        // Upgrade the proxy to the new implementation
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(address(proxy)),
            address(newImplementation)
        );

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
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(address(proxy)),
            address(newImplementation)
        );
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
}

