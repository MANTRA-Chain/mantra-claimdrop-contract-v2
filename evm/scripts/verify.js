const { run } = require("hardhat");

/**
 * Verify contract on block explorer
 *
 * Usage: node scripts/verify.js <contract_address> <constructor_args>
 */
async function verify(address, constructorArguments) {
  console.log("Verifying contract...");

  try {
    await run("verify:verify", {
      address,
      constructorArguments,
    });
    console.log("Contract verified!");
  } catch (error) {
    if (error.message.includes("already verified")) {
      console.log("Contract already verified");
    } else {
      throw error;
    }
  }
}

async function main() {
  if (process.argv.length < 3) {
    console.error("Usage: node verify.js <contract_address> [constructor_args...]");
    process.exit(1);
  }

  const address = process.argv[2];
  const constructorArguments = process.argv.slice(3);

  await verify(address, constructorArguments);
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = { verify };
