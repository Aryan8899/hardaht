require("dotenv").config();
require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-verify");
require("hardhat-contract-sizer");

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          evmVersion: "cancun",
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: "0.8.20",
        settings: {
          evmVersion: "cancun",
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: "0.8.24",
        settings: {
          evmVersion: "cancun",
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: "0.8.27",
        settings: {
          evmVersion: "cancun",
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: "0.8.30",
        settings: {
          evmVersion: "cancun",
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    ],
  },

  contractSizer: {
    runOnCompile: true,
    strict: false, // was true
  },

  networks: {
    nowa: {
      url: "https://node2.nowa.finance",
      chainId: 262144,
      accounts: [process.env.PRIVATE_KEY],
    },
  },

  etherscan: {
    apiKey: {
      nowa: "anything",
    },
    customChains: [
      {
        network: "nowa",
        chainId: 262144,
        urls: {
          apiURL: "https://apiexplorer.nowa.finance/api/",
          browserURL: "https://apiexplorer.nowa.finance",
        },
      },
    ],
  },
};