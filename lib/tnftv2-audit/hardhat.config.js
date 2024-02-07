require("dotenv").config();
require("@atixlabs/hardhat-time-n-mine");
require('@openzeppelin/hardhat-upgrades');
require("hardhat-deploy")
require("hardhat-gas-reporter")
require("hardhat-tracer")
require("@nomicfoundation/hardhat-chai-matchers");
require('hardhat-contract-sizer');

module.exports = {
  mocha: {
    timeout: 100000000
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      // forking: {
      //   url: process.env.INFURA_URL_MUMBAI,
      //   blockNumber: 39290683
      // }
    },
    localhost: {},
    mumbai: {
      url: process.env.INFURA_URL_MUMBAI,
      accounts: [process.env.PK1, process.env.PK2, process.env.PK2],
      //gasPrice: 30000000000
    },
    polygon: {
      url: process.env.INFURA_URL_POLYGON,
      accounts: [process.env.PK1, process.env.PK2],
      // gasPrice: 30000000000
    },
  },
  namedAccounts: {
    deployer: 0,
    storageFeeAddress: 1,
    sellFeeAddress: 2,
    priceManager: 3,
    randomUser: 4,
    randomUser2: 5,
    randomUser3: 6,
    randomUser4: 7
  },
  solidity: {
    compilers: [
      {
        version: "0.8.21",
        settings: {
          evmVersion: 'paris',
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000,
          },
        },
      },
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
    ]
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.POLYGON_EXPLORER_API_KEY,
  },
};
