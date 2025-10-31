const { ethers } = require("hardhat");

/**
 * Create a campaign on deployed Claimdrop contract
 *
 * Usage: node scripts/createCampaign.js <claimdrop_address> <config_file>
 */
async function createCampaign(claimdropAddress, config) {
  const claimdrop = await ethers.getContractAt("Claimdrop", claimdropAddress);

  console.log("Creating campaign:", config.name);

  // Convert distribution configurations
  const distributions = config.distributions.map((d) => ({
    kind: d.kind === "LinearVesting" ? 0 : 1,
    percentageBps: d.percentageBps,
    startTime: d.startTime,
    endTime: d.endTime || 0,
    cliffDuration: d.cliffDuration || 0,
  }));

  const tx = await claimdrop.createCampaign(
    config.name,
    config.description,
    config.campaignType,
    config.rewardToken,
    config.totalReward,
    distributions,
    config.startTime,
    config.endTime
  );

  const receipt = await tx.wait();
  console.log("Campaign created:", receipt.hash);

  return receipt;
}

async function main() {
  if (process.argv.length < 4) {
    console.error("Usage: node createCampaign.js <claimdrop_address> <config_file>");
    process.exit(1);
  }

  const claimdropAddress = process.argv[2];
  const configFile = process.argv[3];

  const config = require(configFile);

  await createCampaign(claimdropAddress, config);
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = { createCampaign };
