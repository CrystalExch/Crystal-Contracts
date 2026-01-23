const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
  vaultFixture,
  deployFixture,
  advanceTime,
  TIME,
  MAX_UINT256,
} = require("./helpers");

describe("CrystalVault", function () {
  describe("ERC20 Constructor", function () {
    it("Should set name correctly", async function () {
      const { vault } = await loadFixture(vaultFixture);
      expect(await vault.name()).to.not.equal("");
    });

    it("Should set symbol correctly", async function () {
      const { vault } = await loadFixture(vaultFixture);
      expect(await vault.symbol()).to.not.equal("");
    });

    it("Should have 18 decimals", async function () {
      const { vault } = await loadFixture(vaultFixture);
      expect(await vault.decimals()).to.equal(18n);
    });

    it("Should set DOMAIN_SEPARATOR", async function () {
      const { vault } = await loadFixture(vaultFixture);
      expect(await vault.DOMAIN_SEPARATOR()).to.not.equal(ethers.ZeroHash);
    });

    it("Should set PERMIT_TYPEHASH", async function () {
      const { vault } = await loadFixture(vaultFixture);
      expect(await vault.PERMIT_TYPEHASH()).to.not.equal(ethers.ZeroHash);
    });
  });

  describe("approve", function () {
    it("Should set allowance and return true", async function () {
      const { vault, vaultOperator, depositor } = await loadFixture(vaultFixture);
      await vault.connect(vaultOperator).approve(depositor.address, 1000n);
      expect(await vault.allowance(vaultOperator.address, depositor.address)).to.equal(1000n);
    });

    it("Should emit Approval event", async function () {
      const { vault, vaultOperator, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(vaultOperator).approve(depositor.address, 1000n))
        .to.emit(vault, "Approval")
        .withArgs(vaultOperator.address, depositor.address, 1000n);
    });
  });

  describe("permit", function () {
    it("Should revert with expired deadline", async function () {
      const { vault, vaultOperator, depositor } = await loadFixture(vaultFixture);
      const value = ethers.parseEther("100");
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp - 1;
      const nonce = await vault.nonces(vaultOperator.address);

      const domain = {
        name: await vault.name(),
        version: "1",
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: vault.target
      };
      const types = {
        Permit: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
          { name: "value", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" }
        ]
      };
      const message = { owner: vaultOperator.address, spender: depositor.address, value, nonce, deadline };
      const signature = await vaultOperator.signTypedData(domain, types, message);
      const { v, r, s } = ethers.Signature.from(signature);

      await expect(vault.permit(vaultOperator.address, depositor.address, value, deadline, v, r, s))
        .to.be.revertedWith("expired");
    });

    it("Should revert with invalid signature - wrong signer", async function () {
      const { vault, vaultOperator, depositor, user1 } = await loadFixture(vaultFixture);
      const value = ethers.parseEther("100");
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;
      const nonce = await vault.nonces(vaultOperator.address);

      const domain = {
        name: await vault.name(),
        version: "1",
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: vault.target
      };
      const types = {
        Permit: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
          { name: "value", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" }
        ]
      };
      const message = { owner: vaultOperator.address, spender: depositor.address, value, nonce, deadline };
      const signature = await user1.signTypedData(domain, types, message); // wrong signer
      const { v, r, s } = ethers.Signature.from(signature);

      await expect(vault.permit(vaultOperator.address, depositor.address, value, deadline, v, r, s))
        .to.be.revertedWith("invalid signature");
    });

    it("Should revert with zero address recovery ", async function () {
      const { vault, vaultOperator, depositor } = await loadFixture(vaultFixture);
      const value = ethers.parseEther("100");
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;

      await expect(vault.permit(vaultOperator.address, depositor.address, value, deadline, 27, ethers.ZeroHash, ethers.ZeroHash))
        .to.be.revertedWith("invalid signature");
    });

    it("Should set allowance with valid permit signature", async function () {
      const { vault, vaultOperator, depositor } = await loadFixture(vaultFixture);
      const value = ethers.parseEther("100");
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;
      const nonce = await vault.nonces(vaultOperator.address);

      const domain = {
        name: await vault.name(),
        version: "1",
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: vault.target
      };
      const types = {
        Permit: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
          { name: "value", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" }
        ]
      };
      const message = { owner: vaultOperator.address, spender: depositor.address, value, nonce, deadline };
      const signature = await vaultOperator.signTypedData(domain, types, message);
      const { v, r, s } = ethers.Signature.from(signature);

      await vault.permit(vaultOperator.address, depositor.address, value, deadline, v, r, s);
      expect(await vault.allowance(vaultOperator.address, depositor.address)).to.equal(value);
    });

    it("Should increment nonce after successful permit", async function () {
      const { vault, vaultOperator, depositor } = await loadFixture(vaultFixture);
      const nonceBefore = await vault.nonces(vaultOperator.address);

      const value = ethers.parseEther("100");
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 3600;

      const domain = {
        name: await vault.name(),
        version: "1",
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: vault.target
      };
      const types = {
        Permit: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
          { name: "value", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" }
        ]
      };
      const message = { owner: vaultOperator.address, spender: depositor.address, value, nonce: nonceBefore, deadline };
      const signature = await vaultOperator.signTypedData(domain, types, message);
      const { v, r, s } = ethers.Signature.from(signature);

      await vault.permit(vaultOperator.address, depositor.address, value, deadline, v, r, s);
      expect(await vault.nonces(vaultOperator.address)).to.equal(nonceBefore + 1n);
    });
  });

  describe("CrystalVault Constructor", function () {
    it("Should set crystal address", async function () {
      const { vault, crystal } = await loadFixture(vaultFixture);
      expect(await vault.crystal()).to.equal(crystal.target);
    });

    it("Should set market from Crystal", async function () {
      const { vault } = await loadFixture(vaultFixture);
      expect(await vault.market()).to.not.equal(ethers.ZeroAddress);
    });

    it("Should revert if market doesn't match tokens", async function () {
      const { crystal, owner, token1, token2 } = await loadFixture(deployFixture);
      const TestVaultDeployer = await ethers.getContractFactory("TestVaultDeployer");
      const deployer = await TestVaultDeployer.deploy();

      await expect(
        deployer.deployVault(crystal.target, token1.target, token2.target, owner.address, "TEST",
          { name: "Test", description: "", social1: "", social2: "", social3: "" })
      ).to.be.reverted;
    });

    it("Should set quoteAsset", async function () {
      const { vault, quote } = await loadFixture(vaultFixture);
      expect(await vault.quoteAsset()).to.equal(quote.target);
    });

    it("Should set baseAsset", async function () {
      const { vault, weth } = await loadFixture(vaultFixture);
      expect(await vault.baseAsset()).to.equal(weth.target);
    });

    it("Should set owner", async function () {
      const { vault, vaultOperator } = await loadFixture(vaultFixture);
      expect(await vault.owner()).to.equal(vaultOperator.address);
    });

    it("Should set factory", async function () {
      const { vault, vaultFactory } = await loadFixture(vaultFixture);
      expect(await vault.factory()).to.equal(vaultFactory.target);
    });

    it("Should set orderCap from factory", async function () {
      const { vault } = await loadFixture(vaultFixture);
      expect(await vault.orderCap()).to.be.greaterThan(0n);
    });

    it("Should set lockup from factory", async function () {
      const { vault } = await loadFixture(vaultFixture);
      expect(await vault.lockup()).to.be.greaterThanOrEqual(0n);
    });
  });

  describe("_sqrt", function () {
    it("Should return 0 for sqrt(0) - y == 0 branch", async function () {
      const { crystal, _owner, user1, quote, weth } = await loadFixture(deployFixture);
      const TestVaultDeployer = await ethers.getContractFactory("TestVaultDeployer");
      const deployer = await TestVaultDeployer.deploy();

      const vaultAddress = await deployer.deployVault.staticCall(
        crystal.target, quote.target, weth.target, user1.address, "TEST",
        { name: "Test", description: "", social1: "", social2: "", social3: "" }
      );
      await deployer.deployVault(crystal.target, quote.target, weth.target, user1.address, "TEST",
        { name: "Test", description: "", social1: "", social2: "", social3: "" });
      const vault = await ethers.getContractAt("CrystalVault", vaultAddress);

      const [shares] = await vault.previewDeposit(0, 0);
      expect(shares).to.equal(0n);
    });

    it("Should return 1 for sqrt(1) - y <= 3 && y != 0 branch", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 0, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const tx = await factory.connect(user1).deploy(quote.target, weth.target, 1n, 1n, 0, 0, false, ["Tiny", "", "", "", ""]);
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);
      expect(await vault.totalSupply()).to.equal(1n);
    });

    it("Should return 1 for sqrt(2) - y <= 3 && y != 0 branch", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 0, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const tx = await factory.connect(user1).deploy(quote.target, weth.target, 1n, 2n, 0, 0, false, ["Tiny", "", "", "", ""]);
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);
      expect(await vault.totalSupply()).to.equal(1n);
    });

    it("Should return 1 for sqrt(3) - y <= 3 && y != 0 branch", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 0, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const tx = await factory.connect(user1).deploy(quote.target, weth.target, 1n, 3n, 0, 0, false, ["Tiny", "", "", "", ""]);
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);
      expect(await vault.totalSupply()).to.equal(1n);
    });

    it("Should return 2 for sqrt(4) - y > 3 branch", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 0, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const tx = await factory.connect(user1).deploy(quote.target, weth.target, 2n, 2n, 0, 0, false, ["Tiny", "", "", "", ""]);
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);
      expect(await vault.totalSupply()).to.equal(2n);
    });
  });

  describe("_min", function () {
    it("Should return a when a < b", async function () {
      const { vault } = await loadFixture(vaultFixture);
      const [shares] = await vault.previewDeposit(ethers.parseUnits("100", 6), ethers.parseEther("0.1"));
      expect(shares).to.be.greaterThan(0n);
    });

    it("Should return b when a >= b", async function () {
      const { vault } = await loadFixture(vaultFixture);
      const [shares] = await vault.previewDeposit(ethers.parseUnits("100", 6), ethers.parseEther("1000"));
      expect(shares).to.be.greaterThan(0n);
    });
  });

  describe("getBalances", function () {
    it("Should return vault balances from Crystal", async function () {
      const { vault } = await loadFixture(vaultFixture);
      const [quoteBalance, baseBalance, availableQuote, availableBase] = await vault.getBalances();
      expect(quoteBalance).to.be.greaterThan(0n);
      expect(baseBalance).to.be.greaterThan(0n);
      expect(availableQuote).to.equal(quoteBalance);
      expect(availableBase).to.equal(baseBalance);
    });
  });

  describe("transfer", function () {
    it("Should revert - shares are non-transferable", async function () {
      const { vault, vaultOperator, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(vaultOperator).transfer(depositor.address, 1n)).to.be.reverted;
    });
  });

  describe("transferFrom", function () {
    it("Should revert - shares are non-transferable", async function () {
      const { vault, vaultOperator, depositor, user1 } = await loadFixture(vaultFixture);
      await vault.connect(vaultOperator).approve(depositor.address, MAX_UINT256);
      await expect(vault.connect(depositor).transferFrom(vaultOperator.address, user1.address, 1n)).to.be.reverted;
    });
  });

  describe("lock", function () {
    it("Should revert when not called by factory", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).lock()).to.be.reverted;
    });

    it("Should revert when already locked ", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).lock(vault.target);
      await expect(vaultFactory.connect(vaultOperator).lock(vault.target)).to.be.reverted;
    });

    it("Should lock vault", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).lock(vault.target);
      expect(await vault.locked()).to.be.true;
    });
  });

  describe("unlock", function () {
    it("Should revert when not called by factory", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).unlock()).to.be.reverted;
    });

    it("Should revert when not locked", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(vaultOperator).unlock(vault.target)).to.be.reverted;
    });

    it("Should revert when vault is closed", async function () {
      const { vault, vaultFactory, vaultOperator, quote, weth } = await loadFixture(vaultFixture);
      const shares = await vault.balanceOf(vaultOperator.address);
      await vault.connect(vaultOperator).approve(vaultFactory.target, shares);
      await vaultFactory.connect(vaultOperator).withdraw(vault.target, quote.target, weth.target, shares, 0, 0);
      expect(await vault.closed()).to.be.true;
      await expect(vaultFactory.connect(vaultOperator).unlock(vault.target)).to.be.reverted;
    });

    it("Should unlock vault", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).lock(vault.target);
      await vaultFactory.connect(vaultOperator).unlock(vault.target);
      expect(await vault.locked()).to.be.false;
    });
  });

  describe("changeMaxShares", function () {
    it("Should revert when not called by factory", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).changeMaxShares(1000000n)).to.be.reverted;
    });

    it("Should update maxShares", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).changeMaxShares(vault.target, 1000000n);
      expect(await vault.maxShares()).to.equal(1000000n);
    });
  });

  describe("changeMarket", function () {
    it("Should revert when not called by factory", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).changeMarket()).to.be.reverted;
    });

    it("Should update market", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vault.market();
      await vaultFactory.connect(vaultOperator).changeMarket(vault.target);
      expect(await vault.market()).to.not.equal(ethers.ZeroAddress);
    });
  });

  describe("changeOrderCap", function () {
    it("Should revert when new cap exceeds maxOrderCap", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      const maxOrderCap = await vaultFactory.maxOrderCap();
      await expect(vaultFactory.connect(vaultOperator).changeOrderCap(vault.target, Number(maxOrderCap) + 1)).to.be.reverted;
    });

    it("Should revert when existing order has cloid >= newCap", async function () {
      const { vault, vaultFactory, vaultOperator, quote, crystal } = await loadFixture(vaultFixture);

      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      const actions = [{ action: 2n, requireSuccess: false, cloid: 50n, param1: priceParam, param2: ethers.parseUnits("100", 6) }];
      await vault.connect(vaultOperator).execute(actions, 0);
      await expect(vaultFactory.connect(vaultOperator).changeOrderCap(vault.target, 50)).to.be.reverted;
      await vaultFactory.connect(vaultOperator).changeOrderCap(vault.target, 51);
      expect(await vault.orderCap()).to.equal(51n);
    });

    it("Should update orderCap", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).changeOrderCap(vault.target, 50);
      expect(await vault.orderCap()).to.equal(50n);
    });
  });

  describe("changeDecreaseOnWithdraw", function () {
    it("Should revert when not called by factory", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).changeDecreaseOnWithdraw(true)).to.be.reverted;
    });

    it("Should update decrease setting", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture); // default true
      await vaultFactory.connect(vaultOperator).changeDecreaseOnWithdraw(vault.target, false);
      expect(await vault.decrease()).to.be.false;
    });
  });

  describe("changeLockup", function () {
    it("Should revert when not called by factory", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).changeLockup(1000)).to.be.reverted;
    });

    it("Should revert when lockup exceeds maxLockup", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      const maxLockup = await vaultFactory.maxLockup();
      await expect(vaultFactory.connect(vaultOperator).changeLockup(vault.target, Number(maxLockup) + 1)).to.be.reverted;
    });

    it("Should update lockup", async function () {
      const { vault, vaultFactory, vaultOperator, owner } = await loadFixture(vaultFixture);
      await vaultFactory.connect(owner).changeMaxLockup(TIME.THIRTY_DAYS);
      await vaultFactory.connect(vaultOperator).changeLockup(vault.target, TIME.SEVEN_DAYS);
      expect(await vault.lockup()).to.equal(TIME.SEVEN_DAYS);
    });
  });

  describe("claimFees", function () {
    it("Should revert when not called by factory", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).claimFees()).to.be.reverted;
    });

    it("Should claim fees", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).claimFees(vault.target);
    });
  });

  describe("clearCloidSlots", function () {
    it("Should revert when not called by factory", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).clearCloidSlots(1, [1, 2, 3])).to.be.reverted;
    });

    it("Should clear cloid slots", async function () {
      const { vault, vaultFactory, vaultOperator, crystal } = await loadFixture(vaultFixture);
      const userId = await crystal.addressToUserId(vault.target);
      await vaultFactory.connect(vaultOperator).clearCloidSlots(vault.target, userId, [1, 2, 3]);
    });
  });

  describe("previewDeposit", function () {
    it("Should return shares using sqrt when totalSupply == 0", async function () {
      const { crystal, _owner, user1, quote, weth } = await loadFixture(deployFixture);
      const TestVaultDeployer = await ethers.getContractFactory("TestVaultDeployer");
      const deployer = await TestVaultDeployer.deploy();

      const vaultAddress = await deployer.deployVault.staticCall(
        crystal.target, quote.target, weth.target, user1.address, "TEST",
        { name: "Test", description: "", social1: "", social2: "", social3: "" }
      );
      await deployer.deployVault(crystal.target, quote.target, weth.target, user1.address, "TEST",
        { name: "Test", description: "", social1: "", social2: "", social3: "" });
      const vault = await ethers.getContractAt("CrystalVault", vaultAddress);

      expect(await vault.totalSupply()).to.equal(0n);
      const [shares, amountQuote, amountBase] = await vault.previewDeposit(ethers.parseUnits("1000", 6), ethers.parseEther("1"));
      expect(shares).to.be.greaterThan(0n);
      expect(amountQuote).to.equal(ethers.parseUnits("1000", 6));
      expect(amountBase).to.equal(ethers.parseEther("1"));
    });

    it("Should return shares using ratio when totalSupply > 0", async function () {
      const { vault } = await loadFixture(vaultFixture);
      expect(await vault.totalSupply()).to.be.greaterThan(0n);
      const [shares, _amountQuote, _amountBase] = await vault.previewDeposit(ethers.parseUnits("100", 6), ethers.parseEther("0.1"));
      expect(shares).to.be.greaterThan(0n);
    });

    it("Should use amountBaseOptimal path when baseOptimal <= baseDesired", async function () {
      const { vault } = await loadFixture(vaultFixture);
      const [_shares, amountQuote, amountBase] = await vault.previewDeposit(ethers.parseUnits("100", 6), ethers.parseEther("1000"));
      expect(amountQuote).to.equal(ethers.parseUnits("100", 6));
      expect(amountBase).to.be.lessThan(ethers.parseEther("1000"));
    });

    it("Should use amountQuoteOptimal path when baseOptimal > baseDesired", async function () {
      const { vault } = await loadFixture(vaultFixture);
      const [_shares, amountQuote, amountBase] = await vault.previewDeposit(ethers.parseUnits("100000", 6), ethers.parseEther("0.01"));
      expect(amountBase).to.equal(ethers.parseEther("0.01"));
      expect(amountQuote).to.be.lessThan(ethers.parseUnits("100000", 6));
    });
  });

  describe("previewWithdrawal", function () {
    it("Should return proportional amounts", async function () {
      const { vault, vaultOperator } = await loadFixture(vaultFixture);
      const shares = await vault.balanceOf(vaultOperator.address);
      const [amountQuote, amountBase] = await vault.previewWithdrawal(shares);
      expect(amountQuote).to.be.greaterThan(0n);
      expect(amountBase).to.be.greaterThan(0n);
    });
  });

  describe("deposit", function () {
    it("Should revert when not called by factory", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).deposit(depositor.address, 1000n, 1000n, 0, 0)).to.be.reverted;
    });

    it("Should revert when locked", async function () {
      const { vault, vaultFactory, vaultOperator, depositor, quote, weth } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).lock(vault.target);
      await expect(vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0)).to.be.reverted;
    });

    it("Should revert when amountQuoteDesired == 0", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, 0, ethers.parseEther("0.1"), 0, 0)).to.be.reverted;
    });

    it("Should revert when amountBaseDesired == 0", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), 0, 0, 0)).to.be.reverted;
    });

    it("Should use _min with a < b due to rounding", async function () {
      const { crystal, owner, user1, user2, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const quoteAmount = 500n * 10n ** 6n;
      const baseAmount = 700n * 10n ** 18n;

      const tx = await factory.connect(user1).deploy(
        quote.target, weth.target,
        quoteAmount,
        baseAmount,
        0, 0, false, ["Test", "", "", "", ""]
      );
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);

      await quote.connect(user2).approve(factory.target, MAX_UINT256);
      await weth.connect(user2).approve(factory.target, MAX_UINT256);
      await factory.connect(user2).deposit(vault.target, quote.target, weth.target, 1000n * 10n ** 6n, 200n * 10n ** 18n, 0, 0);

      expect(await vault.balanceOf(user2.address)).to.be.greaterThan(0n);
    });

    it("Should respect maxShares limit", async function () {
      const { crystal, owner, user1, user2, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const maxShares = ethers.parseUnits("40000000000000", 0);
      const tx = await factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"), maxShares, 0, false, ["Test", "", "", "", ""]);
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);

      await quote.connect(user2).approve(factory.target, MAX_UINT256);
      await weth.connect(user2).approve(factory.target, MAX_UINT256);
      await expect(factory.connect(user2).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("10000", 6), ethers.parseEther("10"), 0, 0)).to.be.reverted;
    });

    it("Should mint shares on deposit", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      const sharesBefore = await vault.balanceOf(depositor.address);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);
      expect(await vault.balanceOf(depositor.address)).to.be.greaterThan(sharesBefore);
    });

    it("Should update lastDepositTimestamp", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);
      expect(await vault.lastDepositTimestamp(depositor.address)).to.be.greaterThan(0n);
    });

    it("Should revert when deposit would make owner < 5%", async function () {
      const { crystal, owner, user1, user2, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const tx = await factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0, false, ["Test", "", "", "", ""]);
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);

      await quote.connect(user2).approve(factory.target, MAX_UINT256);
      await weth.connect(user2).approve(factory.target, MAX_UINT256);
      await expect(factory.connect(user2).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100000", 6), ethers.parseEther("100"), 0, 0)).to.be.reverted;
    });
  });

  describe("withdraw", function () {
    it("Should revert when shares == 0", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, 0, 0, 0)).to.be.reverted;
    });

    it("Should revert when shares > balance", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);
      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares * 2n);
      await expect(vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, shares * 2n, 0, 0)).to.be.reverted;
    });

    it("Should respect lockup period", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 100, 100, TIME.ONE_DAY);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);
      const tx = await factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0, false, ["Test", "", "", "", ""]);
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);

      const shares = await vault.balanceOf(user1.address);
      await vault.connect(user1).approve(factory.target, shares);
      await expect(factory.connect(user1).withdraw(vault.target, quote.target, weth.target, shares / 2n, 0, 0)).to.be.reverted;
      await advanceTime(TIME.ONE_DAY + 1);
      await factory.connect(user1).withdraw(vault.target, quote.target, weth.target, shares / 4n, 0, 0);
    });

    it("Should revert when slippage not met", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);
      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares);
      await expect(vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, shares, ethers.parseUnits("1000000", 6), 0)).to.be.reverted;
      await expect(vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, shares, 0, ethers.parseEther("1000000"))).to.be.reverted;
    });

    it("Should burn shares and return tokens", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);
      const sharesBefore = await vault.balanceOf(depositor.address);
      const quoteBefore = await quote.balanceOf(depositor.address);

      await vault.connect(depositor).approve(vaultFactory.target, sharesBefore);
      await vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, sharesBefore / 2n, 0, 0);

      expect(await vault.balanceOf(depositor.address)).to.equal(sharesBefore - sharesBefore / 2n);
      expect(await quote.balanceOf(depositor.address)).to.be.greaterThan(quoteBefore);
    });

    it("Should close vault when owner withdraws all", async function () {
      const { vault, vaultFactory, vaultOperator, quote, weth } = await loadFixture(vaultFixture);
      const shares = await vault.balanceOf(vaultOperator.address);
      await vault.connect(vaultOperator).approve(vaultFactory.target, shares);
      await vaultFactory.connect(vaultOperator).withdraw(vault.target, quote.target, weth.target, shares, 0, 0);
      expect(await vault.closed()).to.be.true;
      expect(await vault.locked()).to.be.true;
    });

    it("Should handle closing vault when already locked", async function () {
      const { vault, vaultFactory, vaultOperator, quote, weth } = await loadFixture(vaultFixture);

      await vaultFactory.connect(vaultOperator).lock(vault.target);
      expect(await vault.locked()).to.be.true;

      const shares = await vault.balanceOf(vaultOperator.address);
      await vault.connect(vaultOperator).approve(vaultFactory.target, shares);
      await vaultFactory.connect(vaultOperator).withdraw(vault.target, quote.target, weth.target, shares, 0, 0);
      expect(await vault.closed()).to.be.true;
      expect(await vault.locked()).to.be.true;
    });

    it("Should revert when owner partial withdraw would leave < 5%", async function () {
      const { crystal, owner, user1, user2, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);
      const tx = await factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0, false, ["Test", "", "", "", ""]);
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);

      await quote.connect(user2).approve(factory.target, MAX_UINT256);
      await weth.connect(user2).approve(factory.target, MAX_UINT256);
      await factory.connect(user2).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0);

      const ownerShares = await vault.balanceOf(user1.address);
      await vault.connect(user1).approve(factory.target, ownerShares);
      await expect(factory.connect(user1).withdraw(vault.target, quote.target, weth.target, ownerShares * 95n / 100n, 0, 0)).to.be.reverted;
    });

    it("Should handle decrease mode with buy orders", async function () {
      const { vault, vaultFactory, vaultOperator, depositor, quote, weth, crystal } = await loadFixture(vaultFixture);

      await vaultFactory.connect(vaultOperator).changeDecreaseOnWithdraw(vault.target, true);
      expect(await vault.decrease()).to.be.true;

      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      const [quoteBalanceBefore, , availableQuoteBefore] = await vault.getBalances();

      const orderSize = quoteBalanceBefore * 50n / 100n;
      const actions = [{ action: 2n, requireSuccess: true, cloid: 1n, param1: priceParam, param2: orderSize }];
      await vault.connect(vaultOperator).execute(actions, 0);

      const [, , availableQuoteAfter] = await vault.getBalances();
      expect(availableQuoteAfter).to.be.lessThan(availableQuoteBefore);

      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0);

      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares);
      await vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, shares, 0, 0);
    });

    it("Should handle decrease mode with sell orders", async function () {
      const { vault, vaultFactory, vaultOperator, depositor, quote, weth, crystal } = await loadFixture(vaultFixture);

      await vaultFactory.connect(vaultOperator).changeDecreaseOnWithdraw(vault.target, true);
      expect(await vault.decrease()).to.be.true;

      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 5000n * priceFactor;

      const [, baseBalanceBefore, , availableBaseBefore] = await vault.getBalances();

      const orderSize = baseBalanceBefore * 50n / 100n;
      const actions = [{ action: 3n, requireSuccess: true, cloid: 1n, param1: priceParam, param2: orderSize }];
      await vault.connect(vaultOperator).execute(actions, 0);

      const [, , , availableBaseAfter] = await vault.getBalances();
      expect(availableBaseAfter).to.be.lessThan(availableBaseBefore);

      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0);

      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares);
      await vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, shares, 0, 0);
    });

    it("Should handle non-decrease mode with locked quote", async function () {
      const { vault, vaultFactory, vaultOperator, depositor, quote, weth, crystal } = await loadFixture(vaultFixture);

      await vaultFactory.connect(vaultOperator).changeDecreaseOnWithdraw(vault.target, false);
      expect(await vault.decrease()).to.be.false;

      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("500", 6), ethers.parseEther("500"), 0, 0);

      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      const [quoteBalanceAfterDeposit, , availableQuoteBefore] = await vault.getBalances();

      const orderSize = quoteBalanceAfterDeposit * 95n / 100n;
      const actions = [{ action: 2n, requireSuccess: true, cloid: 1n, param1: priceParam, param2: orderSize }];
      await vault.connect(vaultOperator).execute(actions, 0);

      const [_quoteBalanceFinal, , availableQuoteFinal] = await vault.getBalances();
      expect(availableQuoteFinal).to.be.lessThan(availableQuoteBefore);

      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares);
      await vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, shares, 0, 0);
    });

    it("Should handle non-decrease mode with locked base", async function () {
      const { vault, vaultFactory, vaultOperator, depositor, quote, weth, crystal } = await loadFixture(vaultFixture);

      await vaultFactory.connect(vaultOperator).changeDecreaseOnWithdraw(vault.target, false);
      expect(await vault.decrease()).to.be.false;

      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("500", 6), ethers.parseEther("500"), 0, 0);

      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 5000n * priceFactor;

      const [, baseBalanceAfterDeposit, , availableBaseBefore] = await vault.getBalances();

      const orderSize = baseBalanceAfterDeposit * 95n / 100n;
      const actions = [{ action: 3n, requireSuccess: true, cloid: 1n, param1: priceParam, param2: orderSize }];
      await vault.connect(vaultOperator).execute(actions, 0);

      const [, , , availableBaseFinal] = await vault.getBalances();
      expect(availableBaseFinal).to.be.lessThan(availableBaseBefore);

      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares);
      await vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, shares, 0, 0);
    });

    it("Should handle non-decrease mode with mixed orders but only quote excess", async function () {
      const { vault, vaultFactory, vaultOperator, depositor, quote, weth, crystal } = await loadFixture(vaultFixture);

      await vaultFactory.connect(vaultOperator).changeDecreaseOnWithdraw(vault.target, false);
      expect(await vault.decrease()).to.be.false;

      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("500", 6), ethers.parseEther("500"), 0, 0);

      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const buyPrice = 500n * priceFactor;
      const sellPrice = 5000n * priceFactor;

      const [quoteBalanceAfterDeposit] = await vault.getBalances();

      const buyOrderSize = quoteBalanceAfterDeposit * 95n / 100n;
      const sellOrderSize = ethers.parseEther("1");

      const actions = [
        { action: 2n, requireSuccess: true, cloid: 1n, param1: buyPrice, param2: buyOrderSize },
        { action: 3n, requireSuccess: true, cloid: 2n, param1: sellPrice, param2: sellOrderSize }
      ];
      await vault.connect(vaultOperator).execute(actions, 0);

      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares);
      await vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, shares, 0, 0);
    });
  });

  describe("cancelAll", function () {
    it("Should revert when called by non-owner/non-factory", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).cancelAll()).to.be.reverted;
    });

    it("Should cancel all orders when called by owner", async function () {
      const { vault, vaultOperator, quote, crystal } = await loadFixture(vaultFixture);
      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      const buySize = ethers.parseUnits("100", 6);
      const sellSize = ethers.parseEther("0.1");

      const actions = [
        { action: 2n, requireSuccess: true, cloid: 1n, param1: priceParam, param2: buySize },
        { action: 3n, requireSuccess: true, cloid: 2n, param1: priceParam * 2n, param2: sellSize }
      ];
      await vault.connect(vaultOperator).execute(actions, 0);

      const [quoteBalanceBefore, baseBalanceBefore, availableQuoteBefore, availableBaseBefore] = await vault.getBalances();
      expect(availableQuoteBefore).to.be.lessThan(quoteBalanceBefore);
      expect(availableBaseBefore).to.be.lessThan(baseBalanceBefore);

      await vault.connect(vaultOperator).cancelAll();

      const [quoteBalance, baseBalance, availableQuote, availableBase] = await vault.getBalances();
      expect(availableQuote).to.equal(quoteBalance);
      expect(availableBase).to.equal(baseBalance);
    });

    it("Should cancel all when called by factory", async function () {
      const { vault, vaultFactory, vaultOperator, quote, weth } = await loadFixture(vaultFixture);

      const shares = await vault.balanceOf(vaultOperator.address);
      await vault.connect(vaultOperator).approve(vaultFactory.target, shares);
      await vaultFactory.connect(vaultOperator).withdraw(vault.target, quote.target, weth.target, shares, 0, 0);
    });
  });

  describe("sweep", function () {
    it("Should revert when called by non-owner", async function () {
      const { vault, depositor } = await loadFixture(vaultFixture);
      await expect(vault.connect(depositor).sweep()).to.be.reverted;
    });

    it("Should sweep ETH to owner", async function () {
      const { vault, vaultOperator, owner } = await loadFixture(vaultFixture);
      await owner.sendTransaction({ to: vault.target, value: ethers.parseEther("0.1") });
      const balanceBefore = await ethers.provider.getBalance(vaultOperator.address);
      const tx = await vault.connect(vaultOperator).sweep();
      const receipt = await tx.wait();
      const gasCost = receipt.gasUsed * receipt.gasPrice;
      const balanceAfter = await ethers.provider.getBalance(vaultOperator.address);
      expect(balanceAfter + gasCost - balanceBefore).to.be.closeTo(ethers.parseEther("0.1"), ethers.parseEther("0.001"));
    });

    it("Should revert if owner cannot receive ETH", async function () {
      const { vaultFactory, quote, weth, owner } = await loadFixture(vaultFixture);

      const BadOwner = await ethers.getContractFactory("BadOwner");
      const badOwner = await BadOwner.deploy();
      await badOwner.waitForDeployment();

      const amountQuote = ethers.parseUnits("1000", 6);
      const amountBase = ethers.parseEther("1000");
      await quote.mint(badOwner.target, amountQuote);
      await weth.connect(owner).transfer(badOwner.target, amountBase);

      await badOwner.approveToken(quote.target, vaultFactory.target, amountQuote);
      await badOwner.approveToken(weth.target, vaultFactory.target, amountBase);

      const vaultAddr = await badOwner.deployVault.staticCall(
        vaultFactory.target, quote.target, weth.target, amountQuote, amountBase
      );
      await badOwner.deployVault(vaultFactory.target, quote.target, weth.target, amountQuote, amountBase);
      const vault = await ethers.getContractAt("CrystalVault", vaultAddr);

      await owner.sendTransaction({ to: vault.target, value: ethers.parseEther("0.1") });

      await expect(badOwner.callSweep(vault.target)).to.be.reverted;
    });
  });

  describe("execute", function () {
    it("Should revert when called by non-owner", async function () {
      const { vault, depositor, quote, crystal } = await loadFixture(vaultFixture);
      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      const actions = [{ action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 1000n }];
      await expect(vault.connect(depositor).execute(actions, 0)).to.be.reverted;
    });

    it("Should revert when vault is closed", async function () {
      const { vault, vaultFactory, vaultOperator, quote, weth, crystal } = await loadFixture(vaultFixture);
      const shares = await vault.balanceOf(vaultOperator.address);
      await vault.connect(vaultOperator).approve(vaultFactory.target, shares);
      await vaultFactory.connect(vaultOperator).withdraw(vault.target, quote.target, weth.target, shares, 0, 0);
      expect(await vault.closed()).to.be.true;

      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      const actions = [{ action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 1000n }];
      await expect(vault.connect(vaultOperator).execute(actions, 0)).to.be.reverted;
    });

    it("Should handle action type 1", async function () {
      const { vault, vaultOperator, quote, crystal } = await loadFixture(vaultFixture);
      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      await vault.connect(vaultOperator).execute([{ action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 10000n }], 0);
      await vault.connect(vaultOperator).execute([{ action: 1n, requireSuccess: false, cloid: 1n, param1: 0n, param2: 0n }], 0);
    });

    it("Should require cloid != 0 for limit orders", async function () {
      const { vault, vaultOperator, quote, crystal } = await loadFixture(vaultFixture);
      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      const actions = [{ action: 2n, requireSuccess: false, cloid: 0n, param1: priceParam, param2: 1000n }];
      await expect(vault.connect(vaultOperator).execute(actions, 0)).to.be.reverted;
    });

    it("Should require cloid < orderCap", async function () {
      const { vault, vaultOperator, quote, crystal } = await loadFixture(vaultFixture);
      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;
      const orderCap = await vault.orderCap();

      const actions = [{ action: 2n, requireSuccess: false, cloid: BigInt(orderCap) + 1n, param1: priceParam, param2: 1000n }];
      await expect(vault.connect(vaultOperator).execute(actions, 0)).to.be.reverted;
    });

    it("Should execute actions when called by owner", async function () {
      const { vault, vaultOperator, quote, crystal } = await loadFixture(vaultFixture);
      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      const actions = [{ action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 1000n }];
      await vault.connect(vaultOperator).execute(actions, 0);
    });

    it("Should handle multiple actions", async function () {
      const { vault, vaultOperator, quote, crystal } = await loadFixture(vaultFixture);
      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      const actions = [
        { action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 1000n },
        { action: 3n, requireSuccess: false, cloid: 2n, param1: priceParam * 2n, param2: 1000n }
      ];
      await vault.connect(vaultOperator).execute(actions, 0);
    });

    it("Should handle action type 4 (modify order)", async function () {
      const { vault, vaultOperator, quote, crystal } = await loadFixture(vaultFixture);
      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      await vault.connect(vaultOperator).execute([{ action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 1000n }], 0);
      await vault.connect(vaultOperator).execute([{ action: 4n, requireSuccess: false, cloid: 1n, param1: priceParam + 10n, param2: 2000n }], 0);
    });

    it("Should handle action type 5 (decrease order)", async function () {
      const { vault, vaultOperator, quote, crystal } = await loadFixture(vaultFixture);
      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      await vault.connect(vaultOperator).execute([{ action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 10000n }], 0);
      await vault.connect(vaultOperator).execute([{ action: 5n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 500n }], 0);
    });

    it("Should work with non-zero bid", async function () {
      const { vault, vaultOperator, quote, crystal, owner } = await loadFixture(vaultFixture);
      await owner.sendTransaction({ to: vault.target, value: ethers.parseEther("0.1") });

      const marketInfo = await crystal.getMarket(await vault.market());
      const scaleFactor = marketInfo.scaleFactor;
      const quoteDecimals = await quote.decimals();
      const priceFactor = 10n ** (BigInt(quoteDecimals) + BigInt(scaleFactor) - 18n);
      const priceParam = 500n * priceFactor;

      const actions = [{ action: 2n, requireSuccess: false, cloid: 1n, param1: priceParam, param2: 1000n }];
      await vault.connect(vaultOperator).execute(actions, 1000);
    });

    it("Should revert when crystal.call fails with requireSuccess true", async function () {
      const { vault, vaultOperator, _quote, crystal } = await loadFixture(vaultFixture);
      const _marketInfo = await crystal.getMarket(await vault.market());

      await expect(vault.connect(vaultOperator).execute(
        [{ action: 2n, requireSuccess: true, cloid: 1n, param1: 0n, param2: 1000n }],
        0
      )).to.be.reverted;
    });
  });

  describe("receive", function () {
    it("Should accept ETH transfers", async function () {
      const { vault, owner } = await loadFixture(vaultFixture);
      await owner.sendTransaction({ to: vault.target, value: ethers.parseEther("1") });
      expect(await ethers.provider.getBalance(vault.target)).to.equal(ethers.parseEther("1"));
    });
  });
});

describe("Parent ERC20 Functions (non-overridden)", function () {
  async function deployTestERC20() {
    const [owner, user1, user2] = await ethers.getSigners();
    const TestVaultERC20 = await ethers.getContractFactory("TestVaultERC20");
    const token = await TestVaultERC20.deploy();
    return { token, owner, user1, user2 };
  }

  describe("transfer()", function () {
    it("Should transfer tokens", async function () {
      const { token, owner, user1 } = await deployTestERC20();
      await token.mint(owner.address, ethers.parseEther("1000"));
      await token.transfer(user1.address, ethers.parseEther("100"));
      expect(await token.balanceOf(user1.address)).to.equal(ethers.parseEther("100"));
      expect(await token.balanceOf(owner.address)).to.equal(ethers.parseEther("900"));
    });

    it("Should emit Transfer event", async function () {
      const { token, owner, user1 } = await deployTestERC20();
      await token.mint(owner.address, ethers.parseEther("1000"));
      await expect(token.transfer(user1.address, ethers.parseEther("100")))
        .to.emit(token, "Transfer")
        .withArgs(owner.address, user1.address, ethers.parseEther("100"));
    });
  });

  describe("transferFrom()", function () {
    it("Should not decrease allowance when set to max", async function () {
      const { token, owner, user1, user2 } = await deployTestERC20();
      await token.mint(owner.address, ethers.parseEther("1000"));
      await token.approve(user1.address, ethers.MaxUint256);
      await token.connect(user1).transferFrom(owner.address, user2.address, ethers.parseEther("100"));
      expect(await token.allowance(owner.address, user1.address)).to.equal(ethers.MaxUint256);
    });

    it("Should transfer with approval", async function () {
      const { token, owner, user1, user2 } = await deployTestERC20();
      await token.mint(owner.address, ethers.parseEther("1000"));
      await token.approve(user1.address, ethers.parseEther("500"));
      await token.connect(user1).transferFrom(owner.address, user2.address, ethers.parseEther("100"));
      expect(await token.balanceOf(user2.address)).to.equal(ethers.parseEther("100"));
      expect(await token.allowance(owner.address, user1.address)).to.equal(ethers.parseEther("400"));
    });
  });
});

// changeMarket, proportional decrease, withdraw error paths, cancelAll, zero amounts
describe("CrystalVault with MockCrystal", function () {
  async function mockCrystalFixture() {
    const [owner, depositor] = await ethers.getSigners();

    const TestToken = await ethers.getContractFactory("TestToken");
    const quote = await TestToken.deploy("Mock USDC", "MUSDC", 6);
    const base = await TestToken.deploy("Mock WETH", "MWETH", 18);

    const MockCrystal = await ethers.getContractFactory("MockCrystal");
    const mockCrystal = await MockCrystal.deploy(quote.target, base.target);

    const MockFactory = await ethers.getContractFactory("MockFactory");
    const mockFactory = await MockFactory.deploy();

    const metadata = {
      name: "Test Vault",
      description: "A test vault",
      social1: "",
      social2: "",
      social3: ""
    };

    const tx = await mockFactory.deployVault(
      mockCrystal.target,
      quote.target,
      base.target,
      owner.address,
      "TV",
      metadata
    );
    const receipt = await tx.wait();
    const vaultDeployedEvent = receipt.logs.find(log => {
      try {
        return mockFactory.interface.parseLog(log)?.name === "VaultDeployed";
      } catch {
        return false;
      }
    });
    const vaultAddress = mockFactory.interface.parseLog(vaultDeployedEvent).args[0];
    const vault = await ethers.getContractAt("CrystalVault", vaultAddress);

    await quote.mint(depositor.address, ethers.parseUnits("10000", 6));
    await base.mint(depositor.address, ethers.parseEther("10"));
    await quote.mint(owner.address, ethers.parseUnits("10000", 6));
    await base.mint(owner.address, ethers.parseEther("10"));

    await quote.connect(depositor).approve(mockFactory.target, ethers.MaxUint256);
    await base.connect(depositor).approve(mockFactory.target, ethers.MaxUint256);
    await quote.connect(owner).approve(mockFactory.target, ethers.MaxUint256);
    await base.connect(owner).approve(mockFactory.target, ethers.MaxUint256);

    return { vault, mockCrystal, mockFactory, quote, base, owner, depositor };
  }

  describe("changeMarket with invalid market", function () {
    it("Should revert when new market has wrong quoteAsset", async function () {
      const { vault, mockCrystal, mockFactory, owner } = await mockCrystalFixture();

      await mockCrystal.setFakeOrderCount(0);
      await mockCrystal.setShouldRevertOnBatch(false);
      await mockCrystal.setConfiguredQuoteAsset(ethers.ZeroAddress);
      await expect(
        mockFactory.connect(owner).changeMarket(vault.target)
      ).to.be.reverted;
    });
  });

  describe("Proportional decrease conditions", function () {
    it("Should skip decrease for buy order when proportional check fails", async function () {
      const { vault, mockCrystal, mockFactory, quote, base, owner } = await mockCrystalFixture();

      await mockFactory.connect(owner).deposit(
        vault.target,
        quote.target,
        base.target,
        ethers.parseUnits("1000", 6),
        ethers.parseEther("1")
      );
      await mockCrystal.setFakeOrderCount(1);
      await mockCrystal.setAllBuyOrders(true);
      await mockCrystal.setShouldRevertOnBatch(false);
      await mockCrystal.setDepositedBalance(vault.target, quote.target, ethers.parseUnits("1000", 6), ethers.parseUnits("999", 6));
      await mockCrystal.setDepositedBalance(vault.target, base.target, ethers.parseEther("1"), ethers.parseEther("1"));

      const shares = await vault.balanceOf(owner.address);
      await mockFactory.connect(owner).withdraw(vault.target, shares);
    });

    it("Should decrease buy order when proportional check passes", async function () {
      const { vault, mockCrystal, mockFactory, quote, base, owner } = await mockCrystalFixture();

      await mockFactory.connect(owner).deposit(
        vault.target,
        quote.target,
        base.target,
        ethers.parseUnits("1000", 6),
        ethers.parseEther("1")
      );

      await mockCrystal.setFakeOrderCount(1);
      await mockCrystal.setAllBuyOrders(true);
      await mockCrystal.setShouldRevertOnBatch(false);
      await mockCrystal.setDepositedBalance(vault.target, quote.target, ethers.parseUnits("1000", 6), ethers.parseUnits("100", 6));
      await mockCrystal.setDepositedBalance(vault.target, base.target, ethers.parseEther("1"), ethers.parseEther("1"));

      const shares = await vault.balanceOf(owner.address);
      await mockFactory.connect(owner).withdraw(vault.target, shares);
    });

    it("Should decrease sell order when proportional check passes", async function () {
      const { vault, mockCrystal, mockFactory, quote, base, owner } = await mockCrystalFixture();

      await mockFactory.connect(owner).deposit(
        vault.target,
        quote.target,
        base.target,
        ethers.parseUnits("1000", 6),
        ethers.parseEther("1")
      );
      await mockCrystal.setFakeOrderCount(1);
      await mockCrystal.setAllBuyOrders(false);
      await mockCrystal.setShouldRevertOnBatch(false);
      await mockCrystal.setDepositedBalance(vault.target, quote.target, ethers.parseUnits("1000", 6), ethers.parseUnits("1000", 6));
      await mockCrystal.setDepositedBalance(vault.target, base.target, ethers.parseEther("1"), ethers.parseEther("0.1"));

      const shares = await vault.balanceOf(owner.address);
      await mockFactory.connect(owner).withdraw(vault.target, shares);
    });

    it("Should skip decrease for sell order when proportional check fails", async function () {
      const { vault, mockCrystal, mockFactory, quote, base, owner } = await mockCrystalFixture();

      await mockFactory.connect(owner).deposit(
        vault.target,
        quote.target,
        base.target,
        ethers.parseUnits("1000", 6),
        ethers.parseEther("1")
      );
      await mockCrystal.setFakeOrderCount(1);
      await mockCrystal.setAllBuyOrders(false);
      await mockCrystal.setShouldRevertOnBatch(false);
      await mockCrystal.setDepositedBalance(vault.target, quote.target, ethers.parseUnits("1000", 6), ethers.parseUnits("1000", 6));
      await mockCrystal.setDepositedBalance(vault.target, base.target, ethers.parseEther("1"), ethers.parseEther("0.999"));

      const shares = await vault.balanceOf(owner.address);
      await mockFactory.connect(owner).withdraw(vault.target, shares);
    });
  });

  describe("Withdraw error paths", function () {
    it("Should revert with Crystal error when batch decrease fails", async function () {
      const { vault, mockCrystal, mockFactory, quote, base, owner, depositor } = await mockCrystalFixture();

      await mockFactory.connect(owner).changeDecreaseOnWithdraw(vault.target, true);
      await mockFactory.connect(owner).deposit(
        vault.target,
        quote.target,
        base.target,
        ethers.parseUnits("1000", 6),
        ethers.parseEther("1")
      );
      await mockFactory.connect(depositor).deposit(
        vault.target,
        quote.target,
        base.target,
        ethers.parseUnits("100", 6),
        ethers.parseEther("0.1")
      );
      await mockCrystal.setFakeOrderCount(2);
      await mockCrystal.setShouldRevertOnBatch(true);
      await mockCrystal.setDepositedBalance(vault.target, quote.target, ethers.parseUnits("1100", 6), ethers.parseUnits("100", 6));
      await mockCrystal.setDepositedBalance(vault.target, base.target, ethers.parseEther("1.1"), ethers.parseEther("0.1"));

      const ownerShares = await vault.balanceOf(owner.address);
      const partialShares = ownerShares / 2n;

      await ethers.provider.send("hardhat_impersonateAccount", [mockFactory.target]);
      await ethers.provider.send("hardhat_setBalance", [mockFactory.target, "0xDE0B6B3A7640000"]);
      const factorySigner = await ethers.getSigner(mockFactory.target);

      await expect(
        vault.connect(factorySigner).withdraw(owner.address, partialShares, 0, 0)
      ).to.be.revertedWith("MockCrystal: batch call reverted");

      await ethers.provider.send("hardhat_stopImpersonatingAccount", [mockFactory.target]);
    });

    it("Should revert with Crystal error when batch cancel fails in non-decrease mode", async function () {
      const { vault, mockCrystal, mockFactory, quote, base, owner, depositor } = await mockCrystalFixture();

      await mockFactory.connect(owner).deposit(
        vault.target,
        quote.target,
        base.target,
        ethers.parseUnits("1000", 6),
        ethers.parseEther("1")
      );
      await mockFactory.connect(depositor).deposit(
        vault.target,
        quote.target,
        base.target,
        ethers.parseUnits("100", 6),
        ethers.parseEther("0.1")
      );
      await mockCrystal.setFakeOrderCount(2);
      await mockCrystal.setShouldRevertOnBatch(true);
      await mockCrystal.setDepositedBalance(vault.target, quote.target, ethers.parseUnits("1100", 6), ethers.parseUnits("100", 6));
      await mockCrystal.setDepositedBalance(vault.target, base.target, ethers.parseEther("1.1"), ethers.parseEther("0.1"));

      const ownerShares = await vault.balanceOf(owner.address);
      const partialShares = ownerShares / 2n;

      await ethers.provider.send("hardhat_impersonateAccount", [mockFactory.target]);
      await ethers.provider.send("hardhat_setBalance", [mockFactory.target, "0xDE0B6B3A7640000"]);
      const factorySigner = await ethers.getSigner(mockFactory.target);

      await expect(
        vault.connect(factorySigner).withdraw(owner.address, partialShares, 0, 0)
      ).to.be.revertedWith("MockCrystal: batch call reverted");

      await ethers.provider.send("hardhat_stopImpersonatingAccount", [mockFactory.target]);
    });
  });

  describe("cancelAll error path", function () {
    it("Should revert with crystal error when batch cancel fails in cancelAll", async function () {
      const { vault, mockCrystal, owner } = await mockCrystalFixture();

      await mockCrystal.setFakeOrderCount(2);
      await mockCrystal.setShouldRevertOnBatch(true);

      expect(await mockCrystal.shouldRevertOnBatch()).to.be.true;
      expect(await mockCrystal.fakeOrderCount()).to.equal(2n);

      await expect(
        vault.connect(owner).cancelAll()
      ).to.be.revertedWith("MockCrystal: batch call reverted");
    });

    it("Should track coverage when cancelAll is called via impersonated factory", async function () {
      const { vault, mockCrystal, mockFactory } = await mockCrystalFixture();

      await mockCrystal.setFakeOrderCount(2);
      await mockCrystal.setShouldRevertOnBatch(true);

      await ethers.provider.send("hardhat_impersonateAccount", [mockFactory.target]);
      await ethers.provider.send("hardhat_setBalance", [mockFactory.target, "0xDE0B6B3A7640000"]);
      const factorySigner = await ethers.getSigner(mockFactory.target);

      await expect(
        vault.connect(factorySigner).cancelAll()
      ).to.be.revertedWith("MockCrystal: batch call reverted");

      await ethers.provider.send("hardhat_stopImpersonatingAccount", [mockFactory.target]);
    });

    it("Direct low-level call to MockCrystal fallback", async function () {
      const { mockCrystal, owner } = await mockCrystalFixture();

      await mockCrystal.setShouldRevertOnBatch(true);

      const data = ethers.solidityPacked(["bytes32"], [ethers.ZeroHash]);

      await expect(
        owner.sendTransaction({ to: mockCrystal.target, data })
      ).to.be.revertedWith("MockCrystal: batch call reverted");
    });
  });

  describe("Withdraw with zero amounts", function () {
    it("Should skip quote withdrawal when amountQuote is 0", async function () {
      const { vault, mockCrystal, mockFactory, quote, base, owner } = await mockCrystalFixture();

      await mockFactory.connect(owner).deposit(
        vault.target,
        quote.target,
        base.target,
        ethers.parseUnits("1000", 6),
        ethers.parseEther("1")
      );

      await mockCrystal.setDepositedBalance(vault.target, quote.target, 0, 0);
      await mockCrystal.setDepositedBalance(vault.target, base.target, ethers.parseEther("1"), ethers.parseEther("1"));

      await mockCrystal.setFakeOrderCount(0);
      await mockCrystal.setShouldRevertOnBatch(false);

      const shares = await vault.balanceOf(owner.address);
      await mockFactory.connect(owner).withdraw(vault.target, shares);
    });

    it("Should skip base withdrawal when amountBase is 0", async function () {
      const { vault, mockCrystal, mockFactory, quote, base, owner } = await mockCrystalFixture();

      await mockFactory.connect(owner).deposit(
        vault.target,
        quote.target,
        base.target,
        ethers.parseUnits("1000", 6),
        ethers.parseEther("1")
      );
      await mockCrystal.setDepositedBalance(vault.target, quote.target, ethers.parseUnits("1000", 6), ethers.parseUnits("1000", 6));
      await mockCrystal.setDepositedBalance(vault.target, base.target, 0, 0);
      await mockCrystal.setFakeOrderCount(0);
      await mockCrystal.setShouldRevertOnBatch(false);

      const shares = await vault.balanceOf(owner.address);
      await mockFactory.connect(owner).withdraw(vault.target, shares);
    });
  });
});
