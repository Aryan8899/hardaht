require("dotenv").config();
require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-verify");
require("hardhat-contract-sizer");


// Helper to avoid repeating the same settings block
const cfg = (version, { runs = 1, viaIR = true } = {}) => ({
  version,
  settings: {
    evmVersion: "cancun",
    viaIR,
    optimizer: { enabled: true, runs },
    metadata: { bytecodeHash: "none" },
  },
});


module.exports = {
  solidity: {
    compilers: [
      cfg("0.8.19"),
      cfg("0.8.20"),
      cfg("0.8.24"),
      cfg("0.8.27"),
      cfg("0.8.30"),
      cfg("0.8.34"),
    ],


    overrides: {
      // Price oracle: pinned to 0.8.24, no viaIR, so the explorer can verify it
      "contracts/PriceOracleSetter.sol": cfg("0.8.24", { runs: 200, viaIR: false }),
      "contracts/TokenPriceReader.sol": cfg("0.8.24", { runs: 200, viaIR: false }),


      // BNPL contracts
      "contracts/BNPLcontracts/core/BNPL_V2.sol": cfg("0.8.30", { runs: 1 }),
      "contracts/BNPLcontracts/core/BNPLAdmin.sol": cfg("0.8.30", { runs: 200 }),
      "contracts/BNPLcontracts/core/BNPLView.sol": cfg("0.8.30", { runs: 200 }),
      "contracts/BNPLcontracts/core/BNPLSignature.sol": cfg("0.8.30", { runs: 200 }),
    },
  },


  contractSizer: {
    runOnCompile: true,
    strict: false,
  },


  networks: {
    nowa: {
      url: "https://tnode2.nowa.finance",
      chainId: 22052010,
      accounts: [process.env.PRIVATE_KEY],
      // Fixed gas price: the node's eth_feeHistory is broken, so Hardhat
      // must not try to auto-detect EIP-1559 fees. Node reports ~1.125 gwei.
      gasPrice: 1300000000,
      // gas: 6000000, // uncomment only if you get gas estimation errors
    },
    // nowa: {
    //   url: "https://node1.nowa.finance",
    //   chainId: 262144,
    //   accounts: [process.env.PRIVATE_KEY],
    //   // Fixed gas price: the node's eth_feeHistory is broken, so Hardhat
    //   // must not try to auto-detect EIP-1559 fees. Node reports ~1.125 gwei.
    //   gasPrice: 1300000000,
    //   // gas: 6000000, // uncomment only if you get gas estimation errors
    // },
  },


  sourcify: { enabled: false },


  etherscan: {
    apiKey: {
      nowa: "anything",
    },
    customChains: [
      {
        network: "nowa",
        chainId: 22052010,
        urls: {
          apiURL: "https://testnetbackend.nowa.finance/api",
          browserURL: "https://testnet.nowa.finance",
        },
      },
      // {
      //   network: "nowa",
      //   chainId: 262144,
      //   urls: {
      //     apiURL: "https://apiexplorer.nowa.finance/api",
      //     browserURL: "https://explorer.nowa.finance",
      //   },
      // },
    ],
  },
};