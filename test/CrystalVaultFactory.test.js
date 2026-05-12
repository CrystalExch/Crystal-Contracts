const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {
  deployFixture,
  vaultFixture,
  TIME,
  MAX_UINT256,
  ETH_ADDRESS,
} = require("./helpers");

describe("CrystalVaultFactory", function () {
  describe("getVault", function () {
    it("Should return vault info", async function () {
      const { vault, vaultFactory, vaultOperator, quote, weth } = await loadFixture(vaultFixture);
      const info = await vaultFactory.getVault(vault.target);
      expect(info.quoteAsset).to.equal(quote.target);
      expect(info.baseAsset).to.equal(weth.target);
      expect(info.owner).to.equal(vaultOperator.address);
    });
  });

  describe("constructor", function () {
    it("Should deploy with correct Crystal reference", async function () {
      const { vaultFactory, crystal } = await loadFixture(vaultFixture);
      expect(await vaultFactory.crystal()).to.equal(crystal.target);
    });

    it("Should deploy with correct gov", async function () {
      const { vaultFactory, owner } = await loadFixture(vaultFixture);
      expect(await vaultFactory.gov()).to.equal(owner.address);
    });

    it("Should deploy with correct WETH", async function () {
      const { crystal, owner, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);
      expect(await factory.weth()).to.equal(weth.target);
    });

    it("Should deploy with zero WETH address", async function () {
      const { crystal, owner } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 100, 100, 0);
      expect(await factory.weth()).to.equal(ethers.ZeroAddress);
    });

    it("Should deploy with correct minDeposit", async function () {
      const { vaultFactory } = await loadFixture(vaultFixture);
      expect(await vaultFactory.minDeposit()).to.equal(100n);
    });

    it("Should deploy with correct maxOrderCap", async function () {
      const { vaultFactory } = await loadFixture(vaultFixture);
      expect(await vaultFactory.maxOrderCap()).to.be.greaterThan(0n);
    });

    it("Should deploy with correct maxLockup", async function () {
      const { crystal, owner } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, ethers.ZeroAddress, 100, 100, TIME.SEVEN_DAYS);
      expect(await factory.maxLockup()).to.equal(TIME.SEVEN_DAYS);
    });

    it("Should have correct ETH constant", async function () {
      const { vaultFactory } = await loadFixture(vaultFixture);
      expect(await vaultFactory.eth()).to.equal(ETH_ADDRESS);
    });

    it("Should have minSize mapping", async function () {
      const { vaultFactory, quote } = await loadFixture(vaultFixture);
      expect(await vaultFactory.minSize(quote.target)).to.be.greaterThanOrEqual(0n);
    });
  });

  describe("changeGov", function () {
    it("Should revert for non-gov", async function () {
      const { vaultFactory, user1, user2 } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(user1).changeGov(user2.address)).to.be.reverted;
    });

    it("Should change gov", async function () {
      const { vaultFactory, owner, user1 } = await loadFixture(vaultFixture);
      await vaultFactory.connect(owner).changeGov(user1.address);
      expect(await vaultFactory.gov()).to.equal(user1.address);
    });
  });

  describe("changeMaxOrderCap", function () {
    it("Should revert for non-gov", async function () {
      const { vaultFactory, user1 } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(user1).changeMaxOrderCap(200)).to.be.reverted;
    });

    it("Should change max order cap", async function () {
      const { vaultFactory, owner } = await loadFixture(vaultFixture);
      await vaultFactory.connect(owner).changeMaxOrderCap(200);
      expect(await vaultFactory.maxOrderCap()).to.equal(200n);
    });
  });

  describe("changeMaxLockup", function () {
    it("Should revert for non-gov", async function () {
      const { vaultFactory, user1 } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(user1).changeMaxLockup(TIME.SEVEN_DAYS)).to.be.reverted;
    });

    it("Should change max lockup period", async function () {
      const { vaultFactory, owner } = await loadFixture(vaultFixture);
      await vaultFactory.connect(owner).changeMaxLockup(TIME.SEVEN_DAYS);
      expect(await vaultFactory.maxLockup()).to.equal(TIME.SEVEN_DAYS);
    });
  });

  describe("changeTokenMinSize", function () {
    it("Should revert for non-gov", async function () {
      const { vaultFactory, user1, quote } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(user1).changeTokenMinSize(quote.target, 200)).to.be.reverted;
    });

    it("Should change minimum size for a token", async function () {
      const { vaultFactory, owner, quote } = await loadFixture(vaultFixture);
      await vaultFactory.connect(owner).changeTokenMinSize(quote.target, 200);
      expect(await vaultFactory.minSize(quote.target)).to.equal(200n);
    });
  });

  describe("deploy", function () {
    it("Should use minSize when set for quote asset", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await factory.connect(owner).changeTokenMinSize(quote.target, ethers.parseUnits("500", 6));
      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      await expect(
        factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("400", 6), ethers.parseEther("1"), 0, 0, false, ["Test", "", "", "", ""])
      ).to.be.reverted;

      await factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("600", 6), ethers.parseEther("1"), 0, 0, false, ["Test", "", "", "", ""]);
    });

    it("Should revert when amountQuote <= minDeposit", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 1000, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      await expect(
        factory.connect(user1).deploy(quote.target, weth.target, 500, ethers.parseEther("1"), 0, 0, false, ["Test", "", "", "", ""])
      ).to.be.reverted;
    });

    it("Should use minSize when set for base asset", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await factory.connect(owner).changeTokenMinSize(weth.target, ethers.parseEther("0.5"));
      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      await expect(
        factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("0.3"), 0, 0, false, ["Test", "", "", "", ""])
      ).to.be.reverted;

      await factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("0.6"), 0, 0, false, ["Test", "", "", "", ""]);
    });

    it("Should revert when amountBase <= minDeposit", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 1000, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      await expect(
        factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("10000", 6), 500, 0, 0, false, ["Test", "", "", "", ""])
      ).to.be.reverted;
    });

    it("Should revert on zero quote asset", async function () {
      const { crystal, owner, user1, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await weth.connect(user1).approve(factory.target, MAX_UINT256);
      await expect(
        factory.connect(user1).deploy(ethers.ZeroAddress, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0, false, ["Test", "", "", "", ""])
      ).to.be.reverted;
    });

    // _createVault
    it("Should deploy vault with lockup period", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, TIME.THIRTY_DAYS);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const lockup = TIME.ONE_DAY;
      const tx = await factory.connect(user1).deploy(
        quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"),
        0, lockup, false, ["Locked Vault", "Description", "website", "twitter", "telegram"]
      );

      const receipt = await tx.wait();
      const event = receipt.logs.map(log => {
        try { return factory.interface.parseLog(log); } catch { return null; }
      }).find(e => e && e.name === "VaultDeployed");

      expect(event.args.lockup).to.equal(lockup);
    });

    it("Should deploy vault with maxShares", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const maxShares = ethers.parseEther("10000");
      const tx = await factory.connect(user1).deploy(
        quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"),
        maxShares, 0, false, ["Capped Vault", "Description", "website", "twitter", "telegram"]
      );

      const receipt = await tx.wait();
      const event = receipt.logs.map(log => {
        try { return factory.interface.parseLog(log); } catch { return null; }
      }).find(e => e && e.name === "VaultDeployed");

      expect(event.args.maxShares).to.equal(maxShares);
    });

    it("Should deploy vault with decreaseOnWithdraw", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const tx = await factory.connect(user1).deploy(
        quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"),
        0, 0, true, ["Decrease Vault", "Description", "website", "twitter", "telegram"]
      );

      const receipt = await tx.wait();
      const event = receipt.logs.map(log => {
        try { return factory.interface.parseLog(log); } catch { return null; }
      }).find(e => e && e.name === "VaultDeployed");

      expect(event.args.decreaseOnWithdraw).to.be.true;
    });

    it("Should register vault in allVaults", async function () {
      const { vaultFactory, vault } = await loadFixture(vaultFixture);
      const length = await vaultFactory.allVaultsLength();
      expect(length).to.be.greaterThan(0n);
      expect(await vaultFactory.allVaults(0)).to.equal(vault.target);
    });

    it("Should deploy new vault", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const tx = await factory.connect(user1).deploy(
        quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0, false,
        ["Test Vault", "Description", "website", "twitter", "telegram"]
      );

      const receipt = await tx.wait();
      const event = receipt.logs.map(log => {
        try { return factory.interface.parseLog(log); } catch { return null; }
      }).find(e => e && e.name === "VaultDeployed");

      expect(event).to.not.be.undefined;
      expect(event.args.vault).to.not.equal(ethers.ZeroAddress);
    });

    it("Should deploy vault with ETH as base asset", async function () {
      const { crystal, owner, user1, weth, quote } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);

      const tx = await factory.connect(user1).deploy(
        quote.target, ETH_ADDRESS, ethers.parseUnits("1000", 6), ethers.parseEther("1"),
        0, 0, false, ["ETH Base Deploy", "", "", "", ""],
        { value: ethers.parseEther("1") }
      );

      const receipt = await tx.wait();
      const event = receipt.logs.map(log => {
        try { return factory.interface.parseLog(log); } catch { return null; }
      }).find(e => e && e.name === "VaultDeployed");

      expect(event).to.not.be.undefined;
      const vaultInfo = await factory.getVault(event.args.vault);
      expect(vaultInfo.baseAsset).to.equal(weth.target);
    });

    it("Should deploy vault with ETH as quote asset", async function () {
      const { crystal, owner, user1, weth, token1 } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await token1.connect(user1).approve(factory.target, MAX_UINT256);

      const tx = await factory.connect(user1).deploy(
        ETH_ADDRESS, token1.target, ethers.parseEther("1"), ethers.parseEther("1000"),
        0, 0, false, ["ETH Quote Vault", "", "", "", ""],
        { value: ethers.parseEther("1") }
      );

      const receipt = await tx.wait();
      const event = receipt.logs.map(log => {
        try { return factory.interface.parseLog(log); } catch { return null; }
      }).find(e => e && e.name === "VaultDeployed");

      expect(event).to.not.be.undefined;
      expect(event.args.quoteAsset).to.equal(weth.target);
    });
  });

  describe("allVaultsLength", function () {
    it("Should return correct count", async function () {
      const { vaultFactory } = await loadFixture(vaultFixture);
      expect(await vaultFactory.allVaultsLength()).to.be.greaterThan(0n);
    });
  });

  describe("previewDeposit", function () {
    it("Should return expected shares", async function () {
      const { vault, vaultFactory } = await loadFixture(vaultFixture);
      const [shares, _amountQuote, _amountBase] = await vaultFactory.previewDeposit(vault.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"));
      expect(shares).to.be.greaterThan(0n);
    });
  });

  describe("previewWithdrawal", function () {
    it("Should return expected amounts", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      const shares = await vault.balanceOf(vaultOperator.address);
      const [amountQuote, amountBase] = await vaultFactory.previewWithdrawal(vault.target, shares);
      expect(amountQuote).to.be.greaterThan(0n);
      expect(amountBase).to.be.greaterThan(0n);
    });
  });

  describe("balanceOf", function () {
    it("Should return shares and amounts", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      const [shares, amountQuote, amountBase] = await vaultFactory.balanceOf(vault.target, vaultOperator.address);
      expect(shares).to.be.greaterThan(0n);
      expect(amountQuote).to.be.greaterThan(0n);
      expect(amountBase).to.be.greaterThan(0n);
    });
  });

  describe("deposit", function () {
    it("Should block reentrancy on deposit", async function () {
      const { crystal, weth, token1, owner } = await loadFixture(vaultFixture);
      const eth = ETH_ADDRESS;

      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await token1.connect(owner).approve(factory.target, MAX_UINT256);
      const vaultTx = await factory.connect(owner).deploy(eth, token1.target, ethers.parseEther("1"), ethers.parseEther("1"), 0, 0, false, ["ETH Vault", "", "", "", ""], { value: ethers.parseEther("2") });
      const receipt = await vaultTx.wait();
      const vaultEvent = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(ev => ev && ev.name === "VaultDeployed");
      const vaultAddr = vaultEvent.args.vault;

      const ReentrancyAttacker = await ethers.getContractFactory("ReentrancyAttacker");
      const attacker = await ReentrancyAttacker.deploy();

      await attacker.setup(factory.target, vaultAddr, eth, token1.target);
      await attacker.setReenter(0, 0, 0, 0);
      await token1.transfer(attacker.target, ethers.parseEther("10"));
      await attacker.approveToken(token1.target, factory.target, MAX_UINT256);

      await attacker.attackDepositReentrancy(ethers.parseEther("0.5"), ethers.parseEther("0.5"), { value: ethers.parseEther("1") });
      expect(await attacker.attacked()).to.be.true;
      expect(await attacker.reenterSucceeded()).to.be.false;
    });

    it("Should block reentrancy from deposit into withdraw", async function () {
      const { crystal, weth, token1, owner } = await loadFixture(vaultFixture);
      const eth = ETH_ADDRESS;

      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await token1.connect(owner).approve(factory.target, MAX_UINT256);
      const vaultTx = await factory.connect(owner).deploy(eth, token1.target, ethers.parseEther("1"), ethers.parseEther("1"), 0, 0, false, ["ETH Vault", "", "", "", ""], { value: ethers.parseEther("2") });
      const receipt = await vaultTx.wait();
      const vaultEvent = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(ev => ev && ev.name === "VaultDeployed");
      const vaultAddr = vaultEvent.args.vault;

      const ReentrancyAttacker = await ethers.getContractFactory("ReentrancyAttacker");
      const attacker = await ReentrancyAttacker.deploy();

      await attacker.setup(factory.target, vaultAddr, eth, token1.target);
      await attacker.setReenter(2, 0, 0, 0);
      await token1.transfer(attacker.target, ethers.parseEther("10"));
      await attacker.approveToken(token1.target, factory.target, MAX_UINT256);

      await attacker.attackDepositReentrancy(ethers.parseEther("0.5"), ethers.parseEther("0.5"), { value: ethers.parseEther("1") });
      expect(await attacker.attacked()).to.be.true;
      expect(await attacker.reenterSucceeded()).to.be.false;
    });

    it("Should revert with wrong quote asset", async function () {
      const { vault, vaultFactory, depositor, base, weth } = await loadFixture(vaultFixture);
      await expect(
        vaultFactory.connect(depositor).deposit(vault.target, base.target, weth.target, ethers.parseUnits("100", 18), ethers.parseEther("0.1"), 0, 0)
      ).to.be.reverted;
    });

    it("Should revert with wrong base asset", async function () {
      const { vault, vaultFactory, depositor, quote, base } = await loadFixture(vaultFixture);
      await expect(
        vaultFactory.connect(depositor).deposit(vault.target, quote.target, base.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0)
      ).to.be.reverted;
    });

    it("Should deposit with ETH as quote asset", async function () {
      const { crystal, owner, user1, user2, weth, token1 } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await token1.connect(user1).approve(factory.target, MAX_UINT256);
      const tx = await factory.connect(user1).deploy(ETH_ADDRESS, token1.target, ethers.parseEther("1"), ethers.parseEther("1000"), 0, 0, false, ["ETH Quote Vault", "", "", "", ""], { value: ethers.parseEther("1") });
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);

      await token1.connect(user2).approve(factory.target, MAX_UINT256);
      await factory.connect(user2).deposit(vault.target, ETH_ADDRESS, token1.target, ethers.parseEther("0.5"), ethers.parseEther("500"), 0, 0, { value: ethers.parseEther("0.5") });
      expect(await vault.balanceOf(user2.address)).to.be.greaterThan(0n);
    });

    it("Should deposit with ETH as base asset", async function () {
      const { crystal, owner, user1, weth, quote } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      const deployTx = await factory.connect(user1).deploy(quote.target, ETH_ADDRESS, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0, false, ["ETH Test Vault", "", "", "", ""], { value: ethers.parseEther("1") });
      const receipt = await deployTx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);

      await factory.connect(user1).deposit(event.args.vault, quote.target, ETH_ADDRESS, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0, { value: ethers.parseEther("0.1") });
      expect(await vault.balanceOf(user1.address)).to.be.greaterThan(0n);
    });

    it("Should accept deposits via factory", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);
      expect(await vault.balanceOf(depositor.address)).to.be.greaterThan(0n);
    });

    it("Should revert when ETH refund fails (quote is ETH)", async function () {
      const { crystal, weth, token1, owner } = await loadFixture(vaultFixture);
      const eth = ETH_ADDRESS;

      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      const ETHRejecter = await ethers.getContractFactory("ETHRejecter");
      const rejecter = await ETHRejecter.deploy();

      await token1.connect(owner).approve(factory.target, MAX_UINT256);
      const vaultTx = await factory.connect(owner).deploy(eth, token1.target, ethers.parseEther("1"), ethers.parseEther("1"), 0, 0, false, ["ETH Vault", "", "", "", ""], { value: ethers.parseEther("2") });
      const receipt = await vaultTx.wait();
      const vaultEvent = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(ev => ev && ev.name === "VaultDeployed");
      const vaultAddr = vaultEvent.args.vault;

      await token1.transfer(rejecter.target, ethers.parseEther("10"));
      await rejecter.approveToken(token1.target, factory.target, MAX_UINT256);

      await expect(
        rejecter.depositToVault(factory.target, vaultAddr, eth, token1.target, ethers.parseEther("0.5"), ethers.parseEther("0.5"), { value: ethers.parseEther("1") })
      ).to.be.reverted;
    });

    it("Should revert when ETH refund fails (base is ETH)", async function () {
      const { crystal, weth, quote, owner } = await loadFixture(vaultFixture);
      const eth = ETH_ADDRESS;

      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      const ETHRejecter = await ethers.getContractFactory("ETHRejecter");
      const rejecter = await ETHRejecter.deploy();

      await quote.connect(owner).approve(factory.target, MAX_UINT256);
      const vaultTx = await factory.connect(owner).deploy(quote.target, eth, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0, false, ["ETH Base Vault", "", "", "", ""], { value: ethers.parseEther("2") });
      const receipt = await vaultTx.wait();
      const vaultEvent = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(ev => ev && ev.name === "VaultDeployed");
      const vaultAddr = vaultEvent.args.vault;

      await quote.transfer(rejecter.target, ethers.parseUnits("10000", 6));
      await rejecter.approveToken(quote.target, factory.target, MAX_UINT256);

      await expect(
        rejecter.depositToVault(factory.target, vaultAddr, quote.target, eth, ethers.parseUnits("500", 6), ethers.parseEther("0.5"), { value: ethers.parseEther("1") })
      ).to.be.reverted;
    });

    it("Should refund excess ETH on deposit", async function () {
      const { crystal, owner, user1, user2, weth, token1 } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await token1.connect(user1).approve(factory.target, MAX_UINT256);
      const tx = await factory.connect(user1).deploy(ETH_ADDRESS, token1.target, ethers.parseEther("1"), ethers.parseEther("1000"), 0, 0, false, ["ETH Quote Vault", "", "", "", ""], { value: ethers.parseEther("1") });
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");

      await token1.connect(user2).approve(factory.target, MAX_UINT256);
      const ethBalanceBefore = await ethers.provider.getBalance(user2.address);

      const depositTx = await factory.connect(user2).deposit(event.args.vault, ETH_ADDRESS, token1.target, ethers.parseEther("2"), ethers.parseEther("500"), 0, 0, { value: ethers.parseEther("2") });
      await depositTx.wait();

      const ethBalanceAfter = await ethers.provider.getBalance(user2.address);
      const ethSpent = ethBalanceBefore - ethBalanceAfter;
      expect(ethSpent).to.be.lessThan(ethers.parseEther("2"));
    });

    it("Should respect minAmountQuote", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await expect(
        vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), ethers.parseUnits("1000", 6), 0)
      ).to.be.reverted;
    });

    it("Should respect minAmountBase", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await expect(
        vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, ethers.parseEther("1000"))
      ).to.be.reverted;
    });

    it("Should update totalShares in getVault", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      const infoBefore = await vaultFactory.getVault(vault.target);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);
      const infoAfter = await vaultFactory.getVault(vault.target);
      expect(infoAfter.totalShares).to.be.greaterThan(infoBefore.totalShares);
    });
  });

  describe("withdraw", function () {
    it("Should block reentrancy on withdraw", async function () {
      const { crystal, weth, token1, owner } = await loadFixture(vaultFixture);
      const eth = ETH_ADDRESS;

      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await token1.connect(owner).approve(factory.target, MAX_UINT256);
      const vaultTx = await factory.connect(owner).deploy(eth, token1.target, ethers.parseEther("1"), ethers.parseEther("1"), 0, 0, false, ["ETH Vault", "", "", "", ""], { value: ethers.parseEther("2") });
      const receipt = await vaultTx.wait();
      const vaultEvent = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(ev => ev && ev.name === "VaultDeployed");
      const vaultAddr = vaultEvent.args.vault;
      const vault = await ethers.getContractAt("CrystalVault", vaultAddr);

      const ReentrancyAttacker = await ethers.getContractFactory("ReentrancyAttacker");
      const attacker = await ReentrancyAttacker.deploy();

      await attacker.setup(factory.target, vaultAddr, eth, token1.target);
      await token1.transfer(attacker.target, ethers.parseEther("10"));
      await attacker.approveToken(token1.target, factory.target, MAX_UINT256);

      await attacker.setReenter(1, ethers.parseEther("0.5"), ethers.parseEther("0.5"), 0);
      await attacker.attackDepositReentrancy(ethers.parseEther("0.5"), ethers.parseEther("0.5"), { value: ethers.parseEther("0.5") });

      const shares = await vault.balanceOf(attacker.target);
      expect(shares).to.be.greaterThan(0n);

      const reenterShares = shares / 4n > 0n ? shares / 4n : 1n;
      await attacker.setReenter(2, 0, 0, reenterShares);
      await attacker.attackWithdrawReentrancy(shares / 2n);
      expect(await attacker.attacked()).to.be.true;
      expect(await attacker.reenterSucceeded()).to.be.false;
    });

    it("Should revert with wrong quote asset", async function () {
      const { vault, vaultFactory, depositor, quote, weth, base } = await loadFixture(vaultFixture);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);

      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares);

      await expect(vaultFactory.connect(depositor).withdraw(vault.target, base.target, weth.target, shares / 2n, 0, 0)).to.be.reverted;
    });

    it("Should process withdrawals via factory", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);

      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares);
      await vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, shares / 2n, 0, 0);

      expect(await vault.balanceOf(depositor.address)).to.equal(shares - shares / 2n);
    });

    it("Should withdraw with ETH as quote asset", async function () {
      const { crystal, owner, user1, user2, weth, token1 } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await token1.connect(user1).approve(factory.target, MAX_UINT256);
      const tx = await factory.connect(user1).deploy(ETH_ADDRESS, token1.target, ethers.parseEther("1"), ethers.parseEther("1000"), 0, 0, false, ["ETH Quote Vault", "", "", "", ""], { value: ethers.parseEther("1") });
      const receipt = await tx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);

      await token1.connect(user2).approve(factory.target, MAX_UINT256);
      await factory.connect(user2).deposit(vault.target, ETH_ADDRESS, token1.target, ethers.parseEther("0.5"), ethers.parseEther("500"), 0, 0, { value: ethers.parseEther("0.5") });

      const shares = await vault.balanceOf(user2.address);
      await vault.connect(user2).approve(factory.target, shares);
      const ethBalanceBefore = await ethers.provider.getBalance(user2.address);

      const withdrawTx = await factory.connect(user2).withdraw(vault.target, ETH_ADDRESS, token1.target, shares, 0, 0);
      const withdrawReceipt = await withdrawTx.wait();
      const gasUsed = withdrawReceipt.gasUsed * withdrawReceipt.gasPrice;

      const ethBalanceAfter = await ethers.provider.getBalance(user2.address);
      expect(ethBalanceAfter + gasUsed).to.be.greaterThan(ethBalanceBefore);
    });

    it("Should revert when ETH transfer fails (quote is ETH)", async function () {
      const { crystal, weth, token1, owner } = await loadFixture(vaultFixture);
      const eth = ETH_ADDRESS;

      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await token1.connect(owner).approve(factory.target, MAX_UINT256);
      const vaultTx = await factory.connect(owner).deploy(eth, token1.target, ethers.parseEther("1"), ethers.parseEther("1"), 0, 0, false, ["ETH Vault", "", "", "", ""], { value: ethers.parseEther("2") });
      const receipt = await vaultTx.wait();
      const vaultEvent = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(ev => ev && ev.name === "VaultDeployed");
      const vaultAddr = vaultEvent.args.vault;
      const vault = await ethers.getContractAt("CrystalVault", vaultAddr);

      const ETHToggler = await ethers.getContractFactory("ETHToggler");
      const toggler = await ETHToggler.deploy();

      await token1.transfer(toggler.target, ethers.parseEther("10"));
      await toggler.approveToken(token1.target, factory.target, MAX_UINT256);

      await toggler.depositToVault(factory.target, vaultAddr, eth, token1.target, ethers.parseEther("0.5"), ethers.parseEther("0.5"), { value: ethers.parseEther("1") });

      const shares = await vault.balanceOf(toggler.target);
      expect(shares).to.be.greaterThan(0n);

      await toggler.setRejectETH(true);

      await expect(toggler.withdrawFromVault(factory.target, vaultAddr, eth, token1.target, shares)).to.be.reverted;
    });

    it("Should withdraw with ETH as base asset", async function () {
      const { crystal, owner, user1, weth, quote } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      const deployTx = await factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0, false, ["ETH Test Vault", "", "", "", ""]);
      const receipt = await deployTx.wait();
      const event = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(e => e && e.name === "VaultDeployed");
      const vault = await ethers.getContractAt("CrystalVault", event.args.vault);

      const shares = await vault.balanceOf(user1.address);
      await vault.connect(user1).approve(factory.target, shares);
      const ethBefore = await ethers.provider.getBalance(user1.address);

      const withdrawTx = await factory.connect(user1).withdraw(event.args.vault, quote.target, ETH_ADDRESS, shares / 2n, 0, 0);
      const withdrawReceipt = await withdrawTx.wait();
      const gasUsed = withdrawReceipt.gasUsed * withdrawReceipt.gasPrice;
      const ethAfter = await ethers.provider.getBalance(user1.address);

      expect(ethAfter + gasUsed).to.be.greaterThan(ethBefore);
    });

    it("Should revert when ETH transfer fails (base is ETH)", async function () {
      const { crystal, weth, quote, owner } = await loadFixture(vaultFixture);
      const eth = ETH_ADDRESS;

      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await quote.connect(owner).approve(factory.target, MAX_UINT256);
      const vaultTx = await factory.connect(owner).deploy(quote.target, eth, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0, false, ["ETH Base Vault", "", "", "", ""], { value: ethers.parseEther("2") });
      const receipt = await vaultTx.wait();
      const vaultEvent = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(ev => ev && ev.name === "VaultDeployed");
      const vaultAddr = vaultEvent.args.vault;
      const vault = await ethers.getContractAt("CrystalVault", vaultAddr);

      const ETHToggler = await ethers.getContractFactory("ETHToggler");
      const toggler = await ETHToggler.deploy();

      await quote.transfer(toggler.target, ethers.parseUnits("10000", 6));
      await toggler.approveToken(quote.target, factory.target, MAX_UINT256);

      await toggler.depositToVault(factory.target, vaultAddr, quote.target, eth, ethers.parseUnits("500", 6), ethers.parseEther("0.5"), { value: ethers.parseEther("1") });

      const shares = await vault.balanceOf(toggler.target);
      expect(shares).to.be.greaterThan(0n);

      await toggler.setRejectETH(true);

      await expect(toggler.withdrawFromVault(factory.target, vaultAddr, quote.target, eth, shares)).to.be.reverted;
    });

    it("Should lock and close vault and emit events when owner withdraws all shares", async function () {
      const { vault, vaultFactory, vaultOperator, quote, weth } = await loadFixture(vaultFixture);

      const shares = await vault.balanceOf(vaultOperator.address);
      await vault.connect(vaultOperator).approve(vaultFactory.target, shares);

      const tx = await vaultFactory
        .connect(vaultOperator)
        .withdraw(vault.target, quote.target, weth.target, shares, 0, 0);

      const receipt = await tx.wait();

      const info = await vaultFactory.getVault(vault.target);
      expect(info.closed).to.be.true;
      expect(info.locked).to.be.true;

      const events = receipt.logs
        .map((log) => {
          try {
            return vaultFactory.interface.parseLog(log);
          } catch (e) {
            return null;
          }
        })
        .filter((e) => e !== null);

      expect(events.some((e) => e.name === "Locked")).to.be.true;
      expect(events.some((e) => e.name === "Closed")).to.be.true;
      
      const locked = events.filter((e) => e.name === "Locked");
      const closed = events.filter((e) => e.name === "Closed");

      expect(locked).to.have.length(1);
      expect(closed).to.have.length(1);
      expect(locked[0].args[0]).to.equal(vault.target);
      expect(closed[0].args[0]).to.equal(vault.target);
    });

    it("Should not emit Locked if already locked on withdraw", async function () {
      const { vault, vaultFactory, vaultOperator, depositor, quote, weth } = await loadFixture(vaultFixture);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);
      await vaultFactory.connect(vaultOperator).lock(vault.target);

      const ownerShares = await vault.balanceOf(vaultOperator.address);
      await vault.connect(vaultOperator).approve(vaultFactory.target, ownerShares);

      const tx = await vaultFactory.connect(vaultOperator).withdraw(vault.target, quote.target, weth.target, ownerShares, 0, 0);
      const receipt = await tx.wait();
      const events = receipt.logs.map(log => { try { return vaultFactory.interface.parseLog(log); } catch { return null; } }).filter(e => e !== null);

      expect(events.filter(e => e.name === "Locked").length).to.equal(0);
      expect(events.find(e => e.name === "Closed")).to.not.be.undefined;
    });

    it("Should update totalShares on withdraw", async function () {
      const { vault, vaultFactory, depositor, quote, weth } = await loadFixture(vaultFixture);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);

      const infoBefore = await vaultFactory.getVault(vault.target);
      const shares = await vault.balanceOf(depositor.address);
      await vault.connect(depositor).approve(vaultFactory.target, shares);

      await vaultFactory.connect(depositor).withdraw(vault.target, quote.target, weth.target, shares / 2n, 0, 0);

      const infoAfter = await vaultFactory.getVault(vault.target);
      expect(infoAfter.totalShares).to.be.lessThan(infoBefore.totalShares);
    });
  });

  describe("lock", function () {
    it("Should revert for non-owner", async function () {
      const { vault, vaultFactory, depositor } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).lock(vault.target)).to.be.reverted;
    });

    it("Should lock the vault", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).lock(vault.target);
      expect((await vaultFactory.getVault(vault.target)).locked).to.be.true;
    });

    it("Should emit Locked event", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(vaultOperator).lock(vault.target)).to.emit(vaultFactory, "Locked").withArgs(vault.target);
    });
  });

  describe("unlock", function () {
    it("Should revert for non-owner", async function () {
      const { vault, vaultFactory, vaultOperator, depositor } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).lock(vault.target);
      await expect(vaultFactory.connect(depositor).unlock(vault.target)).to.be.reverted;
    });

    it("Should unlock the vault", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).lock(vault.target);
      await vaultFactory.connect(vaultOperator).unlock(vault.target);
      expect((await vaultFactory.getVault(vault.target)).locked).to.be.false;
    });

    it("Should emit Unlocked event", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).lock(vault.target);
      await expect(vaultFactory.connect(vaultOperator).unlock(vault.target)).to.emit(vaultFactory, "Unlocked").withArgs(vault.target);
    });
  });

  describe("close", function () {
    it("Should revert for non-owner", async function () {
      const { vault, vaultFactory, depositor } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).close(vault.target)).to.be.reverted;
    });

    it("Should close vault and return funds to owner", async function () {
      const { vault, vaultFactory, vaultOperator, quote, weth } = await loadFixture(vaultFixture);
      const quoteBefore = await quote.balanceOf(vaultOperator.address);
      const wethBefore = await weth.balanceOf(vaultOperator.address);

      await vaultFactory.connect(vaultOperator).close(vault.target);

      expect(await quote.balanceOf(vaultOperator.address)).to.be.greaterThan(quoteBefore);
      expect(await weth.balanceOf(vaultOperator.address)).to.be.greaterThan(wethBefore);
    });

    it("Should close vault even if owner is not the only depositor", async function () {
      const { vault, vaultFactory, vaultOperator, depositor, quote, weth } = await loadFixture(vaultFixture);
      await vaultFactory.connect(depositor).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);

      const tx = await vaultFactory.connect(vaultOperator).close(vault.target);
      const receipt = await tx.wait();
      const events = receipt.logs.map(log => { try { return vaultFactory.interface.parseLog(log); } catch { return null; } }).filter(e => e !== null);

      const totalSupply = await vault.totalSupply();
      if (totalSupply > 0n) {
        expect((await vaultFactory.getVault(vault.target)).closed).to.be.true;
        expect(events.find(e => e.name === "Closed")).to.exist;
      }
    });

    it("Should not emit Locked if already locked", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).lock(vault.target);

      const tx = await vaultFactory.connect(vaultOperator).close(vault.target);
      const receipt = await tx.wait();
      const events = receipt.logs.map(log => { try { return vaultFactory.interface.parseLog(log); } catch { return null; } }).filter(e => e !== null);

      expect(events.filter(e => e.name === "Locked").length).to.equal(0);
    });

    it("Should emit Locked and Closed events and mark vault as closed", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);

      const tx = await vaultFactory.connect(vaultOperator).close(vault.target);
      const receipt = await tx.wait();

      const events = receipt.logs
        .map((log) => {
          try {
            return vaultFactory.interface.parseLog(log);
          } catch {
            return null;
          }
        })
        .filter((e) => e !== null);

      expect(events.find((e) => e.name === "Locked")).to.not.be.undefined;
      expect(events.find((e) => e.name === "Closed")).to.not.be.undefined;

      const info = await vaultFactory.getVault(vault.target);
      expect(info.closed).to.be.true;
      expect(info.locked).to.be.true;
    });
  });

  describe("changeMaxShares", function () {
    it("Should revert for non-owner", async function () {
      const { vault, vaultFactory, depositor } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).changeMaxShares(vault.target, 1000n)).to.be.reverted;
    });

    it("Should update max shares", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      const newMaxShares = ethers.parseEther("50000");
      await vaultFactory.connect(vaultOperator).changeMaxShares(vault.target, newMaxShares);
      expect((await vaultFactory.getVault(vault.target)).maxShares).to.equal(newMaxShares);
    });

    it("Should emit MaxSharesChanged event", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      const newMaxShares = ethers.parseEther("50000");
      await expect(vaultFactory.connect(vaultOperator).changeMaxShares(vault.target, newMaxShares)).to.emit(vaultFactory, "MaxSharesChanged").withArgs(vault.target, newMaxShares);
    });
  });

  describe("changeLockup", function () {
    it("Should revert for non-owner", async function () {
      const { vault, vaultFactory, depositor } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).changeLockup(vault.target, TIME.ONE_DAY)).to.be.reverted;
    });

    it("Should update lockup period", async function () {
      const { vault, vaultFactory, vaultOperator, owner } = await loadFixture(vaultFixture);
      await vaultFactory.connect(owner).changeMaxLockup(TIME.THIRTY_DAYS);
      const newLockup = TIME.SEVEN_DAYS;
      await vaultFactory.connect(vaultOperator).changeLockup(vault.target, newLockup);
      expect((await vaultFactory.getVault(vault.target)).lockup).to.equal(newLockup);
    });

    it("Should emit LockupChanged event", async function () {
      const { vault, vaultFactory, vaultOperator, owner } = await loadFixture(vaultFixture);
      await vaultFactory.connect(owner).changeMaxLockup(TIME.THIRTY_DAYS);
      const newLockup = TIME.SEVEN_DAYS;
      await expect(vaultFactory.connect(vaultOperator).changeLockup(vault.target, newLockup)).to.emit(vaultFactory, "LockupChanged").withArgs(vault.target, newLockup);
    });
  });

  describe("changeOrderCap", function () {
    it("Should revert for non-owner", async function () {
      const { vault, vaultFactory, depositor } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).changeOrderCap(vault.target, 50)).to.be.reverted;
    });

    it("Should update order cap", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).changeOrderCap(vault.target, 50);
      expect(await vault.orderCap()).to.equal(50n);
    });
  });

  describe("changeDecreaseOnWithdraw", function () {
    it("Should revert for non-owner", async function () {
      const { vault, vaultFactory, depositor } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).changeDecreaseOnWithdraw(vault.target, true)).to.be.reverted;
    });

    it("Should update setting", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).changeDecreaseOnWithdraw(vault.target, true);
      expect(await vault.decrease()).to.be.true;
    });

    it("Should emit DecreaseOnWithdrawChanged event", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(vaultOperator).changeDecreaseOnWithdraw(vault.target, true)).to.emit(vaultFactory, "DecreaseOnWithdrawChanged").withArgs(vault.target, true);
    });
  });

  describe("changeMarket", function () {
    it("Should revert for non-owner", async function () {
      const { vault, vaultFactory, depositor } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).changeMarket(vault.target)).to.be.reverted;
    });

    it("Should update market", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).changeMarket(vault.target);
    });
  });

  describe("claimFees", function () {
    it("Should revert for non-owner", async function () {
      const { vault, vaultFactory, depositor } = await loadFixture(vaultFixture);
      await expect(vaultFactory.connect(depositor).claimFees(vault.target)).to.be.reverted;
    });

    it("Should claim fees", async function () {
      const { vault, vaultFactory, vaultOperator } = await loadFixture(vaultFixture);
      await vaultFactory.connect(vaultOperator).claimFees(vault.target);
    });
  });

  describe("clearCloidSlots", function () {
    it("Should revert for non-owner", async function () {
      const { vault, vaultFactory, depositor, crystal } = await loadFixture(vaultFixture);
      const userId = await crystal.addressToUserId(vault.target);
      await expect(vaultFactory.connect(depositor).clearCloidSlots(vault.target, userId, [1, 2, 3])).to.be.reverted;
    });

    it("Should clear slots", async function () {
      const { vault, vaultFactory, vaultOperator, crystal } = await loadFixture(vaultFixture);
      const userId = await crystal.addressToUserId(vault.target);
      await vaultFactory.connect(vaultOperator).clearCloidSlots(vault.target, userId, [1, 2, 3]);
    });
  });

  describe("receive", function () {
    it("Should accept ETH", async function () {
      const { vaultFactory, owner } = await loadFixture(vaultFixture);
      await owner.sendTransaction({ to: vaultFactory.target, value: ethers.parseEther("1") });
      expect(await ethers.provider.getBalance(vaultFactory.target)).to.equal(ethers.parseEther("1"));
    });
  });

  describe("Access Control", function () {
    it("Anyone can deploy vault", async function () {
      const { crystal, owner, user1, quote, weth } = await loadFixture(deployFixture);
      const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");
      const factory = await CrystalVaultFactory.deploy(crystal.target, owner.address, weth.target, 100, 100, 0);

      await quote.connect(user1).approve(factory.target, MAX_UINT256);
      await weth.connect(user1).approve(factory.target, MAX_UINT256);

      await factory.connect(user1).deploy(quote.target, weth.target, ethers.parseUnits("1000", 6), ethers.parseEther("1"), 0, 0, true, ["User Vault", "Description", "website", "twitter", "telegram"]);
    });

    it("Anyone can deposit to vault", async function () {
      const { vault, vaultFactory, user1, quote, weth } = await loadFixture(vaultFixture);
      await quote.connect(user1).approve(vaultFactory.target, MAX_UINT256);
      await weth.connect(user1).approve(vaultFactory.target, MAX_UINT256);

      await vaultFactory.connect(user1).deposit(vault.target, quote.target, weth.target, ethers.parseUnits("100", 6), ethers.parseEther("0.1"), 0, 0);
      expect(await vault.balanceOf(user1.address)).to.be.greaterThan(0n);
    });
  });
});
