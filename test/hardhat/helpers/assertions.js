const { expect } = require("chai");
const { ethers } = require("hardhat");

/**
 * Shared assertions for Crystal contract testing
 */

/**
 * Assert bitmap is set at specific position
 * @param {Object} crystal - Crystal contract
 * @param {string} marketAddr - Market address
 * @param {bigint} price - Price to check
 * @param {boolean} shouldBeSet - Expected state
 */
async function assertBitmapSet(crystal, marketAddr, price, shouldBeSet) {
  // This requires reading the internal bitmap storage
  // Implementation depends on contract storage layout
  // For now, we check via getPriceLevel
  const priceLevel = await crystal.getPriceLevel(marketAddr, price);
  if (shouldBeSet) {
    expect(priceLevel.size).to.be.greaterThan(0n, `Bitmap at price ${price} should be set`);
  } else {
    expect(priceLevel.size).to.equal(0n, `Bitmap at price ${price} should not be set`);
  }
}

/**
 * Assert order exists at price level
 * @param {Object} crystal - Crystal contract
 * @param {string} marketAddr - Market address
 * @param {bigint} price - Price level
 * @param {bigint} orderId - Order ID
 */
async function assertOrderExists(crystal, marketAddr, price, orderId) {
  const order = await crystal.getOrder(marketAddr, price, orderId);
  expect(order.size).to.be.greaterThan(0n, `Order ${orderId} at price ${price} should exist`);
}

/**
 * Assert order does not exist
 * @param {Object} crystal - Crystal contract
 * @param {string} marketAddr - Market address
 * @param {bigint} price - Price level
 * @param {bigint} orderId - Order ID
 */
async function assertOrderNotExists(crystal, marketAddr, price, orderId) {
  const order = await crystal.getOrder(marketAddr, price, orderId);
  expect(order.size).to.equal(0n, `Order ${orderId} at price ${price} should not exist`);
}

/**
 * Parse and assert OrdersUpdated event
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertOrdersUpdatedEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "OrdersUpdated");
  expect(event).to.not.be.undefined;

  if (expectedValues.market) {
    expect(event.args.market).to.equal(expectedValues.market);
  }
  if (expectedValues.user) {
    expect(event.args.user).to.equal(expectedValues.user);
  }

  const orderData = event.args.orderData;
  const hex = orderData.slice(2);
  const flag = parseInt(hex.slice(0, 2), 16);

  const parsed = {
    isBuy: (flag & 0x80) !== 0,
    isActive: (flag & 0x40) !== 0,
    hasCloid: (flag & 0x20) !== 0,
    flag,
  };

  if (expectedValues.isBuy !== undefined) {
    expect(parsed.isBuy).to.equal(expectedValues.isBuy, "isBuy flag mismatch");
  }
  if (expectedValues.isActive !== undefined) {
    expect(parsed.isActive).to.equal(expectedValues.isActive, "isActive flag mismatch");
  }
  if (expectedValues.hasCloid !== undefined) {
    expect(parsed.hasCloid).to.equal(expectedValues.hasCloid, "hasCloid flag mismatch");
  }

  return { event, parsed };
}

/**
 * Parse and assert Fill event
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertFillEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "Fill");
  expect(event).to.not.be.undefined;

  if (expectedValues.market) {
    expect(event.args.market).to.equal(expectedValues.market);
  }
  if (expectedValues.user) {
    expect(event.args.user).to.equal(expectedValues.user);
  }

  const fillInfo = event.args.fillInfo;
  const parsed = {
    price: (fillInfo >> 160n) & ((1n << 80n) - 1n),
    orderId: (fillInfo >> 112n) & ((1n << 48n) - 1n),
    remainingSize: fillInfo & ((1n << 112n) - 1n),
    hasCloid: ((fillInfo >> 240n) & 1n) === 1n,
    fillAmount: event.args.fillAmount,
  };

  if (expectedValues.hasCloid !== undefined) {
    expect(parsed.hasCloid).to.equal(expectedValues.hasCloid, "CLOID flag mismatch in Fill event");
  }
  if (expectedValues.price !== undefined) {
    expect(parsed.price).to.equal(BigInt(expectedValues.price), "Price mismatch in Fill event");
  }

  return { event, parsed };
}

/**
 * Assert Trade event emitted
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertTradeEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "Trade");
  expect(event).to.not.be.undefined;

  if (expectedValues.market) {
    expect(event.args.market).to.equal(expectedValues.market);
  }
  if (expectedValues.user) {
    expect(event.args.user).to.equal(expectedValues.user);
  }
  if (expectedValues.isBuy !== undefined) {
    expect(event.args.isBuy).to.equal(expectedValues.isBuy);
  }

  return event;
}

/**
 * Assert Deposit event emitted
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertDepositEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "Deposit");
  expect(event).to.not.be.undefined;

  if (expectedValues.user) {
    expect(event.args.user).to.equal(expectedValues.user);
  }
  if (expectedValues.token) {
    expect(event.args.token).to.equal(expectedValues.token);
  }
  if (expectedValues.amount) {
    expect(event.args.amount).to.equal(BigInt(expectedValues.amount));
  }

  return event;
}

/**
 * Assert Withdraw event emitted
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertWithdrawEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "Withdraw");
  expect(event).to.not.be.undefined;

  if (expectedValues.user) {
    expect(event.args.user).to.equal(expectedValues.user);
  }
  if (expectedValues.token) {
    expect(event.args.token).to.equal(expectedValues.token);
  }
  if (expectedValues.amount) {
    expect(event.args.amount).to.equal(BigInt(expectedValues.amount));
  }

  return event;
}

/**
 * Assert MarketCreated event emitted
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertMarketCreatedEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "MarketCreated");
  expect(event).to.not.be.undefined;

  if (expectedValues.isCanonical !== undefined) {
    expect(event.args.isCanonical).to.equal(expectedValues.isCanonical);
  }
  if (expectedValues.quoteAsset) {
    expect(event.args.quoteAsset).to.equal(expectedValues.quoteAsset);
  }
  if (expectedValues.baseAsset) {
    expect(event.args.baseAsset).to.equal(expectedValues.baseAsset);
  }

  return event;
}

/**
 * Assert Mint event emitted (AMM liquidity add)
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertMintEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "Mint");
  expect(event).to.not.be.undefined;

  if (expectedValues.market) {
    expect(event.args.market).to.equal(expectedValues.market);
  }
  if (expectedValues.sender) {
    expect(event.args.sender).to.equal(expectedValues.sender);
  }

  return event;
}

/**
 * Assert Burn event emitted (AMM liquidity remove)
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertBurnEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "Burn");
  expect(event).to.not.be.undefined;

  if (expectedValues.market) {
    expect(event.args.market).to.equal(expectedValues.market);
  }

  return event;
}

/**
 * Assert Sync event emitted
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertSyncEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "Sync");
  expect(event).to.not.be.undefined;

  if (expectedValues.market) {
    expect(event.args.market).to.equal(expectedValues.market);
  }

  return event;
}

/**
 * Assert LaunchpadTrade event emitted
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertLaunchpadTradeEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "LaunchpadTrade");
  expect(event).to.not.be.undefined;

  if (expectedValues.token) {
    expect(event.args.token).to.equal(expectedValues.token);
  }
  if (expectedValues.user) {
    expect(event.args.user).to.equal(expectedValues.user);
  }
  if (expectedValues.isBuy !== undefined) {
    expect(event.args.isBuy).to.equal(expectedValues.isBuy);
  }

  return event;
}

/**
 * Assert Migrated event emitted
 * @param {Object} receipt - Transaction receipt
 * @param {Object} crystal - Crystal contract
 * @param {Object} expectedValues - Expected event values
 */
function assertMigratedEvent(receipt, crystal, expectedValues = {}) {
  const event = findEvent(receipt, crystal, "Migrated");
  expect(event).to.not.be.undefined;

  if (expectedValues.token) {
    expect(event.args.token).to.equal(expectedValues.token);
  }

  return event;
}

/**
 * Assert balance changed by expected amount
 * @param {Function} action - Async function to execute
 * @param {Object} token - Token contract
 * @param {string} address - Address to check
 * @param {bigint} expectedChange - Expected balance change (can be negative)
 */
async function assertBalanceChange(action, token, address, expectedChange) {
  const balanceBefore = await token.balanceOf(address);
  await action();
  const balanceAfter = await token.balanceOf(address);
  expect(balanceAfter - balanceBefore).to.equal(expectedChange);
}

/**
 * Assert ETH balance changed
 * @param {Function} action - Async function to execute
 * @param {string} address - Address to check
 * @param {bigint} expectedChange - Expected balance change
 * @param {bigint} tolerance - Tolerance for gas costs
 */
async function assertETHBalanceChange(action, address, expectedChange, tolerance = 0n) {
  const balanceBefore = await ethers.provider.getBalance(address);
  await action();
  const balanceAfter = await ethers.provider.getBalance(address);
  const actualChange = balanceAfter - balanceBefore;

  if (tolerance > 0n) {
    expect(actualChange).to.be.closeTo(expectedChange, tolerance);
  } else {
    expect(actualChange).to.equal(expectedChange);
  }
}

/**
 * Find event in transaction receipt
 * @param {Object} receipt - Transaction receipt
 * @param {Object} contract - Contract with interface
 * @param {string} eventName - Event name to find
 * @returns {Object|undefined} - Parsed event or undefined
 */
function findEvent(receipt, contract, eventName) {
  for (const log of receipt.logs) {
    try {
      const parsed = contract.interface.parseLog(log);
      if (parsed && parsed.name === eventName) {
        return { ...parsed, args: parsed.args };
      }
    } catch {
      continue;
    }
  }
  return undefined;
}

/**
 * Find all events of a specific type in transaction receipt
 * @param {Object} receipt - Transaction receipt
 * @param {Object} contract - Contract with interface
 * @param {string} eventName - Event name to find
 * @returns {Array} - Array of parsed events
 */
function findAllEvents(receipt, contract, eventName) {
  const events = [];
  for (const log of receipt.logs) {
    try {
      const parsed = contract.interface.parseLog(log);
      if (parsed && parsed.name === eventName) {
        events.push({ ...parsed, args: parsed.args });
      }
    } catch {
      continue;
    }
  }
  return events;
}

/**
 * Assert transaction reverts with specific error
 * @param {Promise} txPromise - Transaction promise
 * @param {string} errorName - Expected error name
 */
async function assertRevertsWith(txPromise, errorName) {
  await expect(txPromise).to.be.revertedWithCustomError(
    { interface: { getError: () => ({ name: errorName }) } },
    errorName
  );
}

module.exports = {
  assertBitmapSet,
  assertOrderExists,
  assertOrderNotExists,
  assertOrdersUpdatedEvent,
  assertFillEvent,
  assertTradeEvent,
  assertDepositEvent,
  assertWithdrawEvent,
  assertMarketCreatedEvent,
  assertMintEvent,
  assertBurnEvent,
  assertSyncEvent,
  assertLaunchpadTradeEvent,
  assertMigratedEvent,
  assertBalanceChange,
  assertETHBalanceChange,
  findEvent,
  findAllEvents,
  assertRevertsWith,
};
