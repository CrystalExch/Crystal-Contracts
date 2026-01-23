const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  launchpadFixture,
  advanceTime,
  TIME,
  findEvent,
} = require("../helpers");

describe("Integration: Launchpad Flow", function () {
  describe("Token Lifecycle", function () {
    it("Should create token and allow buying", async function () {
      const { crystal, launchpadToken, user1 } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.5");
      const tx = await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });
      const receipt = await tx.wait();

      expect(findEvent(receipt, crystal, "LaunchpadTrade")).to.not.be.undefined;

      const balance = await launchpadToken.balanceOf(user1.address);
      expect(balance).to.be.greaterThan(0n);
    });

    it("Should allow selling after buying", async function () {
      const { crystal, launchpadToken, user1 } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.5");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);

      await launchpadToken.connect(user1).approve(crystal.target, balance);

      const ethBefore = await ethers.provider.getBalance(user1.address);

      const tx = await crystal.connect(user1).sell(true, launchpadToken.target, balance / 2n, 0);
      const receipt = await tx.wait();
      const gasCost = receipt.gasUsed * receipt.gasPrice;

      const ethAfter = await ethers.provider.getBalance(user1.address);
      expect(ethAfter + gasCost).to.be.greaterThan(ethBefore);
    });

    it("Should track virtual reserves correctly", async function () {
      const { crystal, launchpadToken, user1 } = await launchpadFixture();

      const [nativeReserveBefore, tokenReserveBefore] = await crystal.getVirtualReserves(launchpadToken.target);

      const buyAmount = ethers.parseEther("0.5");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const [nativeReserveAfter, tokenReserveAfter] = await crystal.getVirtualReserves(launchpadToken.target);

      expect(nativeReserveAfter).to.be.greaterThan(nativeReserveBefore);
      expect(tokenReserveAfter).to.be.lessThan(tokenReserveBefore);
    });
  });

  describe("Quote Functions", function () {
    it("quoteBuy() should return expected amounts", async function () {
      const { crystal, launchpadToken } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      const result = await crystal.quoteBuy.staticCall(true, launchpadToken.target, buyAmount, 0);
      const amountIn = result[0];
      const amountOut = result[1];

      expect(amountIn).to.be.greaterThan(0n);
      expect(amountOut).to.be.greaterThan(0n);
    });

    it.skip("quoteSell() should return expected amounts", async function () {
      const { crystal, launchpadToken, user1 } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.5");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);
      expect(balance).to.be.greaterThan(0n);
      await launchpadToken.connect(user1).approve(crystal.target, balance);

      const result = await crystal.quoteSell.staticCall(true, launchpadToken.target, balance / 2n, 0);

      expect(result[1]).to.be.greaterThan(0n);
    });
  });

  describe("Multiple Users", function () {
    it("Should handle multiple buyers", async function () {
      const { crystal, launchpadToken, user1, user2, maker, taker } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");

      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });
      await crystal.connect(user2).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });
      await crystal.connect(maker).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });
      await crystal.connect(taker).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      expect(await launchpadToken.balanceOf(user1.address)).to.be.greaterThan(0n);
      expect(await launchpadToken.balanceOf(user2.address)).to.be.greaterThan(0n);
      expect(await launchpadToken.balanceOf(maker.address)).to.be.greaterThan(0n);
      expect(await launchpadToken.balanceOf(taker.address)).to.be.greaterThan(0n);
    });

    it("Later buyers should get fewer tokens (bonding curve)", async function () {
      const { crystal, launchpadToken, user1, user2 } = await launchpadFixture();

      const buyAmount = ethers.parseEther("1");

      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });
      const balance1 = await launchpadToken.balanceOf(user1.address);

      await crystal.connect(user2).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });
      const balance2 = await launchpadToken.balanceOf(user2.address);

      expect(balance2).to.be.lessThan(balance1);
    });
  });
});
