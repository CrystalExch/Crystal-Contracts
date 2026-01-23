const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  deployFixture,
  multiMarketFixture,
  calculatePriceParams,
  ACTIONS,
  makeHeader,
  encodeAction,
  buildFallbackData,
  buildMultiMarketData,
  findEvent,
  findAllEvents,
} = require("../helpers");

describe("Integration: Fallback Batching", function () {
  describe("Single Market Batching", function () {
    it("Should place multiple orders in single tx", async function () {
      const { crystal, market, maker, quote } = await deployFixture();
      const { priceParam, priceFactor } = await calculatePriceParams(market, quote, { decimals: async () => 18n }, 5);
      const size = 1_000_000n;

      const header = makeHeader(market.target, 5);
      const actions = [
        encodeAction(ACTIONS.BUY_LIMIT, priceParam, size),
        encodeAction(ACTIONS.BUY_LIMIT, priceParam + priceFactor, size),
        encodeAction(ACTIONS.BUY_LIMIT, priceParam + 2n * priceFactor, size),
        encodeAction(ACTIONS.SELL_LIMIT, priceParam * 2n, size),
        encodeAction(ACTIONS.SELL_LIMIT, priceParam * 3n, size),
      ];

      const data = ethers.concat([header, ...actions]);
      const tx = await maker.sendTransaction({ to: crystal.target, data });
      const receipt = await tx.wait();

      const events = findAllEvents(receipt, crystal, "OrdersUpdated");
      expect(events.length).to.be.greaterThan(0);
      expect(receipt.status).to.equal(1);
    });

    it("Should handle mix of place and cancel in single batch", async function () {
      const { crystal, market, maker, quote } = await deployFixture();
      const { priceParam } = await calculatePriceParams(market, quote, { decimals: async () => 18n }, 5);
      const size = 1_000_000n;

      let header = makeHeader(market.target, 1);
      let action = encodeAction(ACTIONS.BUY_LIMIT, priceParam, size);
      let data = ethers.concat([header, action]);
      await maker.sendTransaction({ to: crystal.target, data });

      header = makeHeader(market.target, 2);
      const placeAction = encodeAction(ACTIONS.BUY_LIMIT, priceParam * 2n, size);
      const cancelAction = encodeAction(ACTIONS.CANCEL, priceParam, 1n);
      data = ethers.concat([header, placeAction, cancelAction]);

      await maker.sendTransaction({ to: crystal.target, data });
    });

    it("Should execute 100 orders in single batch", async function () {
      const { crystal, market, maker, quote } = await deployFixture();
      const { priceParam, priceFactor } = await calculatePriceParams(market, quote, { decimals: async () => 18n }, 5);
      const size = 1_000_000n;

      const header = makeHeader(market.target, 100);
      const actions = Array.from({ length: 100 }, (_, i) => {
        const price = priceParam + BigInt(i) * priceFactor;
        return encodeAction(ACTIONS.BUY_LIMIT, price, size);
      });

      const data = ethers.concat([header, ...actions]);
      const tx = await maker.sendTransaction({ to: crystal.target, data });
      const receipt = await tx.wait();

      expect(receipt.status).to.equal(1);
    });

    it.skip("Should handle market orders in batch", async function () {
      const { crystal, market, maker, taker, quote, base } = await deployFixture();
      const { priceParam } = await calculatePriceParams(market, quote, { decimals: async () => 18n }, 5);
      const size = 1_000_000n;

      await crystal.connect(maker).limitOrder(market.target, false, 0, priceParam, size, maker.address);

      const header = makeHeader(market.target, 1);
      const action = encodeAction(ACTIONS.MARKET_BUY, priceParam * 2n, size / 2n);
      const data = ethers.concat([header, action]);

      const tx = await taker.sendTransaction({ to: crystal.target, data });
      const receipt = await tx.wait();

      expect(receipt.status).to.equal(1);
    });
  });

  describe("Balance Modes", function () {
    it("Should use internal balance (mode 1)", async function () {
      const { crystal, market, maker, quote } = await deployFixture();
      const { priceParam } = await calculatePriceParams(market, quote, { decimals: async () => 18n }, 5);
      const size = 1_000_000n;

      const depositAmount = ethers.parseUnits("10000", 6);
      await crystal.connect(maker).deposit(quote.target, depositAmount);

      const header = makeHeader(market.target, 1, 1n);
      const action = encodeAction(ACTIONS.BUY_LIMIT, priceParam, size);
      const data = ethers.concat([header, action]);

      await maker.sendTransaction({ to: crystal.target, data });
    });

    it("Should use external balance (mode 0)", async function () {
      const { crystal, market, maker, quote } = await deployFixture();
      const { priceParam } = await calculatePriceParams(market, quote, { decimals: async () => 18n }, 5);
      const size = 1_000_000n;

      const header = makeHeader(market.target, 1, 0n);
      const action = encodeAction(ACTIONS.BUY_LIMIT, priceParam, size);
      const data = ethers.concat([header, action]);

      await maker.sendTransaction({ to: crystal.target, data });
    });
  });

  describe("Bribe Handling", function () {
    it("Should send bribe to block.coinbase", async function () {
      const { crystal, market, maker, quote } = await deployFixture();
      const { priceParam } = await calculatePriceParams(market, quote, { decimals: async () => 18n }, 5);
      const size = 1_000_000n;
      const bribe = ethers.parseEther("0.01");

      const header = makeHeader(market.target, 1, 0n, bribe);
      const action = encodeAction(ACTIONS.BUY_LIMIT, priceParam, size);
      const data = ethers.concat([header, action]);

      await maker.sendTransaction({ to: crystal.target, data, value: bribe });
    });
  });

  describe("Error Handling", function () {
    it.skip("Should revert on invalid action count", async function () {
      const { crystal, market, maker, quote } = await deployFixture();
      const { priceParam } = await calculatePriceParams(market, quote, { decimals: async () => 18n }, 5);
      const size = 1_000_000n;

      const header = makeHeader(market.target, 3);
      const action = encodeAction(ACTIONS.BUY_LIMIT, priceParam, size);
      const data = ethers.concat([header, action]);

      await expect(
        maker.sendTransaction({ to: crystal.target, data })
      ).to.be.reverted;
    });

    it("Should revert for unregistered user", async function () {
      const { crystal, market, user1, quote } = await deployFixture();
      const { priceParam } = await calculatePriceParams(market, quote, { decimals: async () => 18n }, 5);
      const size = 1_000_000n;

      const header = makeHeader(market.target, 1);
      const action = encodeAction(ACTIONS.BUY_LIMIT, priceParam, size);
      const data = ethers.concat([header, action]);

      await expect(
        user1.sendTransaction({ to: crystal.target, data })
      ).to.be.reverted;
    });
  });
});
