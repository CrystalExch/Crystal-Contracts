const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { deployFixture, advanceTime, TIME, ETH_ADDRESS } = require("./helpers");

describe("Crystal reentrancy guard", function () {
  it("blocks reentrancy on withdraw", async function () {
    const { crystal } = await loadFixture(deployFixture);

    const CrystalReentrancyAttacker = await ethers.getContractFactory("CrystalReentrancyAttacker");
    const attacker = await CrystalReentrancyAttacker.deploy();
    await attacker.setup(crystal.target, ETH_ADDRESS);

    const depositAmount = ethers.parseEther("1");
    await attacker.depositCrystal(depositAmount, { value: depositAmount });

    await attacker.attackWithdraw(ethers.parseEther("0.6"), 1, ethers.parseEther("0.2"));

    expect(await attacker.attacked()).to.be.true;
    expect(await attacker.reenterSucceeded()).to.be.false;
  });

  it("blocks reentrancy on routerWithdraw", async function () {
    const { crystal } = await loadFixture(deployFixture);

    const CrystalReentrancyAttacker = await ethers.getContractFactory("CrystalReentrancyAttacker");
    const attacker = await CrystalReentrancyAttacker.deploy();
    await attacker.setup(crystal.target, ETH_ADDRESS);

    const depositAmount = ethers.parseEther("1");
    await attacker.routerDepositCrystal(depositAmount, { value: depositAmount });

    await attacker.attackRouterWithdraw(ethers.parseEther("0.6"), 2, ethers.parseEther("0.2"));

    expect(await attacker.attacked()).to.be.true;
    expect(await attacker.reenterSucceeded()).to.be.false;
  });

  it("blocks reentrancy across all nonReentrant entrypoints", async function () {
    const { crystal } = await loadFixture(deployFixture);

    const CrystalReentrancyAttacker = await ethers.getContractFactory("CrystalReentrancyAttacker");
    const attacker = await CrystalReentrancyAttacker.deploy();
    await attacker.setup(crystal.target, ETH_ADDRESS);

    const depositAmount = ethers.parseEther("1");
    await attacker.depositCrystal(depositAmount, { value: depositAmount });

    const zero = ethers.ZeroAddress;
    const calls = [
      "0xdeadbeef",
      crystal.interface.encodeFunctionData("addLiquidity", [zero, zero, 0, 0, 0, 0]),
      crystal.interface.encodeFunctionData("removeLiquidity", [zero, zero, 0, 0, 0]),
      crystal.interface.encodeFunctionData("removeLiquidityETH", [zero, zero, 0, 0, 0]),
      crystal.interface.encodeFunctionData("marketOrder", [zero, true, true, 0, 0, 0, 0, zero, zero]),
      crystal.interface.encodeFunctionData("limitOrder", [zero, true, 0, 0, 0, zero]),
      crystal.interface.encodeFunctionData("cancelOrder", [zero, 0, 0, 0, zero]),
      crystal.interface.encodeFunctionData(
        "replaceOrder(address,uint256,uint256,uint256,uint256,uint256,address,address)",
        [zero, 0, 0, 0, 0, 0, zero, zero]
      ),
      crystal.interface.encodeFunctionData("batchOrders", [zero, [], 0, 0, zero, zero]),
      crystal.interface.encodeFunctionData("deposit", [zero, 0]),
      crystal.interface.encodeFunctionData("clearCloidSlots", [0, []]),
      crystal.interface.encodeFunctionData("writeCloidSlots", [0, []]),
      crystal.interface.encodeFunctionData("writeSlots", [zero, [], []]),
      crystal.interface.encodeFunctionData("deploy", [false, zero, zero, 0, 0, 0, 0, 0, 0, 0]),
      crystal.interface.encodeFunctionData("routerDeposit", [zero, 0]),
      crystal.interface.encodeFunctionData("swapExactETHForTokens", [0, [], zero, 0, zero]),
      crystal.interface.encodeFunctionData("swapExactTokensForETH", [0, 0, [], zero, 0, zero]),
      crystal.interface.encodeFunctionData("swapExactTokensForTokens", [0, 0, [], zero, 0, zero]),
      crystal.interface.encodeFunctionData("swapETHForExactTokens", [0, [], zero, 0, zero]),
      crystal.interface.encodeFunctionData("swapTokensForExactETH", [0, 0, [], zero, 0, zero]),
      crystal.interface.encodeFunctionData("swapTokensForExactTokens", [0, 0, [], zero, 0, zero]),
      crystal.interface.encodeFunctionData("swap", [true, zero, zero, 0, 0, 0, 0, zero]),
      crystal.interface.encodeFunctionData("placeLimitOrder", [zero, zero, 0, 0, 0]),
      crystal.interface.encodeFunctionData("cancelLimitOrder", [zero, zero, 0, 0, 0]),
      crystal.interface.encodeFunctionData(
        "replaceOrder(bool,bool,address,address,uint256,uint256,uint256,uint256,uint256,address)",
        [false, false, zero, zero, 0, 0, 0, 0, 0, zero]
      ),
      crystal.interface.encodeFunctionData("multiBatchOrders", [[], 0, zero]),
      crystal.interface.encodeFunctionData("createToken", ["", "", "", "", "", "", "", ""]),
      crystal.interface.encodeFunctionData("buy", [true, zero, 0, 0]),
      crystal.interface.encodeFunctionData("sell", [true, zero, 0, 0]),
      crystal.interface.encodeFunctionData("executeCloseInactiveMarket", [zero]),
    ];

    await attacker.setReenterCalldata(calls);
    await attacker.attackWithdraw(ethers.parseEther("0.1"), 0, 0);

    expect(await attacker.attacked()).to.be.true;
    expect(await attacker.reenterSucceeded()).to.be.false;
  });

  it("createToken with initial buy succeeds under guard", async function () {
    const { crystal, user1 } = await loadFixture(deployFixture);

    const tx = await crystal.connect(user1).createToken(
      "Reentry Token",
      "RET",
      "",
      "Token for reentrancy guard test",
      "",
      "",
      "",
      "",
      { value: ethers.parseEther("1") }
    );

    const receipt = await tx.wait();
    const event = receipt.logs
      .map((log) => {
        try {
          return crystal.interface.parseLog(log);
        } catch {
          return null;
        }
      })
      .find((e) => e && e.name === "TokenCreated");

    const token = await ethers.getContractAt("CrystalToken", event.args.token);
    expect(await token.balanceOf(user1.address)).to.be.greaterThan(0n);
  });

  it("executeCloseInactiveMarket for launchpad succeeds under guard", async function () {
    const { crystal, owner, user1 } = await loadFixture(deployFixture);

    const tx = await crystal.connect(user1).createToken(
      "Close Token",
      "CLOSE",
      "",
      "Token for close guard test",
      "",
      "",
      "",
      ""
    );

    const receipt = await tx.wait();
    const event = receipt.logs
      .map((log) => {
        try {
          return crystal.interface.parseLog(log);
        } catch {
          return null;
        }
      })
      .find((e) => e && e.name === "TokenCreated");

    const tokenAddress = event.args.token;

    await advanceTime(TIME.ONE_YEAR + 1);
    await crystal.connect(owner).queueCloseInactiveMarket(tokenAddress);
    await advanceTime(TIME.SEVEN_DAYS + 1);
    await crystal.connect(owner).executeCloseInactiveMarket(tokenAddress);

    const launchpadMarket = await crystal.launchpadTokenToMarket(tokenAddress);
    expect(launchpadMarket.virtualTokenReserve).to.equal(0n);
  });
});
