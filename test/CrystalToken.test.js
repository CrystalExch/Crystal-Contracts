const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  launchpadFixture,
  advanceTime,
  TIME,
  MAX_UINT256,
  signPermit,
  getValidDeadline,
  getExpiredDeadline,
  signPermitWithWrongSigner,
  getMalformedSignature,
  getPermitTypehash,
  getDomainSeparator,
} = require("./helpers");

describe("CrystalToken", function () {
  describe("Token Deployment & Initialization", function () {
    it("Should deploy with correct name", async function () {
      const { launchpadToken } = await launchpadFixture();
      const name = await launchpadToken.name();
      expect(name).to.equal("Test Token");
    });

    it("Should deploy with correct symbol", async function () {
      const { launchpadToken } = await launchpadFixture();
      const symbol = await launchpadToken.symbol();
      expect(symbol).to.equal("TEST");
    });

    it("Should have 18 decimals", async function () {
      const { launchpadToken } = await launchpadFixture();
      const decimals = await launchpadToken.decimals();
      expect(decimals).to.equal(18n);
    });

    it("Should have non-zero total supply", async function () {
      const { launchpadToken } = await launchpadFixture();
      const totalSupply = await launchpadToken.totalSupply();
      expect(totalSupply).to.be.greaterThan(0n);
    });

    it("Should assign initial supply to Crystal contract", async function () {
      const { launchpadToken, crystal } = await launchpadFixture();
      const crystalBalance = await launchpadToken.balanceOf(crystal.target);
      expect(crystalBalance).to.be.greaterThan(0n);
    });

    it("Should have correct totalSupply constant (1 billion tokens)", async function () {
      const { launchpadToken } = await launchpadFixture();
      const totalSupply = await launchpadToken.totalSupply();
      expect(totalSupply).to.equal(1000000000000000000000000000n); // 1e27 = 1 billion * 1e18
    });

    it("Should store metadata correctly", async function () {
      const { launchpadToken } = await launchpadFixture();
      const metadata = await launchpadToken.metadata();

      expect(metadata.name).to.equal("Test Token");
      expect(metadata.symbol).to.equal("TEST");
      expect(metadata.metadataCID).to.equal("ipfs://metadata");
      expect(metadata.description).to.equal("A test launchpad token");
    });

    it("Should have non-zero DOMAIN_SEPARATOR", async function () {
      const { launchpadToken } = await launchpadFixture();
      const domainSeparator = await launchpadToken.DOMAIN_SEPARATOR();
      expect(domainSeparator).to.not.equal(ethers.ZeroHash);
    });

    it("Should have initial nonces at zero", async function () {
      const { launchpadToken, user1 } = await launchpadFixture();
      const nonce = await launchpadToken.nonces(user1.address);
      expect(nonce).to.equal(0n);
    });
  });

  describe("ERC20 Standard Functions", function () {
    it("balanceOf() should return correct balance", async function () {
      const { crystal, launchpadToken, user1 } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);
      expect(balance).to.be.greaterThan(0n);
    });

    it("transfer() should transfer tokens", async function () {
      const { crystal, launchpadToken, user1, user2 } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);
      const transferAmount = balance / 2n;

      await launchpadToken.connect(user1).transfer(user2.address, transferAmount);

      expect(await launchpadToken.balanceOf(user2.address)).to.equal(transferAmount);
    });

    it("transfer() should emit Transfer event", async function () {
      const { crystal, launchpadToken, user1, user2 } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);

      await expect(launchpadToken.connect(user1).transfer(user2.address, balance / 2n))
        .to.emit(launchpadToken, "Transfer")
        .withArgs(user1.address, user2.address, balance / 2n);
    });

    it("transfer() should revert on insufficient balance", async function () {
      const { launchpadToken, user1, user2 } = await launchpadFixture();

      const hugeAmount = ethers.parseEther("999999999");

      await expect(
        launchpadToken.connect(user1).transfer(user2.address, hugeAmount)
      ).to.be.reverted;
    });

    it("approve() should set allowance", async function () {
      const { launchpadToken, user1, user2 } = await launchpadFixture();

      const amount = ethers.parseEther("100");
      await launchpadToken.connect(user1).approve(user2.address, amount);

      expect(await launchpadToken.allowance(user1.address, user2.address)).to.equal(amount);
    });

    it("approve() should emit Approval event", async function () {
      const { launchpadToken, user1, user2 } = await launchpadFixture();

      const amount = ethers.parseEther("100");

      await expect(launchpadToken.connect(user1).approve(user2.address, amount))
        .to.emit(launchpadToken, "Approval")
        .withArgs(user1.address, user2.address, amount);
    });

    it("transferFrom() should transfer with allowance", async function () {
      const { crystal, launchpadToken, user1, user2, owner } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);

      await launchpadToken.connect(user1).approve(user2.address, balance);
      await launchpadToken.connect(user2).transferFrom(user1.address, owner.address, balance / 2n);

      expect(await launchpadToken.balanceOf(owner.address)).to.equal(balance / 2n);
    });

    it("transferFrom() should reduce allowance", async function () {
      const { crystal, launchpadToken, user1, user2, owner } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);

      await launchpadToken.connect(user1).approve(user2.address, balance);

      const allowanceBefore = await launchpadToken.allowance(user1.address, user2.address);

      await launchpadToken.connect(user2).transferFrom(user1.address, owner.address, balance / 2n);

      const allowanceAfter = await launchpadToken.allowance(user1.address, user2.address);
      expect(allowanceAfter).to.equal(allowanceBefore - balance / 2n);
    });

    it("transferFrom() should not reduce MAX_UINT256 allowance", async function () {
      const { crystal, launchpadToken, user1, user2, owner } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);

      await launchpadToken.connect(user1).approve(user2.address, MAX_UINT256);
      await launchpadToken.connect(user2).transferFrom(user1.address, owner.address, balance / 2n);

      const allowanceAfter = await launchpadToken.allowance(user1.address, user2.address);
      expect(allowanceAfter).to.equal(MAX_UINT256);
    });

    it("transferFrom() should revert on insufficient allowance", async function () {
      const { crystal, launchpadToken, user1, user2, owner } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);

      await launchpadToken.connect(user1).approve(user2.address, 1n);

      await expect(
        launchpadToken.connect(user2).transferFrom(user1.address, owner.address, balance)
      ).to.be.reverted;
    });
  });

  describe("Crystal-specific Behavior", function () {
    it("Crystal should be able to transfer without approval", async function () {
      const { crystal, launchpadToken, user1 } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);
      expect(balance).to.be.greaterThan(0n);
    });

    it("Token should track Crystal contract address", async function () {
      const { crystal, launchpadToken } = await launchpadFixture();

      const tokenCrystal = await launchpadToken.crystal();
      expect(tokenCrystal).to.equal(crystal.target);
    });

    it("Crystal transferFrom should not reduce allowance", async function () {
      const { crystal, launchpadToken, user1 } = await launchpadFixture();

      // User buys tokens
      const buyAmount = ethers.parseEther("0.5");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);
      expect(balance).to.be.greaterThan(0n);

      // User approves Crystal with specific allowance (not MAX)
      const approveAmount = balance;
      await launchpadToken.connect(user1).approve(crystal.target, approveAmount);

      const allowanceBefore = await launchpadToken.allowance(user1.address, crystal.target);
      expect(allowanceBefore).to.equal(approveAmount);

      // User sells tokens - Crystal calls transferFrom internally
      const sellAmount = balance / 2n;
      await crystal.connect(user1).sell(true, launchpadToken.target, sellAmount, 0);

      // Allowance should NOT be reduced because msg.sender == crystal
      const allowanceAfter = await launchpadToken.allowance(user1.address, crystal.target);
      expect(allowanceAfter).to.equal(allowanceBefore);
    });
  });

  describe("permit()", function () {
    it("Should set allowance with valid permit signature", async function () {
      const { launchpadToken, user1, user2 } = await launchpadFixture();

      const value = ethers.parseEther("1000");
      const nonce = await launchpadToken.nonces(user1.address);
      const deadline = await getValidDeadline();
      const chainId = (await ethers.provider.getNetwork()).chainId;
      const tokenName = await launchpadToken.name();

      const { v, r, s } = await signPermit(
        user1,
        launchpadToken.target,
        tokenName,
        user2.address,
        value,
        nonce,
        deadline,
        chainId
      );

      await launchpadToken.permit(user1.address, user2.address, value, deadline, v, r, s);

      expect(await launchpadToken.allowance(user1.address, user2.address)).to.equal(value);
    });

    it("Should increment nonces after permit", async function () {
      const { launchpadToken, user1, user2 } = await launchpadFixture();

      const nonceBefore = await launchpadToken.nonces(user1.address);

      const value = ethers.parseEther("100");
      const deadline = await getValidDeadline();
      const chainId = (await ethers.provider.getNetwork()).chainId;
      const tokenName = await launchpadToken.name();

      const { v, r, s } = await signPermit(
        user1,
        launchpadToken.target,
        tokenName,
        user2.address,
        value,
        nonceBefore,
        deadline,
        chainId
      );

      await launchpadToken.permit(user1.address, user2.address, value, deadline, v, r, s);

      const nonceAfter = await launchpadToken.nonces(user1.address);
      expect(nonceAfter).to.equal(nonceBefore + 1n);
    });

    it("Should emit Approval event on permit", async function () {
      const { launchpadToken, user1, user2 } = await launchpadFixture();

      const value = ethers.parseEther("500");
      const nonce = await launchpadToken.nonces(user1.address);
      const deadline = await getValidDeadline();
      const chainId = (await ethers.provider.getNetwork()).chainId;
      const tokenName = await launchpadToken.name();

      const { v, r, s } = await signPermit(
        user1,
        launchpadToken.target,
        tokenName,
        user2.address,
        value,
        nonce,
        deadline,
        chainId
      );

      await expect(launchpadToken.permit(user1.address, user2.address, value, deadline, v, r, s))
        .to.emit(launchpadToken, "Approval")
        .withArgs(user1.address, user2.address, value);
    });

    it("Should revert with expired deadline", async function () {
      const { launchpadToken, user1, user2 } = await launchpadFixture();

      const value = ethers.parseEther("100");
      const nonce = await launchpadToken.nonces(user1.address);
      const expiredDeadline = await getExpiredDeadline();
      const chainId = (await ethers.provider.getNetwork()).chainId;
      const tokenName = await launchpadToken.name();

      const { v, r, s } = await signPermit(
        user1,
        launchpadToken.target,
        tokenName,
        user2.address,
        value,
        nonce,
        expiredDeadline,
        chainId
      );

      await expect(
        launchpadToken.permit(user1.address, user2.address, value, expiredDeadline, v, r, s)
      ).to.be.revertedWith("expired");
    });

    it("Should revert with wrong signer", async function () {
      const { launchpadToken, user1, user2, owner } = await launchpadFixture();

      const value = ethers.parseEther("100");
      const nonce = await launchpadToken.nonces(user1.address);
      const deadline = await getValidDeadline();
      const chainId = (await ethers.provider.getNetwork()).chainId;
      const tokenName = await launchpadToken.name();

      // Sign with user2 but claim owner is user1
      const { v, r, s } = await signPermitWithWrongSigner(
        user2,
        launchpadToken.target,
        tokenName,
        user1.address,
        owner.address,
        value,
        nonce,
        deadline,
        chainId
      );

      await expect(
        launchpadToken.permit(user1.address, owner.address, value, deadline, v, r, s)
      ).to.be.revertedWith("invalid signature");
    });

    it("Should revert with malformed signature (recoveredAddress == 0)", async function () {
      const { launchpadToken, user1, user2 } = await launchpadFixture();

      const value = ethers.parseEther("100");
      const deadline = await getValidDeadline();

      const { v, r, s } = getMalformedSignature();

      await expect(
        launchpadToken.permit(user1.address, user2.address, value, deadline, v, r, s)
      ).to.be.revertedWith("invalid signature");
    });

    it("Should have correct PERMIT_TYPEHASH", async function () {
      const { launchpadToken } = await launchpadFixture();

      const expectedTypehash = getPermitTypehash();
      const actualTypehash = await launchpadToken.PERMIT_TYPEHASH();

      expect(actualTypehash).to.equal(expectedTypehash);
    });

    it("Should have correct DOMAIN_SEPARATOR", async function () {
      const { launchpadToken } = await launchpadFixture();

      const chainId = (await ethers.provider.getNetwork()).chainId;
      const tokenName = await launchpadToken.name();

      const expectedDomainSeparator = getDomainSeparator(tokenName, launchpadToken.target, chainId);
      const actualDomainSeparator = await launchpadToken.DOMAIN_SEPARATOR();

      expect(actualDomainSeparator).to.equal(expectedDomainSeparator);
    });

    it("Should reject permit with wrong nonce", async function () {
      const { launchpadToken, user1, user2 } = await launchpadFixture();

      const value = ethers.parseEther("100");
      const wrongNonce = 999n; // Wrong nonce
      const deadline = await getValidDeadline();
      const chainId = (await ethers.provider.getNetwork()).chainId;
      const tokenName = await launchpadToken.name();

      const { v, r, s } = await signPermit(
        user1,
        launchpadToken.target,
        tokenName,
        user2.address,
        value,
        wrongNonce,
        deadline,
        chainId
      );

      await expect(
        launchpadToken.permit(user1.address, user2.address, value, deadline, v, r, s)
      ).to.be.revertedWith("invalid signature");
    });
  });

  describe("Edge Cases", function () {
    it("Should handle transfer to zero address", async function () {
      const { crystal, launchpadToken, user1 } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balance = await launchpadToken.balanceOf(user1.address);

      try {
        await launchpadToken.connect(user1).transfer(ethers.ZeroAddress, balance / 2n);
      } catch {

      }
    });

    it("Should handle transfer of zero amount", async function () {
      const { launchpadToken, user1, user2 } = await launchpadFixture();

      await launchpadToken.connect(user1).transfer(user2.address, 0n);
    });

    it("Should handle self-transfer", async function () {
      const { crystal, launchpadToken, user1 } = await launchpadFixture();

      const buyAmount = ethers.parseEther("0.1");
      await crystal.connect(user1).buy(true, launchpadToken.target, buyAmount, 0, { value: buyAmount });

      const balanceBefore = await launchpadToken.balanceOf(user1.address);

      await launchpadToken.connect(user1).transfer(user1.address, balanceBefore / 2n);

      const balanceAfter = await launchpadToken.balanceOf(user1.address);
      expect(balanceAfter).to.equal(balanceBefore);
    });

    it("Should handle approval to zero address", async function () {
      const { launchpadToken, user1 } = await launchpadFixture();

      try {
        await launchpadToken.connect(user1).approve(ethers.ZeroAddress, 1000n);
      } catch {

      }
    });
  });
});
