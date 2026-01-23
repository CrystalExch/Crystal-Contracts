const { ethers } = require("hardhat");
const { DEFAULT_DEPLOY_PARAMS, DEFAULT_MARKET_PARAMS, MARKET_TYPES, MAX_UINT256 } = require("./constants");

/**
 * Deploy base fixture - WETH, test tokens, Crystal, basic markets
 * @returns {Object} - Deployed contracts and accounts
 */
async function deployFixture() {
  const [owner, maker, taker, vaultOperator, depositor, user1, user2, gov] = await ethers.getSigners();

  const WETH = await ethers.getContractFactory("WrappedMonad");
  const weth = await WETH.deploy();

  const Token = await ethers.getContractFactory("TestToken");
  const quote = await Token.deploy("Quote Token", "QUOTE", 6);
  const base = await Token.deploy("Base Token", "BASE", 18);
  const token1 = await Token.deploy("Token One", "TKN1", 18);
  const token2 = await Token.deploy("Token Two", "TKN2", 8);

  const mintAmount = ethers.parseEther("1000000000000000000000000000000");
  const accounts = [owner, maker, taker, vaultOperator, depositor, user1, user2];

  for (const account of accounts) {
    await quote.mint(account.address, mintAmount);
    await base.mint(account.address, mintAmount);
    await token1.mint(account.address, mintAmount);
    await token2.mint(account.address, mintAmount);
    await weth.connect(account).deposit({ value: ethers.parseEther("10000") });
  }

  const Crystal = await ethers.getContractFactory("Crystal");
  const crystal = await Crystal.deploy(
    weth.target,
    owner.address,
    owner.address,
    DEFAULT_DEPLOY_PARAMS.feeCommission,
    DEFAULT_DEPLOY_PARAMS.feeClaimDuration,
    [
      DEFAULT_DEPLOY_PARAMS.launchpadInitialNativeSupply,
      DEFAULT_DEPLOY_PARAMS.launchpadFee,
      DEFAULT_DEPLOY_PARAMS.launchpadCreatorFeeSplit,
      DEFAULT_DEPLOY_PARAMS.graduatedMinSize,
      DEFAULT_DEPLOY_PARAMS.graduatedTakerFee,
      DEFAULT_DEPLOY_PARAMS.graduatedMakerRebate,
      DEFAULT_DEPLOY_PARAMS.graduatedCreatorFeeSplit,
    ]
  );

  const marketParams = {
    isCanonical: true,
    quoteAsset: quote.target,
    baseAsset: weth.target,
    marketType: MARKET_TYPES.LOGARITHMIC_AMM,
    scaleFactor: 21,
    tickSize: 1,
    maxPrice: 1_000_000_000_000_000,
    minSize: 1_000_000,
    takerFee: 99970,
    makerRebate: 99990,
  };

  const marketAddr = await crystal.deploy.staticCall(
    marketParams.isCanonical,
    marketParams.quoteAsset,
    marketParams.baseAsset,
    marketParams.marketType,
    marketParams.scaleFactor,
    marketParams.tickSize,
    marketParams.maxPrice,
    marketParams.minSize,
    marketParams.takerFee,
    marketParams.makerRebate
  );

  await crystal.deploy(
    marketParams.isCanonical,
    marketParams.quoteAsset,
    marketParams.baseAsset,
    marketParams.marketType,
    marketParams.scaleFactor,
    marketParams.tickSize,
    marketParams.maxPrice,
    marketParams.minSize,
    marketParams.takerFee,
    marketParams.makerRebate
  );

  const market = await ethers.getContractAt("CrystalMarket", marketAddr);

  const linearMarketAddr = await crystal.deploy.staticCall(
    false,
    quote.target,
    base.target,
    MARKET_TYPES.LINEAR,
    15,
    1,
    1000000,
    1_000_000,
    99970,
    99990
  );

  await crystal.deploy(
    false,
    quote.target,
    base.target,
    MARKET_TYPES.LINEAR,
    15,
    1,
    1000000,
    1_000_000,
    99970,
    99990
  );

  const linearMarket = await ethers.getContractAt("CrystalMarket", linearMarketAddr);

  // Deploy weth/token1 market (weth as quote) for ETH-as-quote testing
  const wethQuoteMarketAddr = await crystal.deploy.staticCall(
    true,
    weth.target,
    token1.target,
    MARKET_TYPES.LINEAR,
    15,
    1,
    1000000,
    1_000_000,
    99970,
    99990
  );

  await crystal.deploy(
    true,
    weth.target,
    token1.target,
    MARKET_TYPES.LINEAR,
    15,
    1,
    1000000,
    1_000_000,
    99970,
    99990
  );

  const wethQuoteMarket = await ethers.getContractAt("CrystalMarket", wethQuoteMarketAddr);

  for (const account of accounts) {
    await quote.connect(account).approve(crystal.target, MAX_UINT256);
    await base.connect(account).approve(crystal.target, MAX_UINT256);
    await weth.connect(account).approve(crystal.target, MAX_UINT256);
    await token1.connect(account).approve(crystal.target, MAX_UINT256);
    await token2.connect(account).approve(crystal.target, MAX_UINT256);
  }

  await crystal.connect(maker).registerUser(maker.address);
  await crystal.connect(taker).registerUser(taker.address);

  const depositAmount = ethers.parseUnits("100000", 6);
  const depositAmountBase = ethers.parseEther("100000");
  const depositAmountWeth = ethers.parseEther("1000");

  await crystal.connect(maker).deposit(quote.target, depositAmount);
  await crystal.connect(maker).deposit(base.target, depositAmountBase);
  await crystal.connect(maker).deposit(weth.target, depositAmountWeth);

  await crystal.connect(taker).deposit(quote.target, depositAmount);
  await crystal.connect(taker).deposit(base.target, depositAmountBase);
  await crystal.connect(taker).deposit(weth.target, depositAmountWeth);

  return {
    crystal,
    market,
    linearMarket,
    wethQuoteMarket,
    weth,
    quote,
    base,
    token1,
    token2,
    owner,
    maker,
    taker,
    vaultOperator,
    depositor,
    user1,
    user2,
    gov,
    marketParams,
  };
}

/**
 * Deploy launchpad fixture - includes token creation
 * @returns {Object} - Deployed contracts with launchpad token
 */
async function launchpadFixture() {
  const base = await deployFixture();

  const tokenAddr = await base.crystal.connect(base.owner).createToken.staticCall(
    "Test Token",
    "TEST",
    "ipfs://metadata",
    "A test launchpad token",
    "https://twitter.com/test",
    "https://t.me/test",
    "",
    ""
  );

  await base.crystal.connect(base.owner).createToken(
    "Test Token",
    "TEST",
    "ipfs://metadata",
    "A test launchpad token",
    "https://twitter.com/test",
    "https://t.me/test",
    "",
    ""
  );

  const launchpadToken = await ethers.getContractAt("CrystalToken", tokenAddr);

  return {
    ...base,
    launchpadToken,
    launchpadTokenAddr: tokenAddr,
  };
}

/**
 * Deploy vault fixture - includes vault factory and vault
 * @returns {Object} - Deployed contracts with vault
 */
async function vaultFixture() {
  const base = await deployFixture();

  const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
  const vaultFactory = await CrystalVaultFactory.deploy(
    base.crystal.target,
    base.owner.address,
    ethers.ZeroAddress,
    100,
    100,
    0,
  );

  await base.quote.connect(base.vaultOperator).approve(vaultFactory.target, MAX_UINT256);
  await base.weth.connect(base.vaultOperator).approve(vaultFactory.target, MAX_UINT256);
  await base.quote.connect(base.depositor).approve(vaultFactory.target, MAX_UINT256);
  await base.weth.connect(base.depositor).approve(vaultFactory.target, MAX_UINT256);

  const quoteDecimals = await base.quote.decimals();
  const wethDecimals = 18n;
  const amountQuote = 1000n * 10n ** quoteDecimals;
  const amountBase = 1000n * 10n ** wethDecimals;

  const vaultTx = await vaultFactory.connect(base.vaultOperator).deploy(
    base.quote.target,
    base.weth.target,
    amountQuote,
    amountBase,
    0,
    0,
    true,
    ["Test Vault", "A test vault for testing", "crystal.exchange", "x.com/test", "telegram"]
  );

  const receipt = await vaultTx.wait();
  const vaultDeployedEvent = receipt.logs.map(log => {
    try {
      return vaultFactory.interface.parseLog(log);
    } catch { return null; }
  }).find(ev => ev && ev.name === "VaultDeployed");

  const vault = await ethers.getContractAt("CrystalVault", vaultDeployedEvent.args.vault);

  return {
    ...base,
    vaultFactory,
    vault,
    vaultOperator: base.vaultOperator,
  };
}

/**
 * Deploy multi-market fixture - multiple markets for batch testing
 * @returns {Object} - Deployed contracts with multiple markets
 */
async function multiMarketFixture() {
  const base = await deployFixture();

  const markets = [base.market, base.linearMarket];
  const market3Addr = await base.crystal.deploy.staticCall(
    false,
    base.token1.target,
    base.token2.target,
    MARKET_TYPES.LOGARITHMIC,
    18,
    1,
    1_000_000_000_000_000,
    1_000_000,
    99970,
    99990
  );

  await base.crystal.deploy(
    false,
    base.token1.target,
    base.token2.target,
    MARKET_TYPES.LOGARITHMIC,
    18,
    1,
    1_000_000_000_000_000,
    1_000_000,
    99970,
    99990
  );

  const market3 = await ethers.getContractAt("CrystalMarket", market3Addr);
  markets.push(market3);

  return {
    ...base,
    markets,
    market3,
  };
}

/**
 * Calculate price parameters for a market
 * @param {Object} market - Market contract
 * @param {Object} quote - Quote token contract
 * @param {Object} base - Base token contract (or WETH)
 * @param {number} rawPrice - Human-readable price
 * @returns {Object} - Price parameters
 */
async function calculatePriceParams(market, quote, base, rawPrice) {
  const scaleFactor = BigInt(await market.scaleFactor());
  const quoteDecimals = BigInt(await quote.decimals());
  const baseDecimals = base.decimals ? BigInt(await base.decimals()) : 18n;

  const priceFactor = quoteDecimals >= baseDecimals
    ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
    : scaleFactor / 10n ** (baseDecimals - quoteDecimals);

  const priceParam = BigInt(rawPrice) * priceFactor;

  return {
    scaleFactor,
    quoteDecimals,
    baseDecimals,
    priceFactor,
    priceParam,
  };
}

/**
 * Helper to advance blockchain time
 * @param {number} seconds - Seconds to advance
 */
async function advanceTime(seconds) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine");
}

/**
 * Helper to get current block timestamp
 * @returns {number} - Current timestamp
 */
async function getBlockTimestamp() {
  const block = await ethers.provider.getBlock("latest");
  return block.timestamp;
}

/**
 * Helper to mine blocks
 * @param {number} blocks - Number of blocks to mine
 */
async function mineBlocks(blocks) {
  for (let i = 0; i < blocks; i++) {
    await ethers.provider.send("evm_mine");
  }
}

module.exports = {
  deployFixture,
  launchpadFixture,
  vaultFixture,
  multiMarketFixture,
  calculatePriceParams,
  advanceTime,
  getBlockTimestamp,
  mineBlocks,
};
