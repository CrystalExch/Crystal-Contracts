const { ethers } = require("hardhat");
const { ACTIONS } = require("./constants");

/**
 * Create header for fallback function calls
 * Header format (256 bits total):
 * - bits 252-255: balanceMode (4 bits)
 * - bits 172-251: bribe (80 bits)
 * - bits 160-171: numActions (12 bits)
 * - bits 0-159: market address (160 bits)
 * @param {string} marketAddr - Market contract address
 * @param {number} numActions - Number of actions in this batch
 * @param {number} balanceMode - Balance mode bits (0-15)
 * @param {bigint} bribe - Bribe amount in wei
 * @returns {string} - Encoded header as hex string
 */
function makeHeader(marketAddr, numActions, balanceMode = 0n, bribe = 0n) {
  const m = BigInt(marketAddr);
  const hdr = (BigInt(balanceMode) << 252n) | (BigInt(bribe) << 172n) | (BigInt(numActions) << 160n) | m;
  return ethers.zeroPadValue(ethers.toBeHex(hdr), 32);
}

/**
 * Encode a single action for fallback function
 * @param {number} action - Action type (1-12)
 * @param {bigint} price - Price parameter
 * @param {bigint} size - Size parameter
 * @param {bigint} cloid - Client order ID (optional)
 * @returns {string} - Encoded action as hex string
 */
function encodeAction(action, price, size, cloid = 0n) {
  const a = BigInt(action);
  const p = BigInt(price);
  const s = BigInt(size);
  const c = BigInt(cloid);
  const chunk = (a << 252n) | (c << 192n) | (p << 112n) | s;
  return ethers.zeroPadValue(ethers.toBeHex(chunk), 32);
}

/**
 * Encode a market order action
 * @param {boolean} isBuy - True for buy, false for sell
 * @param {boolean} isExactInput - True for exact input, false for exact output
 * @param {bigint} worstPrice - Worst acceptable price
 * @param {bigint} size - Order size
 * @returns {string} - Encoded action as hex string
 */
function encodeMarketOrder(isBuy, isExactInput, worstPrice, size) {
  const action = isBuy ? ACTIONS.MARKET_BUY : ACTIONS.MARKET_SELL;
  const options = isExactInput ? 0n : 1n;
  return encodeAction(action, worstPrice, size, options);
}

module.exports = {
  makeHeader,
  encodeAction,
  encodeMarketOrder,
};