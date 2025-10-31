require("@nomicfoundation/hardhat-toolbox");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    mantradukong: {
      url: process.env.MANTRA_DUKONG_RPC_URL || "https://evm.dukong.mantrachain.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 5887,
      gasPrice: "auto",
      gas: "auto",
    },
    mantra: {
      url: process.env.MANTRA_MAINNET_RPC_URL || "https://evm.mantrachain.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 96969,
      gasPrice: "auto",
      gas: "auto",
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },
  etherscan: {
    apiKey: {
      mantradukong: process.env.MANTRA_API_KEY || "",
    },
    customChains: [
      {
        network: "mantradukong",
        chainId: 5887,
        urls: {
          apiURL: "https://evm.dukong.mantrachain.io/api",
          browserURL: "https://evm.dukong.mantrachain.io"
        }
      }
    ]
  },
  mocha: {
    timeout: 120000,
  },
};
