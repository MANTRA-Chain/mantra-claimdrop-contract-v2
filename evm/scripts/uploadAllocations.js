const { ethers } = require("hardhat");

const BATCH_SIZE = 3000;

/**
 * Upload allocations in batches
 *
 * Usage: node scripts/uploadAllocations.js <claimdrop_address> <allocations_file>
 */
async function uploadAllocations(claimdropAddress, allocationsFile) {
  const allocations = require(allocationsFile); // JSON file with [{address, amount}]
  const claimdrop = await ethers.getContractAt("Claimdrop", claimdropAddress);

  console.log(`Uploading ${allocations.length} allocations...`);

  let totalUploaded = 0;

  for (let i = 0; i < allocations.length; i += BATCH_SIZE) {
    const batch = allocations.slice(i, i + BATCH_SIZE);
    const addresses = batch.map((a) => a.address);
    const amounts = batch.map((a) => a.amount);

    console.log(
      `Uploading batch ${Math.floor(i / BATCH_SIZE) + 1} (${batch.length} allocations)...`
    );

    const tx = await claimdrop.addAllocations(addresses, amounts);
    const receipt = await tx.wait();

    console.log(`Batch uploaded: ${receipt.hash}`);
    totalUploaded += batch.length;
  }

  console.log(`All allocations uploaded! Total: ${totalUploaded}`);
}

async function main() {
  if (process.argv.length < 4) {
    console.error("Usage: node uploadAllocations.js <claimdrop_address> <allocations_file>");
    process.exit(1);
  }

  const claimdropAddress = process.argv[2];
  const allocationsFile = process.argv[3];

  await uploadAllocations(claimdropAddress, allocationsFile);
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = { uploadAllocations };
