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
 * @param {number} action - Action type (1-7)
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

/**
 * Encode a limit order action
 * @param {boolean} isBuy - True for buy, false for sell
 * @param {bigint} price - Limit price
 * @param {bigint} size - Order size
 * @param {bigint} cloid - Client order ID (optional)
 * @returns {string} - Encoded action as hex string
 */
function encodeLimitOrder(isBuy, price, size, cloid = 0n) {
  const action = isBuy ? ACTIONS.BUY_LIMIT : ACTIONS.SELL_LIMIT;
  return encodeAction(action, price, size, cloid);
}

/**
 * Encode a cancel order action
 * @param {bigint} price - Price of order to cancel
 * @param {bigint} orderId - Order ID to cancel
 * @returns {string} - Encoded action as hex string
 */
function encodeCancelOrder(price, orderId) {
  return encodeAction(ACTIONS.CANCEL, price, orderId);
}

/**
 * Encode a replace order action
 * @param {boolean} isBuy - True for buy, false for sell
 * @param {bigint} price - Original price (or 0 to keep current)
 * @param {bigint} orderId - Order ID to replace (or CLOID in upper bits)
 * @param {bigint} newPrice - New price (or 0 to keep current)
 * @param {bigint} newSize - New size (or 0 to keep current)
 * @returns {string} - Encoded action as hex string
 */
function encodeReplaceOrder(isBuy, price, orderId, newPrice, newSize) {
  const action = isBuy ? ACTIONS.REPLACE_BUY : ACTIONS.REPLACE_SELL;
  const chunk = (BigInt(action) << 252n) | (BigInt(newPrice) << 192n) | (BigInt(price) << 112n) | BigInt(orderId);
  return ethers.zeroPadValue(ethers.toBeHex(chunk), 32);
}

/**
 * Build complete fallback calldata from header and actions
 * @param {string} header - Encoded header
 * @param {string[]} actions - Array of encoded actions
 * @returns {string} - Complete calldata
 */
function buildFallbackData(header, actions) {
  return ethers.concat([header, ...actions]);
}

/**
 * Build multi-market fallback calldata
 * @param {Array<{market: string, actions: string[], balanceMode?: number, bribe?: bigint}>} batches
 * @returns {string} - Complete calldata for multi-market batch
 */
function buildMultiMarketData(batches) {
  const chunks = batches.map(({ market, actions, balanceMode = 0, bribe = 0n }) => {
    const header = makeHeader(market, actions.length, balanceMode, bribe);
    return ethers.concat([header, ...actions]);
  });
  return ethers.concat(chunks);
}

/**
 * Parse OrdersUpdated event data
 * @param {string} orderData - Raw orderData from event
 * @returns {Object} - Parsed order information
 */
function parseOrdersUpdatedEvent(orderData) {
  const hex = orderData.slice(2); // Remove 0x prefix
  const flag = parseInt(hex.slice(0, 2), 16);
  const isBuy = (flag & 0x80) !== 0;
  const isActive = (flag & 0x40) !== 0;
  const hasCloid = (flag & 0x20) !== 0;

  return {
    flag,
    isBuy,
    isActive,
    hasCloid,
    rawData: orderData,
  };
}

/**
 * Parse Fill event data
 * @param {bigint} fillInfo - fillInfo from Fill event
 * @param {bigint} fillAmount - fillAmount from Fill event
 * @returns {Object} - Parsed fill information
 */
function parseFillEvent(fillInfo, fillAmount) {
  const price = (fillInfo >> 160n) & ((1n << 80n) - 1n);
  const orderId = (fillInfo >> 112n) & ((1n << 48n) - 1n);
  const remainingSize = fillInfo & ((1n << 112n) - 1n);
  const hasCloid = (fillInfo >> 240n) & 1n;

  return {
    price,
    orderId,
    remainingSize,
    fillAmount,
    hasCloid: hasCloid === 1n,
  };
}

module.exports = {
  makeHeader,
  encodeAction,
  encodeMarketOrder,
  encodeLimitOrder,
  encodeCancelOrder,
  encodeReplaceOrder,
  buildFallbackData,
  buildMultiMarketData,
  parseOrdersUpdatedEvent,
  parseFillEvent,
};
