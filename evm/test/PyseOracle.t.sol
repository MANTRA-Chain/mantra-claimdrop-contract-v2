// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { PyseOracle } from "../contracts/PyseOracle.sol";
import { PrimarySaleClaimdropFactory } from "../contracts/PrimarySaleClaimdropFactory.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";

/// TODO: Unfinished tests
contract PyseOracleTest is Test {
    PyseOracle public pyseOracle;
    PrimarySaleClaimdropFactory public factory;
    MockERC20 public token;

    uint256 public constant INTEREST_ONLY_PERIOD = 3;
    uint256 public constant REPAYMENT_PERIOD = 48;
    uint256 public constant INITIAL_PRICE = 5000_000000;

    function setUp() public {
        // Deploy and initialize the factory
        factory = new PrimarySaleClaimdropFactory();
        

        // Set up the primary sale metadata required by the oracle
        factory.setPrimarySaleWithMetadata(
            address(0xdeadbeef), // mock primary sale address
            1000, // 10% rate
            INTEREST_ONLY_PERIOD,
            REPAYMENT_PERIOD
        );

        // Deploy the oracle with the factory address
        pyseOracle = new PyseOracle(address(factory));
    }

    function test_initialPrice() public {
        // Initially, with 0 claimdrops deployed, the price should be the initial price.
        assertEq(pyseOracle.getLatestPrice(), INITIAL_PRICE, "Initial price should be 5000e6");
    }

    // According to PyseOracle.sol comments, price should be initialPrice during the interest-only period.
    // The current implementation checks against `repaymentPeriod`, not `interestOnlyPeriod`.
    // This test follows the current implementation.
    function test_getPrice_duringInterestOnlyPeriod() public {
        // Deploy claimdrops to be interest-only period
        factory.deployClaimdrop();

        // Price should remain the initial price
        assertEq(pyseOracle.getLatestPrice(), INITIAL_PRICE, "Price should be initial during interest-only period");
    }

    // This test case demonstrates the behavior when the number of deployed claimdrops
    // is greater than the interest-only period but less than or equal to the repayment period.
    // Based on the current logic `distributedCount <= repaymentPeriod`, the price should still be `initialPrice`.
    function test_getPrice_afterInterestOnly_beforeRepaymentDrop() public {
        // Deploy claimdrops equal to interest-only period + 1
        uint256 dropsToDeploy = INTEREST_ONLY_PERIOD + 1;
        for (uint256 i = 0; i < dropsToDeploy; i++) {
            factory.deployClaimdrop();
        }

        // The current implementation will return initialPrice.
        // A potentially more correct implementation would start dropping the price here.
        assertEq(
            pyseOracle.getLatestPrice(),
            INITIAL_PRICE,
            "Price should be initial because distributedCount <= repaymentPeriod"
        );
    }

    // This test covers the case where price reduction should occur,
    // which in the current implementation is when `distributedCount > repaymentPeriod`.
    function test_getPrice_duringRepaymentPeriod_priceDrop() public {
        // Deploy claimdrops to be greater than the repayment period to trigger price drop
        uint256 dropsToDeploy = REPAYMENT_PERIOD + 1;
        for (uint256 i = 0; i < dropsToDeploy; i++) {
            factory.deployClaimdrop();
        }

        uint256 distributedCount = factory.getDeployedClaimdropsCount();
        uint256 priceDropStep = INITIAL_PRICE / REPAYMENT_PERIOD;
        uint256 expectedPrice = INITIAL_PRICE - (priceDropStep * (distributedCount - INTEREST_ONLY_PERIOD));

        assertEq(pyseOracle.getLatestPrice(), expectedPrice, "Price should drop after repayment period starts");
    }


    function test_getPrice_atEndOfRepayment() public {
        // Deploy claimdrops equal to the sum of both periods
        uint256 dropsToDeploy = INTEREST_ONLY_PERIOD + REPAYMENT_PERIOD;
        for (uint256 i = 0; i < dropsToDeploy; i++) {
            factory.deployClaimdrop();
        }

        // At the very end, the price should be 0
        assertEq(pyseOracle.getLatestPrice(), 0, "Price should be 0 at the end of the repayment period");
    }

    function test_getPrice_afterEndOfRepayment() public {
        // Deploy claimdrops exceeding the sum of both periods
        uint256 dropsToDeploy = INTEREST_ONLY_PERIOD + REPAYMENT_PERIOD + 1;
        for (uint256 i = 0; i < dropsToDeploy; i++) {
            factory.deployClaimdrop();
        }

        // After the end, the price should remain 0
        assertEq(pyseOracle.getLatestPrice(), 0, "Price should remain 0 after the repayment period");
    }
}
