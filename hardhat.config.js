require("hardhat-gas-reporter");
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      evmVersion: "prague",
      viaIR: false,
      optimizer: {
        enabled: true,
        runs: 1700,
      }
    }
  },
  mocha: {
    timeout: 100000,
    parallel: false
  },
  networks: {
    monad: {
      url: 'https://rpc.monad.xyz',
      chainId: 143,
      gas: "auto",
      gasPrice: "auto",
      allowUnlimitedContractSize: true,
      blockGasLimit: 150000000
    },
    hardhat: {
      allowUnlimitedContractSize: true,
      blockGasLimit: 150000000,
      gas: 150000000,
      hardfork: "prague",
      accounts: {
        count: 20,
        accountsBalance: "1000000000000000000000000000000000000000000"
      }
    }
  },
  gasReporter: {
    enabled: false,
    currency: "USD",
    coinmarketcap: ""
  }
};