require("dotenv").config();

require("@atixlabs/hardhat-time-n-mine");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("hardhat-deploy");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("hardhat-contract-sizer");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "localhost",
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
      80001: 3,
      137: 3
    },
  },
  networks: {
    localhost: {},
    mumbai: {
      chainId: 80001,
      url: process.env.MUMBAI_URL || "https://matic-mumbai.chainstacklabs.com",
      // accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      accounts: {
        mnemonic: process.env.MNEMONIC,
        path: process.env.MNEMONIC_PATH || "m/44'/60'/0'/0",
      },
      // gasPrice: 5000000000,
    },
    polygon: {
      chainId: 137,
      url: process.env.POLYGON_URL || "https://rpc-mainnet.matic.network",
      accounts: {
        mnemonic: process.env.MNEMONIC,
        path: process.env.MNEMONIC_PATH || "m/44'/60'/0'/0",
      },
      // gasPrice: 60000000000,
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY,
  },
};
