const { ethers } = require("hardhat");

/**
 * Deploy Claimdrop contract
 */
async function main() {
  console.log("Deploying Claimdrop contract...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "ETH");

  // Deploy contract
  const Claimdrop = await ethers.getContractFactory("Claimdrop");
  const claimdrop = await Claimdrop.deploy(deployer.address);
  await claimdrop.waitForDeployment();

  const address = await claimdrop.getAddress();
  console.log("Claimdrop deployed to:", address);

  // Wait for block confirmations
  console.log("Waiting for block confirmations...");
  await claimdrop.deploymentTransaction().wait(5);

  console.log("Deployment complete!");

  return { claimdrop, address };
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = { main };
