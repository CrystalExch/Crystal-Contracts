const MASKS = {
  MASK_KEEP_0_128: (1n << 128n) - 1n,
  MASK_KEEP_0_112: (1n << 112n) - 1n,
  MASK_KEEP_0_80: (1n << 80n) - 1n,
  MASK_KEEP_0_51: (1n << 51n) - 1n,
  MASK_KEEP_0_41: (1n << 41n) - 1n,
  MASK_OUT_0_128: ~((1n << 128n) - 1n),
};

const ETH_ADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

const MAX_UINT256 = 2n ** 256n - 1n;

const FEES = {
  MIN_FEE: 90000,
  MAX_FEE: 100000,
  DEFAULT_TAKER_FEE: 99970,
  DEFAULT_MAKER_REBATE: 99990,
};

const MARKET_TYPES = {
  LINEAR: 0,
  LOGARITHMIC: 1,
  LOGARITHMIC_AMM: 2,
  LAUNCHPAD: 3,
};

const ACTIONS = {
  CANCEL: 1,
  BUY_LIMIT: 2,
  SELL_LIMIT: 3,
  REPLACE_BUY: 4,
  REPLACE_SELL: 5,
  MARKET_BUY: 6,
  MARKET_SELL: 7,
};

const ORDER_TYPES = {
  NORMAL: 0,
  STP: 1,
  EXACT_OUTPUT: 2,
};

const TIME = {
  ONE_DAY: 86400,
  SEVEN_DAYS: 7 * 86400,
  THIRTY_DAYS: 30 * 86400,
  ONE_YEAR: 365 * 86400,
};

const LAUNCHPAD = {
  INITIAL_TOKEN_SUPPLY: 1000000000n * 10n ** 18n,
  MIN_LIQUIDITY: 100000n,
};

const DEFAULT_DEPLOY_PARAMS = {
  feeCommission: 10,
  feeClaimDuration: 86400,
  launchpadInitialNativeSupply: 1000000000000000000000n,
  launchpadFee: 99000n,
  launchpadCreatorFeeSplit: 5n,
  graduatedMinSize: 1000000000000000000n,
  graduatedTakerFee: 99920,
  graduatedMakerRebate: 99990,
  graduatedCreatorFeeSplit: 40,
};

const DEFAULT_MARKET_PARAMS = {
  scaleFactor: 21,
  tickSize: 1,
  maxPrice: 1_000_000_000_000_000,
  minSize: 1_000_000,
  takerFee: 99970,
  makerRebate: 99990,
};

module.exports = {
  MASKS,
  ETH_ADDRESS,
  MAX_UINT256,
  FEES,
  MARKET_TYPES,
  ACTIONS,
  ORDER_TYPES,
  TIME,
  LAUNCHPAD,
  DEFAULT_DEPLOY_PARAMS,
  DEFAULT_MARKET_PARAMS,
};
