const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { deployClaimdropFixture } = require("./fixtures/deployClaimdrop");

describe("Claimdrop", function () {
  let claimdrop, token;
  let owner, admin, user1, user2, user3, user4, user5;

  beforeEach(async function () {
    ({ claimdrop, token, owner, admin, user1, user2, user3, user4, user5 } =
      await deployClaimdropFixture());
  });

  describe("Deployment", function () {
    it("should set the correct owner", async function () {
      expect(await claimdrop.owner()).to.equal(owner.address);
    });

    it("should set admin as authorized wallet", async function () {
      expect(await claimdrop.isAuthorized(admin.address)).to.be.true;
    });

    it("should not have a campaign initially", async function () {
      const campaign = await claimdrop.getCampaign();
      expect(campaign.exists).to.be.false;
    });
  });

  describe("Campaign Management", function () {
    let startTime, endTime;
    let distributions;

    beforeEach(async function () {
      const now = await time.latest();
      startTime = now + 3600; // 1 hour from now
      endTime = now + 3600 * 24 * 365; // 1 year from now

      // 30% lump sum, 70% linear vesting
      distributions = [
        {
          kind: 1, // LumpSum
          percentageBps: 3000,
          startTime: startTime,
          endTime: 0,
          cliffDuration: 0,
        },
        {
          kind: 0, // LinearVesting
          percentageBps: 7000,
          startTime: startTime,
          endTime: endTime,
          cliffDuration: 0,
        },
      ];
    });

    it("should create a campaign with valid parameters", async function () {
      await claimdrop.createCampaign(
        "Test Campaign",
        "Test Description",
        "airdrop",
        token.target,
        ethers.parseEther("1000000"),
        distributions,
        startTime,
        endTime
      );

      const campaign = await claimdrop.getCampaign();
      expect(campaign.exists).to.be.true;
      expect(campaign.name).to.equal("Test Campaign");
      expect(campaign.rewardToken).to.equal(token.target);
      expect(campaign.totalReward).to.equal(ethers.parseEther("1000000"));
    });

    it("should reject campaign with invalid percentages", async function () {
      const invalidDistributions = [
        {
          kind: 1,
          percentageBps: 5000, // Only 50%
          startTime: startTime,
          endTime: 0,
          cliffDuration: 0,
        },
      ];

      await expect(
        claimdrop.createCampaign(
          "Test",
          "Test",
          "airdrop",
          token.target,
          ethers.parseEther("1000"),
          invalidDistributions,
          startTime,
          endTime
        )
      ).to.be.revertedWithCustomError(claimdrop, "InvalidPercentageSum");
    });

    it("should reject campaign with start time in past", async function () {
      const pastTime = (await time.latest()) - 3600;

      await expect(
        claimdrop.createCampaign(
          "Test",
          "Test",
          "airdrop",
          token.target,
          ethers.parseEther("1000"),
          distributions,
          pastTime,
          endTime
        )
      ).to.be.revertedWithCustomError(claimdrop, "InvalidTimeWindow");
    });

    it("should reject duplicate campaign creation", async function () {
      await claimdrop.createCampaign(
        "Test Campaign",
        "Test Description",
        "airdrop",
        token.target,
        ethers.parseEther("1000000"),
        distributions,
        startTime,
        endTime
      );

      await expect(
        claimdrop.createCampaign(
          "Test Campaign 2",
          "Test Description 2",
          "airdrop",
          token.target,
          ethers.parseEther("1000000"),
          distributions,
          startTime,
          endTime
        )
      ).to.be.revertedWithCustomError(claimdrop, "CampaignAlreadyExists");
    });

    it("should allow authorized wallet to create campaign", async function () {
      await claimdrop.connect(admin).createCampaign(
        "Test Campaign",
        "Test Description",
        "airdrop",
        token.target,
        ethers.parseEther("1000000"),
        distributions,
        startTime,
        endTime
      );

      const campaign = await claimdrop.getCampaign();
      expect(campaign.exists).to.be.true;
    });

    it("should reject unauthorized user from creating campaign", async function () {
      await expect(
        claimdrop.connect(user1).createCampaign(
          "Test",
          "Test",
          "airdrop",
          token.target,
          ethers.parseEther("1000"),
          distributions,
          startTime,
          endTime
        )
      ).to.be.revertedWithCustomError(claimdrop, "Unauthorized");
    });

    describe("Close Campaign", function () {
      beforeEach(async function () {
        await claimdrop.createCampaign(
          "Test Campaign",
          "Test Description",
          "airdrop",
          token.target,
          ethers.parseEther("1000000"),
          distributions,
          startTime,
          endTime
        );

        // Fund contract
        await token.transfer(claimdrop.target, ethers.parseEther("1000000"));
      });

      it("should close campaign and return unclaimed tokens", async function () {
        const balanceBefore = await token.balanceOf(owner.address);

        await claimdrop.closeCampaign();

        const balanceAfter = await token.balanceOf(owner.address);
        const campaign = await claimdrop.getCampaign();

        expect(campaign.closedAt).to.be.gt(0);
        expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("1000000"));
      });

      it("should reject closing already closed campaign", async function () {
        await claimdrop.closeCampaign();

        await expect(claimdrop.closeCampaign()).to.be.revertedWithCustomError(
          claimdrop,
          "CampaignAlreadyClosed"
        );
      });

      it("should reject non-owner from closing campaign", async function () {
        await expect(
          claimdrop.connect(admin).closeCampaign()
        ).to.be.reverted;
      });
    });
  });

  describe("Allocation Management", function () {
    let startTime, endTime, distributions;

    beforeEach(async function () {
      const now = await time.latest();
      startTime = now + 3600;
      endTime = now + 3600 * 24 * 365;

      distributions = [
        {
          kind: 1,
          percentageBps: 10000,
          startTime: startTime,
          endTime: 0,
          cliffDuration: 0,
        },
      ];

      await claimdrop.createCampaign(
        "Test Campaign",
        "Test Description",
        "airdrop",
        token.target,
        ethers.parseEther("1000000"),
        distributions,
        startTime,
        endTime
      );
    });

    it("should add allocations in batch", async function () {
      const addresses = [user1.address, user2.address, user3.address];
      const amounts = [
        ethers.parseEther("1000"),
        ethers.parseEther("2000"),
        ethers.parseEther("3000"),
      ];

      await claimdrop.addAllocations(addresses, amounts);

      expect(await claimdrop.getAllocation(user1.address)).to.equal(amounts[0]);
      expect(await claimdrop.getAllocation(user2.address)).to.equal(amounts[1]);
      expect(await claimdrop.getAllocation(user3.address)).to.equal(amounts[2]);
    });

    it("should reject allocations after campaign starts", async function () {
      await time.increaseTo(startTime);

      const addresses = [user1.address];
      const amounts = [ethers.parseEther("1000")];

      await expect(
        claimdrop.addAllocations(addresses, amounts)
      ).to.be.revertedWithCustomError(claimdrop, "CampaignHasStarted");
    });

    it("should reject array length mismatch", async function () {
      const addresses = [user1.address, user2.address];
      const amounts = [ethers.parseEther("1000")];

      await expect(
        claimdrop.addAllocations(addresses, amounts)
      ).to.be.revertedWithCustomError(claimdrop, "ArrayLengthMismatch");
    });

    it("should reject duplicate allocations", async function () {
      await claimdrop.addAllocations([user1.address], [ethers.parseEther("1000")]);

      await expect(
        claimdrop.addAllocations([user1.address], [ethers.parseEther("2000")])
      ).to.be.revertedWithCustomError(claimdrop, "AllocationExists");
    });

    it("should replace address correctly", async function () {
      await claimdrop.addAllocations(
        [user1.address],
        [ethers.parseEther("1000")]
      );

      await claimdrop.replaceAddress(user1.address, user2.address);

      expect(await claimdrop.getAllocation(user1.address)).to.equal(0);
      expect(await claimdrop.getAllocation(user2.address)).to.equal(
        ethers.parseEther("1000")
      );
    });

    it("should remove address correctly", async function () {
      await claimdrop.addAllocations(
        [user1.address],
        [ethers.parseEther("1000")]
      );

      await claimdrop.removeAddress(user1.address);

      expect(await claimdrop.getAllocation(user1.address)).to.equal(0);
    });

    it("should reject removing address after campaign starts", async function () {
      await claimdrop.addAllocations(
        [user1.address],
        [ethers.parseEther("1000")]
      );

      await time.increaseTo(startTime);

      await expect(
        claimdrop.removeAddress(user1.address)
      ).to.be.revertedWithCustomError(claimdrop, "CampaignHasStarted");
    });
  });

  describe("Claiming", function () {
    let startTime, endTime;

    beforeEach(async function () {
      const now = await time.latest();
      startTime = now + 3600;
      endTime = now + 3600 * 24 * 365;
    });

    describe("Lump Sum Distribution", function () {
      beforeEach(async function () {
        const distributions = [
          {
            kind: 1, // LumpSum
            percentageBps: 10000,
            startTime: startTime,
            endTime: 0,
            cliffDuration: 0,
          },
        ];

        await claimdrop.createCampaign(
          "Test Campaign",
          "Test Description",
          "airdrop",
          token.target,
          ethers.parseEther("1000000"),
          distributions,
          startTime,
          endTime
        );

        await claimdrop.addAllocations(
          [user1.address],
          [ethers.parseEther("1000")]
        );

        await token.transfer(claimdrop.target, ethers.parseEther("1000000"));
      });

      it("should reject claim before start", async function () {
        await expect(
          claimdrop.connect(user1).claim(user1.address, 0)
        ).to.be.revertedWithCustomError(claimdrop, "CampaignNotStarted");
      });

      it("should allow claim after start", async function () {
        await time.increaseTo(startTime);

        const balanceBefore = await token.balanceOf(user1.address);
        await claimdrop.connect(user1).claim(user1.address, 0);
        const balanceAfter = await token.balanceOf(user1.address);

        expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("1000"));
      });

      it("should prevent double claim", async function () {
        await time.increaseTo(startTime);

        await claimdrop.connect(user1).claim(user1.address, 0);

        await expect(
          claimdrop.connect(user1).claim(user1.address, 0)
        ).to.be.revertedWithCustomError(claimdrop, "NothingToClaim");
      });

      it("should support partial claims", async function () {
        await time.increaseTo(startTime);

        const balanceBefore = await token.balanceOf(user1.address);
        await claimdrop.connect(user1).claim(user1.address, ethers.parseEther("500"));
        const balanceAfter = await token.balanceOf(user1.address);

        expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("500"));

        // Claim remaining
        const balanceBefore2 = await token.balanceOf(user1.address);
        await claimdrop.connect(user1).claim(user1.address, 0);
        const balanceAfter2 = await token.balanceOf(user1.address);

        expect(balanceAfter2 - balanceBefore2).to.equal(ethers.parseEther("500"));
      });

      it("should reject claim for blacklisted address", async function () {
        await claimdrop.blacklistAddress(user1.address, true);
        await time.increaseTo(startTime);

        await expect(
          claimdrop.connect(user1).claim(user1.address, 0)
        ).to.be.revertedWithCustomError(claimdrop, "Blacklisted");
      });

      it("should allow owner to claim on behalf of user", async function () {
        await time.increaseTo(startTime);

        const balanceBefore = await token.balanceOf(user1.address);
        await claimdrop.connect(owner).claim(user1.address, 0);
        const balanceAfter = await token.balanceOf(user1.address);

        expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("1000"));
      });
    });

    describe("Linear Vesting Distribution", function () {
      beforeEach(async function () {
        const distributions = [
          {
            kind: 0, // LinearVesting
            percentageBps: 10000,
            startTime: startTime,
            endTime: endTime,
            cliffDuration: 0,
          },
        ];

        await claimdrop.createCampaign(
          "Test Campaign",
          "Test Description",
          "vesting",
          token.target,
          ethers.parseEther("1000000"),
          distributions,
          startTime,
          endTime
        );

        await claimdrop.addAllocations(
          [user1.address],
          [ethers.parseEther("1000")]
        );

        await token.transfer(claimdrop.target, ethers.parseEther("1000000"));
      });

      it("should vest linearly over time", async function () {
        await time.increaseTo(startTime);

        // After start, should be able to claim 0
        let rewards = await claimdrop.getRewards(user1.address);
        expect(rewards.pending).to.equal(0);

        // Move 25% through vesting period
        const duration = endTime - startTime;
        await time.increaseTo(startTime + Math.floor(duration / 4));

        rewards = await claimdrop.getRewards(user1.address);
        // Should be close to 250 tokens (25% of 1000)
        expect(rewards.pending).to.be.closeTo(ethers.parseEther("250"), ethers.parseEther("1"));

        // Claim 25%
        await claimdrop.connect(user1).claim(user1.address, 0);

        rewards = await claimdrop.getRewards(user1.address);
        expect(rewards.claimed).to.be.closeTo(ethers.parseEther("250"), ethers.parseEther("1"));

        // Move to 50%
        await time.increaseTo(startTime + Math.floor(duration / 2));

        rewards = await claimdrop.getRewards(user1.address);
        // Should have ~250 more tokens available (500 total - 250 claimed)
        expect(rewards.pending).to.be.closeTo(ethers.parseEther("250"), ethers.parseEther("1"));
      });

      it("should allow full claim after vesting ends", async function () {
        await time.increaseTo(endTime);

        const balanceBefore = await token.balanceOf(user1.address);
        await claimdrop.connect(user1).claim(user1.address, 0);
        const balanceAfter = await token.balanceOf(user1.address);

        expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("1000"));
      });
    });

    describe("Vesting with Cliff", function () {
      beforeEach(async function () {
        const distributions = [
          {
            kind: 0, // LinearVesting
            percentageBps: 10000,
            startTime: startTime,
            endTime: endTime,
            cliffDuration: 3600 * 24 * 30, // 30 days
          },
        ];

        await claimdrop.createCampaign(
          "Test Campaign",
          "Test Description",
          "vesting",
          token.target,
          ethers.parseEther("1000000"),
          distributions,
          startTime,
          endTime
        );

        await claimdrop.addAllocations(
          [user1.address],
          [ethers.parseEther("1000")]
        );

        await token.transfer(claimdrop.target, ethers.parseEther("1000000"));
      });

      it("should not allow claim during cliff period", async function () {
        await time.increaseTo(startTime + 3600 * 24 * 15); // 15 days after start

        const rewards = await claimdrop.getRewards(user1.address);
        expect(rewards.pending).to.equal(0);

        await expect(
          claimdrop.connect(user1).claim(user1.address, 0)
        ).to.be.revertedWithCustomError(claimdrop, "NothingToClaim");
      });

      it("should allow claim after cliff passes", async function () {
        await time.increaseTo(startTime + 3600 * 24 * 31); // 31 days after start

        const rewards = await claimdrop.getRewards(user1.address);
        expect(rewards.pending).to.be.gt(0);

        const balanceBefore = await token.balanceOf(user1.address);
        await claimdrop.connect(user1).claim(user1.address, 0);
        const balanceAfter = await token.balanceOf(user1.address);

        expect(balanceAfter - balanceBefore).to.be.gt(0);
      });
    });

    describe("Multiple Distributions", function () {
      beforeEach(async function () {
        const distributions = [
          {
            kind: 1, // LumpSum 30%
            percentageBps: 3000,
            startTime: startTime,
            endTime: 0,
            cliffDuration: 0,
          },
          {
            kind: 0, // LinearVesting 70%
            percentageBps: 7000,
            startTime: startTime,
            endTime: endTime,
            cliffDuration: 0,
          },
        ];

        await claimdrop.createCampaign(
          "Test Campaign",
          "Test Description",
          "mixed",
          token.target,
          ethers.parseEther("1000000"),
          distributions,
          startTime,
          endTime
        );

        await claimdrop.addAllocations(
          [user1.address],
          [ethers.parseEther("1000")]
        );

        await token.transfer(claimdrop.target, ethers.parseEther("1000000"));
      });

      it("should claim lump sum immediately and vest remaining", async function () {
        await time.increaseTo(startTime);

        // Should have 300 tokens available from lump sum
        let rewards = await claimdrop.getRewards(user1.address);
        expect(rewards.pending).to.equal(ethers.parseEther("300"));

        // Claim lump sum
        await claimdrop.connect(user1).claim(user1.address, 0);

        // Move halfway through vesting
        const duration = endTime - startTime;
        await time.increaseTo(startTime + Math.floor(duration / 2));

        // Should have ~350 more tokens available (50% of 700)
        rewards = await claimdrop.getRewards(user1.address);
        expect(rewards.pending).to.be.closeTo(ethers.parseEther("350"), ethers.parseEther("1"));
      });

      it("should prioritize lump sum in partial claims", async function () {
        await time.increaseTo(startTime);

        // Partial claim of 100 tokens (should come from lump sum first)
        await claimdrop.connect(user1).claim(user1.address, ethers.parseEther("100"));

        const claims = await claimdrop.getClaims(user1.address);
        expect(claims[0]).to.equal(ethers.parseEther("100")); // Lump sum slot
        expect(claims[1]).to.equal(0); // Vesting slot
      });
    });
  });

  describe("Administration", function () {
    it("should allow owner to manage authorized wallets", async function () {
      await claimdrop.manageAuthorizedWallets([user1.address], true);
      expect(await claimdrop.isAuthorized(user1.address)).to.be.true;

      await claimdrop.manageAuthorizedWallets([user1.address], false);
      expect(await claimdrop.isAuthorized(user1.address)).to.be.false;
    });

    it("should reject non-owner from managing authorized wallets", async function () {
      await expect(
        claimdrop.connect(user1).manageAuthorizedWallets([user2.address], true)
      ).to.be.reverted;
    });

    it("should allow blacklisting addresses", async function () {
      await claimdrop.blacklistAddress(user1.address, true);
      expect(await claimdrop.isBlacklisted(user1.address)).to.be.true;

      await claimdrop.blacklistAddress(user1.address, false);
      expect(await claimdrop.isBlacklisted(user1.address)).to.be.false;
    });

    it("should reject blacklisting owner", async function () {
      await expect(
        claimdrop.blacklistAddress(owner.address, true)
      ).to.be.revertedWithCustomError(claimdrop, "CannotBlacklistOwner");
    });

    it("should allow sweeping non-reward tokens", async function () {
      const MockERC20 = await ethers.getContractFactory("MockERC20");
      const otherToken = await MockERC20.deploy("Other", "OTH", 18);
      await otherToken.waitForDeployment();

      await otherToken.mint(claimdrop.target, ethers.parseEther("1000"));

      const balanceBefore = await otherToken.balanceOf(owner.address);
      await claimdrop.sweep(otherToken.target, ethers.parseEther("1000"));
      const balanceAfter = await otherToken.balanceOf(owner.address);

      expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("1000"));
    });

    it("should allow pausing and unpausing", async function () {
      await claimdrop.pause();

      const now = await time.latest();
      await expect(
        claimdrop.createCampaign(
          "Test",
          "Test",
          "test",
          token.target,
          ethers.parseEther("1000"),
          [
            {
              kind: 1,
              percentageBps: 10000,
              startTime: now + 3600,
              endTime: 0,
              cliffDuration: 0,
            },
          ],
          now + 3600,
          now + 7200
        )
      ).to.be.reverted;

      await claimdrop.unpause();

      await claimdrop.createCampaign(
        "Test",
        "Test",
        "test",
        token.target,
        ethers.parseEther("1000"),
        [
          {
            kind: 1,
            percentageBps: 10000,
            startTime: now + 3600,
            endTime: 0,
            cliffDuration: 0,
          },
        ],
        now + 3600,
        now + 7200
      );

      const campaign = await claimdrop.getCampaign();
      expect(campaign.exists).to.be.true;
    });
  });

  describe("View Functions", function () {
    let startTime, endTime;

    beforeEach(async function () {
      const now = await time.latest();
      startTime = now + 3600;
      endTime = now + 3600 * 24 * 365;

      const distributions = [
        {
          kind: 1,
          percentageBps: 10000,
          startTime: startTime,
          endTime: 0,
          cliffDuration: 0,
        },
      ];

      await claimdrop.createCampaign(
        "Test Campaign",
        "Test Description",
        "airdrop",
        token.target,
        ethers.parseEther("1000000"),
        distributions,
        startTime,
        endTime
      );

      await claimdrop.addAllocations(
        [user1.address, user2.address],
        [ethers.parseEther("1000"), ethers.parseEther("2000")]
      );

      await token.transfer(claimdrop.target, ethers.parseEther("1000000"));
    });

    it("should return correct campaign details", async function () {
      const campaign = await claimdrop.getCampaign();
      expect(campaign.name).to.equal("Test Campaign");
      expect(campaign.description).to.equal("Test Description");
      expect(campaign.rewardToken).to.equal(token.target);
    });

    it("should return correct allocations", async function () {
      expect(await claimdrop.getAllocation(user1.address)).to.equal(
        ethers.parseEther("1000")
      );
      expect(await claimdrop.getAllocation(user2.address)).to.equal(
        ethers.parseEther("2000")
      );
    });

    it("should return correct reward details", async function () {
      await time.increaseTo(startTime);

      const rewards = await claimdrop.getRewards(user1.address);
      expect(rewards.total).to.equal(ethers.parseEther("1000"));
      expect(rewards.pending).to.equal(ethers.parseEther("1000"));
      expect(rewards.claimed).to.equal(0);
    });

    it("should return investor count", async function () {
      expect(await claimdrop.getInvestorCount()).to.equal(2);
    });
  });
});
