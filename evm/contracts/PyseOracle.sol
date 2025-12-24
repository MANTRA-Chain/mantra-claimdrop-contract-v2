/// NOTES:
/// Initial price $5000
/// Read data from PrimarySaleClaimdropFactory and calculate
/// interestOnlyPeriod: 3
/// repaymentPeriod: 48
/// The first <interestOnlyPeriod> months pay interest
/// Starts from the <interestOnlyPeriod + 1>th month, pay principle + interest
/// Token price drops after principle is paid
/// deployedClaimdrops.length - <interestOnlyPeriod> > 0 to determine if principle been paid
/// After every payout, price drops 5000 / <repaymentPeriod>
/// If deployedClaimdrops.length == <interestOnlyPeriod + repaymentPeriod>, price is ZERO

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { PrimarySaleClaimdropFactory } from "./PrimarySaleClaimdropFactory.sol";

contract PyseOracle {
    uint8 public decimals;
    uint256 public initialPrice;

    PrimarySaleClaimdropFactory public immutable PrimarySaleClaimdropFactoryContract;

    constructor(address claimDropFactory_) {
        decimals = 6;
        initialPrice = 5000e6; // $5000 with 6 decimals
        PrimarySaleClaimdropFactoryContract = PrimarySaleClaimdropFactory(claimDropFactory_);
    }

    function getLatestPrice() public view returns (uint256 price) {
        uint256 distributedCount = PrimarySaleClaimdropFactoryContract.getDeployedClaimdropsCount();
        uint256 interestOnlyPeriod = PrimarySaleClaimdropFactoryContract.interestOnlyPeriod();
        uint256 repaymentPeriod = PrimarySaleClaimdropFactoryContract.repaymentPeriod();

        if (distributedCount >= interestOnlyPeriod + repaymentPeriod) {
            return 0;
        } else if (distributedCount <= repaymentPeriod) {
            return initialPrice;
        } else {
            uint256 priceDropStep = initialPrice / repaymentPeriod;
            return initialPrice  - (priceDropStep * (distributedCount - interestOnlyPeriod));
        }
    }
}
