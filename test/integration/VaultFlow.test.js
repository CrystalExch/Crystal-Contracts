const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  vaultFixture,
  calculatePriceParams,
  advanceTime,
  TIME,
  MAX_UINT256,
  findEvent,
} = require("../helpers");

describe("Integration: Vault Flow", function () {
  describe("Complete Vault Lifecycle", function () {
    it("Should deploy vault -> deposit -> trade -> withdraw", async function () {
      const { vault, vaultFactory, vaultOperator, depositor, crystal, market, quote, weth } = await vaultFixture();

      const initialShares = await vault.balanceOf(vaultOperator.address);
      expect(initialShares).to.be.greaterThan(0n);

      const depositQuote = ethers.parseUnits("500", 6);
      const depositBase = ethers.parseEther("0.5");

      await vaultFactory.connect(depositor).deposit(
        vault.target, quote.target, weth.target, depositQuote, depositBase, 0, 0
      );

      const depositorShares = await vault.balanceOf(depositor.address);
      expect(depositorShares).to.be.greaterThan(0n);

      const marketInfo = await crystal.getMarket(market.target);
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = BigInt(scaleFactor) * (10n ** quoteDecimals) / (10n ** 18n);
      const priceParam = 500n * priceFactor;
      const size = 1_000n;

      const actions = [{
        action: 2n,
        requireSuccess: false,
        cloid: 1n,
        param1: priceParam,
        param2: size
      }];

      await vault.connect(vaultOperator).execute(actions, 0);
      await vault.connect(depositor).approve(vaultFactory.target, depositorShares);

      const quoteBefore = await quote.balanceOf(depositor.address);

      await vaultFactory.connect(depositor).withdraw(
        vault.target, quote.target, weth.target, depositorShares / 2n, 0, 0
      );

      const quoteAfter = await quote.balanceOf(depositor.address);
      expect(quoteAfter).to.be.greaterThan(quoteBefore);
    });
  });

  describe("Multi-Depositor Scenario", function () {
    it("Should handle multiple depositors correctly", async function () {
      const { vault, vaultFactory, depositor, user1, quote, weth } = await vaultFixture();

      await quote.connect(user1).approve(vaultFactory.target, MAX_UINT256);
      await weth.connect(user1).approve(vaultFactory.target, MAX_UINT256);

      const depositAmount = ethers.parseUnits("100", 6);
      const depositBase = ethers.parseEther("0.1");

      await vaultFactory.connect(depositor).deposit(
        vault.target, quote.target, weth.target, depositAmount, depositBase, 0, 0
      );

      await vaultFactory.connect(user1).deposit(
        vault.target, quote.target, weth.target, depositAmount, depositBase, 0, 0
      );

      const shares1 = await vault.balanceOf(depositor.address);
      const shares2 = await vault.balanceOf(user1.address);

      expect(shares1).to.be.greaterThan(0n);
      expect(shares2).to.be.greaterThan(0n);

      expect(shares1).to.be.closeTo(shares2, shares1 / 10n);
    });
  });

  describe("Trading Flow", function () {
    it("Should allow operator to place and cancel orders", async function () {
      const { vault, vaultOperator, market, quote, crystal } = await vaultFixture();

      const marketInfo = await crystal.getMarket(market.target);
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = BigInt(scaleFactor) * (10n ** quoteDecimals) / (10n ** 18n);
      const priceParam = 500n * priceFactor;
      const size = 1_000n;

      const placeActions = [{
        action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: size
      }];
      await vault.connect(vaultOperator).execute(placeActions, 0);

      await vault.connect(vaultOperator).cancelAll();
    });

    it("Should track vault balances after trades", async function () {
      const { vault, vaultOperator, crystal, market, maker, quote, weth } = await vaultFixture();

      const [quoteBalanceBefore, baseBalanceBefore] = await vault.getBalances();

      const marketInfo = await crystal.getMarket(market.target);
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = BigInt(scaleFactor) * (10n ** quoteDecimals) / (10n ** 18n);
      const priceParam = 500n * priceFactor;
      const size = 1_000n;

      const actions = [{
        action: 3n,
        requireSuccess: false,
        cloid: 1n,
        param1: priceParam,
        param2: size
      }];
      await vault.connect(vaultOperator).execute(actions, 0);

      const [quoteBalanceAfter, baseBalanceAfter] = await vault.getBalances();

      expect(quoteBalanceAfter).to.equal(quoteBalanceBefore);
      expect(baseBalanceAfter).to.equal(baseBalanceBefore);
    });
  });

  describe("Withdrawal with Active Orders", function () {
    it("Should handle withdrawal when orders are active (decrease mode)", async function () {
      const { vault, vaultFactory, vaultOperator, depositor, market, quote, weth, owner, crystal } = await vaultFixture();

      await vaultFactory.connect(vaultOperator).changeDecreaseOnWithdraw(vault.target, true);

      await vaultFactory.connect(depositor).deposit(
        vault.target, quote.target, weth.target,
        ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0
      );

      const marketInfo = await crystal.getMarket(market.target);
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = BigInt(scaleFactor) * (10n ** quoteDecimals) / (10n ** 18n);
      const priceParam = 500n * priceFactor;

      const actions = [{
        action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 1_000n
      }];
      await vault.connect(vaultOperator).execute(actions, 0);

      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares);

      await vaultFactory.connect(depositor).withdraw(
        vault.target, quote.target, weth.target, shares / 2n, 0, 0
      );
    });
  });

  describe("Owner Full Withdrawal (Vault Closure)", function () {
    it("Should close vault when owner withdraws all shares", async function () {
      const { vault, vaultFactory, vaultOperator, quote, weth } = await vaultFixture();

      const shares = await vault.balanceOf(vaultOperator.address);
      await vault.connect(vaultOperator).approve(vaultFactory.target, shares);

      await vaultFactory.connect(vaultOperator).withdraw(
        vault.target, quote.target, weth.target, shares, 0, 0
      );

      expect(await vault.closed()).to.be.true;
      expect(await vault.locked()).to.be.true;
    });

    it("Should cancel all orders on vault closure", async function () {
      const { vault, vaultFactory, vaultOperator, market, quote, weth, crystal } = await vaultFixture();

      const marketInfo = await crystal.getMarket(market.target);
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = BigInt(scaleFactor) * (10n ** quoteDecimals) / (10n ** 18n);
      const priceParam = 500n * priceFactor;

      const actions = [{
        action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 1_000n
      }];
      await vault.connect(vaultOperator).execute(actions, 0);

      const shares = await vault.balanceOf(vaultOperator.address);
      await vault.connect(vaultOperator).approve(vaultFactory.target, shares);

      await vaultFactory.connect(vaultOperator).withdraw(
        vault.target, quote.target, weth.target, shares, 0, 0
      );

      expect(await vault.closed()).to.be.true;
    });
  });

  describe("Vault Locking", function () {
    it("Should prevent deposits when locked", async function () {
      const { vault, vaultFactory, depositor, quote, weth, vaultOperator } = await vaultFixture();

      await vaultFactory.connect(vaultOperator).lock(vault.target);

      await expect(
        vaultFactory.connect(depositor).deposit(
          vault.target, quote.target, weth.target,
          ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0
        )
      ).to.be.reverted;
    });

    it("Should allow unlock by owner", async function () {
      const { vault, vaultFactory, depositor, quote, weth, vaultOperator } = await vaultFixture();

      await vaultFactory.connect(vaultOperator).lock(vault.target);
      await vaultFactory.connect(vaultOperator).unlock(vault.target);

      await vaultFactory.connect(depositor).deposit(
        vault.target, quote.target, weth.target,
        ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0
      );
    });
  });
});
