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
        runs: 10000
      }
    }
  },
  mocha: {
    timeout: 1000000
  },
  networks: {
    monad: {
      url: 'https://testnet-rpc.monad.xyz',
      chainId: 10143,
      gas: "auto",
      gasPrice: "auto",
      allowUnlimitedContractSize: true,
      blockGasLimit: 150000000
    },
    hardhat: {
      allowUnlimitedContractSize: true,
      blockGasLimit: 150000000,
      accounts: {
        count: 20,
        accountsBalance: "1000000000000000000000000000000000000000000000000000000000000"
      }
    }
  },
  gasReporter: {
    enabled: false,
    currency: "USD",
    coinmarketcap: "" // optional
  }
};