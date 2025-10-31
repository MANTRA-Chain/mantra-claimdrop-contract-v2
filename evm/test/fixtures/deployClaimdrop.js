const { ethers } = require("hardhat");

/**
 * Deploy Claimdrop contract with test token
 */
async function deployClaimdropFixture() {
  // Get signers
  const [owner, admin, user1, user2, user3, user4, user5, user6, user7, user8] =
    await ethers.getSigners();

  // Deploy mock ERC20 token
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const token = await MockERC20.deploy("Test Token", "TEST", 18);
  await token.waitForDeployment();

  // Mint tokens to owner
  await token.mint(owner.address, ethers.parseEther("10000000"));

  // Deploy Claimdrop contract
  const Claimdrop = await ethers.getContractFactory("Claimdrop");
  const claimdrop = await Claimdrop.deploy(owner.address);
  await claimdrop.waitForDeployment();

  // Add admin as authorized wallet
  await claimdrop.manageAuthorizedWallets([admin.address], true);

  return {
    claimdrop,
    token,
    owner,
    admin,
    user1,
    user2,
    user3,
    user4,
    user5,
    user6,
    user7,
    user8,
  };
}

module.exports = {
  deployClaimdropFixture,
};
