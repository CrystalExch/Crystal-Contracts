/**
 * Price and tick utilities for Crystal contract testing
 */

/**
 * Calculate scaled price from raw price
 * @param {bigint} rawPrice - Human-readable price
 * @param {bigint} scaleFactor - Market scale factor
 * @param {bigint} quoteDecimals - Quote token decimals
 * @param {bigint} baseDecimals - Base token decimals
 * @returns {bigint} - Scaled price for contract
 */
function calculateScaledPrice(rawPrice, scaleFactor, quoteDecimals, baseDecimals) {
  const priceFactor = quoteDecimals >= baseDecimals
    ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
    : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
  return BigInt(rawPrice) * priceFactor;
}

/**
 * Calculate price factor from market parameters
 * @param {bigint} scaleFactor - Market scale factor
 * @param {bigint} quoteDecimals - Quote token decimals
 * @param {bigint} baseDecimals - Base token decimals
 * @returns {bigint} - Price factor
 */
function calculatePriceFactor(scaleFactor, quoteDecimals, baseDecimals) {
  return quoteDecimals >= baseDecimals
    ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
    : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
}

const DECADE_THRESHOLDS = [
  1000n,
  1000000n,
  1000000000n, 
  1000000000000n,
  1000000000000000n,
];

/**
 * Convert price to tick for market type 0 (linear)
 * @param {bigint} price - Price value
 * @param {bigint} tickSize - Tick size
 * @returns {bigint} - Tick value
 */
function priceToTickLinear(price, tickSize) {
  if (price % tickSize !== 0n) {
    throw new Error("Price not divisible by tick size");
  }
  return price / tickSize;
}

/**
 * Convert tick to price for market type 0 (linear)
 * @param {bigint} tick - Tick value
 * @param {bigint} tickSize - Tick size
 * @returns {bigint} - Price value
 */
function tickToPriceLinear(tick, tickSize) {
  return tick * tickSize;
}

/**
 * Convert price to tick for market type 1/2 (logarithmic)
 * Simplified approximation - actual contract uses assembly for efficiency
 * @param {bigint} price - Price value
 * @returns {bigint} - Tick value (approximate)
 */
function priceToTickLogarithmic(price) {
  if (price > 1000000000000000n) {
    throw new Error("Price exceeds 1e15 maximum");
  }

  let tick = 0n;
  let threshold = 1n;

  while (threshold * 1000n <= price && threshold < 1000000000000000n) {
    threshold *= 1000n;
    tick += 900n;
  }

  tick += (price - threshold) / (threshold / 100n);

  return tick;
}

/**
 * Validate price against tick size
 * @param {bigint} price - Price to validate
 * @param {bigint} tickSize - Tick size
 * @param {number} marketType - Market type (0, 1, 2, 3)
 * @returns {boolean} - True if valid
 */
function isValidPrice(price, tickSize, marketType) {
  if (marketType === 0) {
    return price % tickSize === 0n;
  }

  return price > 0n && price <= 1000000000000000n;
}

/**
 * Round price up to valid tick
 * @param {bigint} price - Price to round
 * @param {bigint} tickSize - Tick size
 * @returns {bigint} - Rounded price
 */
function roundPriceUp(price, tickSize) {
  const remainder = price % tickSize;
  if (remainder === 0n) return price;
  return price + (tickSize - remainder);
}

/**
 * Round price down to valid tick
 * @param {bigint} price - Price to round
 * @param {bigint} tickSize - Tick size
 * @returns {bigint} - Rounded price
 */
function roundPriceDown(price, tickSize) {
  return price - (price % tickSize);
}

/**
 * Calculate quote amount from base amount and price
 * @param {bigint} baseAmount - Base token amount
 * @param {bigint} price - Scaled price
 * @param {bigint} scaleFactor - Market scale factor
 * @returns {bigint} - Quote token amount
 */
function calculateQuoteAmount(baseAmount, price, scaleFactor) {
  return (baseAmount * price) / scaleFactor;
}

/**
 * Calculate base amount from quote amount and price
 * @param {bigint} quoteAmount - Quote token amount
 * @param {bigint} price - Scaled price
 * @param {bigint} scaleFactor - Market scale factor
 * @returns {bigint} - Base token amount
 */
function calculateBaseAmount(quoteAmount, price, scaleFactor) {
  return (quoteAmount * scaleFactor) / price;
}

/**
 * Calculate AMM output amount using constant product formula
 * @param {bigint} amountIn - Input amount
 * @param {bigint} reserveIn - Input reserve
 * @param {bigint} reserveOut - Output reserve
 * @param {bigint} fee - Fee in basis points (e.g., 9970 for 0.3% fee)
 * @returns {bigint} - Output amount
 */
function getAmountOut(amountIn, reserveIn, reserveOut, fee = 9970n) {
  const amountInWithFee = amountIn * fee;
  const numerator = amountInWithFee * reserveOut;
  const denominator = reserveIn * 10000n + amountInWithFee;
  return numerator / denominator;
}

/**
 * Calculate AMM input amount needed for desired output
 * @param {bigint} amountOut - Desired output amount
 * @param {bigint} reserveIn - Input reserve
 * @param {bigint} reserveOut - Output reserve
 * @param {bigint} fee - Fee in basis points
 * @returns {bigint} - Required input amount
 */
function getAmountIn(amountOut, reserveIn, reserveOut, fee = 9970n) {
  const numerator = reserveIn * amountOut * 10000n;
  const denominator = (reserveOut - amountOut) * fee;
  return numerator / denominator + 1n;
}

/**
 * Calculate initial LP tokens for first liquidity provision
 * @param {bigint} amountQuote - Quote token amount
 * @param {bigint} amountBase - Base token amount
 * @returns {bigint} - LP tokens to mint (minus minimum liquidity)
 */
function calculateInitialLiquidity(amountQuote, amountBase) {
  const liquidity = sqrt(amountQuote * amountBase);
  const MIN_LIQUIDITY = 100000n;
  return liquidity - MIN_LIQUIDITY;
}

/**
 * Integer square root (Babylonian method)
 * @param {bigint} n - Number to take sqrt of
 * @returns {bigint} - Floor of square root
 */
function sqrt(n) {
  if (n < 0n) throw new Error("Square root of negative number");
  if (n === 0n) return 0n;
  let x = n;
  let y = (x + 1n) / 2n;
  while (y < x) {
    x = y;
    y = (x + n / x) / 2n;
  }
  return x;
}

module.exports = {
  calculateScaledPrice,
  calculatePriceFactor,
  priceToTickLinear,
  tickToPriceLinear,
  priceToTickLogarithmic,
  isValidPrice,
  roundPriceUp,
  roundPriceDown,
  calculateQuoteAmount,
  calculateBaseAmount,
  getAmountOut,
  getAmountIn,
  calculateInitialLiquidity,
  sqrt,
  DECADE_THRESHOLDS,
};
