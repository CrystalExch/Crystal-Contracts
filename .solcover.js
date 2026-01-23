module.exports = {
    skipFiles: [
        "interfaces",
        "libraries",
        "mocks"
    ],
    configureYulOptimizer: true,
    solcOptimizerDetails: {
      peephole: false,
      inliner: false,
      jumpdestRemover: false,
      orderLiterals: true,
      deduplicate: false,
      cse: false,
      constantOptimizer: false,
      yul: false
    },
    mocha: {
      timeout: 10000000,
      parallel: false
    },
    istanbulReporter: ['json', 'text', 'html'],
    providerOptions: {
      total_accounts: 20,
      default_balance_ether: 1000000000000000000000000
    }
  };
