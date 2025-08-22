const { expect } = require("chai");
const { ethers } = require("hardhat");

/* function getMarketParams(quoteDecimals, baseDecimals, price, maxPrice) {
  let priceFactor = price.split('.')[1].replace(/0+$/, '').length
  let scaleFactor = BigInt(priceFactor) + baseDecimals - quoteDecimals
  let tickSize = 1
  if (scaleFactor < 0) {
    tickSize = 10n ** (-scaleFactor)
    scaleFactor = 0n
  }
  maxPrice = (10 ** priceFactor) * maxPrice * Number(tickSize)
  let maxSize = BigInt(170141183460469231731687303715884105727) / ((10n ** quoteDecimals) * (10n ** scaleFactor))
  console.log(priceFactor, scaleFactor, maxPrice, tickSize, maxSize.toLocaleString(), 10**priceFactor)
}
getMarketParams(6n, 18n, '0.000000733', 1000000) */

describe("CrystalTests", function () {
  let crystal, market, market1;
  let quote, base;
  let owner, maker, taker, depositer;
  let vaultfactory, vault, vaultoperator;
  let tokenAddr;

  beforeEach(async () => {
    [owner, maker, taker, vaultoperator, depositer] = await ethers.getSigners();

    const WETH = await ethers.getContractFactory("WrappedMonad");
    const Token = await ethers.getContractFactory("TestToken");
    quote = await Token.deploy("Quote", "Q", 6);
    base = await WETH.deploy();
    await quote.mint(maker.address, ethers.parseEther("1000000000000000000000000000000"));
    await base.connect(maker).deposit({value: ethers.parseEther("1000000000000000000000000000000")});
    await quote.mint(taker.address, ethers.parseEther("1000000000000000000000000000000"));
    await base.connect(taker).deposit({value: ethers.parseEther("1000000000000000000000000000000")});
    await quote.mint(vaultoperator.address, ethers.parseEther("1000000000000000000000000000000"));
    await base.connect(vaultoperator).deposit({value: ethers.parseEther("1000000000000000000000000000000")});
    await quote.mint(depositer.address, ethers.parseEther("1000000000000000000000000000000"));
    await base.connect(depositer).deposit({value: ethers.parseEther("1000000000000000000000000000000")});

    const CrystalFactory0 = await ethers.getContractFactory("CrystalMarket0Factory");
    crystalfactory0 = await CrystalFactory0.deploy();
    const CrystalFactory1 = await ethers.getContractFactory("CrystalMarket1Factory");
    crystalfactory1 = await CrystalFactory1.deploy();
    const CrystalFactory2 = await ethers.getContractFactory("CrystalMarket2Factory");
    crystalfactory2 = await CrystalFactory2.deploy();
    const Crystal = await ethers.getContractFactory("Crystal");
    crystal = await Crystal.deploy(base.target, owner.address, owner.address, 10, 10, 86400, [crystalfactory0.target, crystalfactory1.target, crystalfactory2.target], [1000000000000000000000n, 99000n, 5n, 1000000000000000000n, 99920, 99990, 40]);
    // price * base amount * base decimals = quote amount * quote decimals * scale factor
    // price factor = quote amount * scale factor / base amount
    // scale factor = real world max price * price factor * 10 ** quote decimals
    // price factor = 1_000_000_000_000_000 / 1_000_000_000
    const dummyParams = [
      true,
      quote.target,
      base.target,
      2, // market type
      21, // scale factor
      1, // tick size
      1_000_000_000_000_000, // max price
      1_000_000, // min size
      99_970, // taker fee
      99_990, // maker rebate
    ];
    const marketAddr = await crystal.deploy.staticCall(...dummyParams);
    const deployReceipt = await (await crystal.connect(owner).deploy(...dummyParams)).wait();

    market = await ethers.getContractAt("CrystalMarket1", marketAddr);

    await quote.connect(maker).approve(crystal.target, 115792089237316195423570985008687907853269984665640564039457584007913129639935n);
    await base.connect(maker).approve(crystal.target, 115792089237316195423570985008687907853269984665640564039457584007913129639935n);
    
    await crystal.connect(maker).registerUser(maker);
    await quote.connect(taker).approve(crystal.target, 115792089237316195423570985008687907853269984665640564039457584007913129639935n);
    await base.connect(taker).approve(crystal.target, 115792089237316195423570985008687907853269984665640564039457584007913129639935n);
    
    await crystal.connect(taker).registerUser(taker);

    const dummyParams1 = [
      false,
      quote.target,
      base.target,
      0, // market type
      15, // scale factor
      1, // tick size
      1000000, // max price
      1_000_000, // min size
      99_970, // taker fee
      99_990, // maker rebate
    ];
    const marketAddr1 = await crystal.deploy.staticCall(...dummyParams1);
    await crystal.connect(owner).deploy(...dummyParams1);

    market1 = await ethers.getContractAt("CrystalMarket0", marketAddr1);

    const CrystalVaultFactory = await ethers.getContractFactory("CrystalVaultFactory");

    vaultfactory = await CrystalVaultFactory.deploy(
      crystal.target,        // address of the Crystal contract
      owner.address,         // gov
      ethers.ZeroAddress,
      100,                  // defaultQuoteMin
      100000000000000000000n,                  // defaultBaseMin
      100,                  // maxOrderCap
      0n, // 0 day lockup
    );
    await quote.connect(vaultoperator).approve(vaultfactory.target, ethers.MaxUint256);
    await base.connect(vaultoperator).approve(vaultfactory.target, ethers.MaxUint256);
    const vaultName = "Vault1";
    const vaultDescription = "Test Vault";
    const amountQuote = 1_000n * 10n ** BigInt(await quote.decimals());
    const amountBase = 1_000n * 10n ** BigInt(await base.decimals());
    const vaultTx = await vaultfactory.connect(vaultoperator).deploy(
      quote.target,
      base.target,
      amountQuote,
      amountBase,
      vaultName,
      vaultDescription,
      'crystal.exchange',
      'x.com/crystalexch',
      'telegram'
    );
    const receipt = await vaultTx.wait();
    const vaultDeployedEvent = receipt.logs.map(log => {
      try {
        return vaultfactory.interface.parseLog(log);
      } catch { return null }
    }).find(ev => ev && ev.name === "VaultDeployed");
    vault = await ethers.getContractAt("CrystalVault", vaultDeployedEvent.args.vault);
    await quote.connect(depositer).approve(vaultfactory.target, 115792089237316195423570985008687907853269984665640564039457584007913129639935n);
    await base.connect(depositer).approve(vaultfactory.target, 115792089237316195423570985008687907853269984665640564039457584007913129639935n);
    const amounts = await vaultfactory.connect(depositer).deposit.staticCall(vault.target, quote.target, base.target, 2343n * 10n ** BigInt(await quote.decimals()), 1923n * 10n ** BigInt(await base.decimals()), 0, 0)
    await vaultfactory.connect(depositer).deposit(vault.target, quote.target, base.target, 2343n * 10n ** BigInt(await quote.decimals()), 1000n * 10n ** BigInt(await base.decimals()), 0, 0)
    tokenAddr = await crystal.connect(owner).createToken.staticCall('hi', 'hi', 'hi', 'hi', 'hi', 'hi', 'hi')
    await crystal.connect(owner).createToken('hi', 'hi', 'hi', 'hi', 'hi', 'hi', 'hi')
  }); 

  function makeHeader(marketAddr, numActions, internalBalance=0n) {
    const m = BigInt(marketAddr);
    const hdr = (internalBalance << 252n) | (BigInt(numActions) << 160n) | m;
    return ethers.zeroPadValue(ethers.toBeHex(hdr), 32);
  }

  function encodeAction(action, price, size, cloid=0n) {
    const a = BigInt(action);
    const p = BigInt(price);
    const s = BigInt(size);
    const chunk = (a << 252n) | (cloid << 192n) | (p << 112n) | s;
    return ethers.zeroPadValue(ethers.toBeHex(chunk), 32);
  }

  it("getMarket and allMarkets are populated", async () => {
    const mAddr = await market.getAddress();
    const mAddr1 = await market1.getAddress();
    expect(
      await crystal.getMarketByTokens(quote.target, base.target)
    ).to.equal(mAddr);
    expect(await crystal.allMarkets(0)).to.equal(mAddr);
    expect(await crystal.allMarkets(1)).to.equal(mAddr1);
  });

  it("place limit order via router", async () => {
    const rawPrice = 500;
    const rawSize = 1_000_000;

    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize);

    const orderId = await crystal
      .connect(maker)
      .limitOrder
      .staticCall(market.target, true, 0, priceParam, sizeParam);

      await expect(
      crystal.connect(maker).limitOrder(
        market.target, true, 0, priceParam, sizeParam
      )
    ).to.emit(crystal, "OrdersUpdated");

    expect(orderId).to.equal(1n);
  });

  it("cancel limit order via router", async () => {
    const rawPrice = 500;
    const rawSize = 1_000_000;

    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize);

    const orderId = await crystal
      .connect(maker)
      .limitOrder
      .staticCall(market.target, true, 0, priceParam, sizeParam);

    await expect(
      crystal.connect(maker).limitOrder(
        market.target, true, 0, priceParam, sizeParam
      )
    ).to.emit(crystal, "OrdersUpdated");

    expect(orderId).to.equal(1n);

    const tx = await crystal.connect(maker).cancelOrder(
      market.target, 0, priceParam, orderId
    );
    
    const receipt = await tx.wait();
    
    const ordersUpdatedEvent = receipt.logs.find(log => {
      try {
        const parsed = crystal.interface.parseLog(log);
        return parsed.name === 'OrdersUpdated';
      } catch {
        return false;
      }
    });
    
    expect(ordersUpdatedEvent).to.not.be.undefined;
    
    const parsed = crystal.interface.parseLog(ordersUpdatedEvent);
    const orderDataHex = parsed.args.orderData.slice(2);
    const flag = parseInt(orderDataHex.slice(0, 2), 16);
    
    expect(flag).equals(0);
  });

  it("place and cancel a limit order through fallback", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize);
    
    const marketAddr = await market.getAddress();
    
    const header = makeHeader(marketAddr, 1);
    const action = encodeAction(2, priceParam, sizeParam);
    
    const data = ethers.concat([header, action]);
    
    try {
      const tx = await maker.sendTransaction({
        to: crystal.target,
        data: data
      });
      
      await tx.wait();
      
      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market.target, true, 0, priceParam, sizeParam);
      
      expect(nextOrderId).to.equal(2n);
      
      const cancelledSize = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );

      expect(BigInt(cancelledSize.toString())).to.equal(sizeParam);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("place and cancel 100 limit orders through fallback", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);

    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize);
    const marketAddr = await market.getAddress();
    
    const header = makeHeader(marketAddr, 100);
    
    const chunks = Array.from({ length: 100 }, (_, i) => {
      const priceParam = BigInt(rawPrice + i) * priceFactor;
      return encodeAction(2, priceParam, sizeParam);
    });
    const data = ethers.concat([header, ...chunks]);
    
    let placeGas = 0n;
    let cancelGas = 0n;
    try {
      const tx = await crystal.connect(maker).fallback({ data });
      const receipt = await tx.wait();
      placeGas = BigInt(receipt.gasUsed);
      const tx1 = await crystal.connect(maker).fallback({ data });
      const receipt1 = await tx1.wait();
      placeGas = BigInt(receipt1.gasUsed);
      const tx2 = await crystal.connect(maker).fallback({ data });
      const receipt2 = await tx2.wait();
      placeGas = BigInt(receipt2.gasUsed);
      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market.target, true, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(4n);
      
      const firstOrderSize = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(firstOrderSize).to.be.greaterThan(0n);
      
      const cancelHeader = makeHeader(marketAddr, 100);
      const cancelChunks = Array.from({ length: 100 }, (_, i) => {
        const priceParam = BigInt(rawPrice + i) * priceFactor;
        return encodeAction(1, priceParam, 1);
      });
      const cancelData = ethers.concat([cancelHeader, ...cancelChunks]);
      const cancelTx = await crystal.connect(maker).fallback({ data: cancelData });
      const cancelReceipt = await cancelTx.wait();
      cancelGas = BigInt(cancelReceipt.gasUsed);
      
      const firstOrderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(firstOrderSizeAfter).to.equal(0n);
      
      console.log("Gas used for 100 placements:", placeGas.toString());
      console.log("Gas used for 100 cancels:", cancelGas.toString());
      console.log("Total gas used (place + cancel):", (placeGas + cancelGas).toString());
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("cloids n em", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr = await market.getAddress();
    
    const sellHeader = makeHeader(marketAddr, 1);
    let sellChunk = encodeAction(3, priceParam, sizeParam, 1n);

    try {
      let tx = await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      let receipt = await tx.wait();
      let ordersUpdatedEvent = crystal.interface.parseLog(receipt.logs.find(log => {
        try {
          const parsed = crystal.interface.parseLog(log);
          return parsed.name === 'OrdersUpdated';
        } catch {
          return false;
        }
      }));
      sellChunk = encodeAction(3, priceParam, sizeParam, 2n);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam, 3n);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market.target, false, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(3n);
      
      const buySize = BigInt(rawSize) * 6n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
        
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      // console.log("Gas used for 1 fills:", fillsReceipt.gasUsed.toString());
      // console.log(fillsReceipt.logs.length);
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
      sellChunk = encodeAction(3, priceParam, sizeParam, 1n);
      tx = await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      receipt = await tx.wait();
      ordersUpdatedEvent = crystal.interface.parseLog(receipt.logs.find(log => {
        try {
          const parsed = crystal.interface.parseLog(log);
          return parsed.name === 'OrdersUpdated';
        } catch {
          return false;
        }
      }));
      sellChunk = encodeAction(3, priceParam, sizeParam, 2n);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam, 4n);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      // console.log(await crystal.connect(maker).getPriceLevel.staticCall(market.target, priceParam));
      // console.log(await crystal.connect(maker).getOrderByCloid.staticCall(1n, 3n));
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("vaults n em", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr = await market.getAddress();
    
    const sellHeader = makeHeader(marketAddr, 1);
    let sellChunk = encodeAction(3, priceParam, sizeParam, 1n);

    try {
      let sharesBalance = await vault.connect(vaultoperator).balanceOf.staticCall(vaultoperator)
      console.log(sharesBalance)
      console.log(await vault.connect(vaultoperator).previewWithdrawal.staticCall(sharesBalance))
      let tx = await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      let receipt = await tx.wait();
      let ordersUpdatedEvent = crystal.interface.parseLog(receipt.logs.find(log => {
        try {
          const parsed = crystal.interface.parseLog(log);
          return parsed.name === 'OrdersUpdated';
        } catch {
          return false;
        }
      }));
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 2n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 3n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 4n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      tx = await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 5n, param1: priceParam, param2: sizeParam}]);
      receipt = await tx.wait();
      ordersUpdatedEvent = crystal.interface.parseLog(receipt.logs.find(log => {
        try {
          const parsed = crystal.interface.parseLog(log);
          return parsed.name === 'OrdersUpdated';
        } catch {
          return false;
        }
      }));
      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market.target, false, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(4n);
      
      let buySize = BigInt(rawSize) * 6n;
      const worstPrice = priceParam;
      
      let buyHeader = makeHeader(marketAddr, 1);
      let buyChunk = encodeAction(6, worstPrice, buySize);
      let buyData = ethers.concat([buyHeader, buyChunk]);
        
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      // console.log("Gas used for 1 fills:", fillsReceipt.gasUsed.toString());
      // console.log(fillsReceipt.logs.length);
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
      sellChunk = encodeAction(3, priceParam, sizeParam, 1n);
      tx = await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      receipt = await tx.wait();
      ordersUpdatedEvent = crystal.interface.parseLog(receipt.logs.find(log => {
        try {
          const parsed = crystal.interface.parseLog(log);
          return parsed.name === 'OrdersUpdated';
        } catch {
          return false;
        }
      }));
      sellChunk = encodeAction(3, priceParam, sizeParam, 2n);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam, 4n);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 2n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 3n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 4n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      tx = await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 5n, param1: priceParam, param2: sizeParam}]);
      tx = await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 6n, param1: priceParam, param2: sizeParam}]);
      fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });

      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 2n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      buySize = BigInt(rawSize) / 34n * 23n;
      buyHeader = makeHeader(marketAddr, 1);
      buyChunk = encodeAction(6, worstPrice, buySize);
      buyData = ethers.concat([buyHeader, buyChunk]);
      fills = await crystal.connect(taker).fallback({ data: buyData });
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, quote.target))
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, base.target))
      fills = await crystal.connect(taker).fallback({ data: buyData });
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, quote.target))
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, base.target))
      fills = await crystal.connect(taker).fallback({ data: buyData });
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, quote.target))
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, base.target))

      // console.log(await crystal.connect(maker).getPriceLevel.staticCall(market.target, priceParam));
      // console.log(await crystal.connect(maker).getOrderByCloid.staticCall(1n, 3n));
      sharesBalance = await vault.connect(vaultoperator).balanceOf.staticCall(vaultoperator)
      console.log(sharesBalance)
      console.log(await vault.connect(vaultoperator).previewWithdrawal.staticCall(sharesBalance))
      sharesBalance = await vault.connect(depositer).balanceOf.staticCall(depositer)
      console.log(sharesBalance)
      console.log(await vault.connect(depositer).previewWithdrawal.staticCall(sharesBalance))
      buySize = BigInt(rawSize) * 34n;
      buyHeader = makeHeader(marketAddr, 1);
      buyChunk = encodeAction(6, worstPrice, buySize);
      buyData = ethers.concat([buyHeader, buyChunk]);
      fills = await crystal.connect(taker).fallback({ data: buyData });
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, quote.target))
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, base.target))
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      console.log(await crystal.connect(vaultoperator).getOrderByCloid.staticCall(3n, 1n))
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 1n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      console.log(await crystal.connect(vaultoperator).getOrderByCloid.staticCall(3n, 1n))
      sharesBalance = await vault.connect(vaultoperator).balanceOf.staticCall(vaultoperator)
      console.log(sharesBalance)
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 2n, param1: priceParam, param2: sizeParam}]);
      console.log(await vault.connect(vaultoperator).previewWithdrawal.staticCall(sharesBalance))
      sharesBalance = await vault.connect(depositer).balanceOf.staticCall(depositer)
      console.log(sharesBalance)
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, quote.target))
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, base.target))
      await vaultfactory.connect(depositer).withdraw(vault.target, quote.target, base.target, sharesBalance, 0, 0)
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, quote.target))
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, base.target))
      sharesBalance = await vault.connect(vaultoperator).balanceOf.staticCall(vaultoperator)
      console.log(sharesBalance)
      await vaultfactory.connect(vaultoperator).withdraw(vault.target, quote.target, base.target, sharesBalance, 0, 0)
      sharesBalance = await vault.connect(depositer).balanceOf.staticCall(depositer)
      console.log(sharesBalance)
      sharesBalance = await vault.connect(depositer).balanceOf.staticCall(vaultoperator)
      console.log(sharesBalance)
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, quote.target))
      console.log(await crystal.connect(vaultoperator).getDepositedBalance.staticCall(vault, base.target))
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("place 1 sell orders and take all 3 with market buy via fallback", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr = await market.getAddress();
    
    const sellHeader = makeHeader(marketAddr, 1);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(1).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market.target, false, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(6n);
      
      const buySize = BigInt(rawSize) * 1n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
        
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 1 fills:", fillsReceipt.gasUsed.toString());
      console.log(fillsReceipt.logs.length);
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("place 10 sell orders and take all 3 with market buy via fallback", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr = await market.getAddress();
    
    const sellHeader = makeHeader(marketAddr, 10);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(10).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market.target, false, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(51n);
      
      const buySize = BigInt(rawSize) * 10n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
      
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 10 fills:", fillsReceipt.gasUsed.toString());
      console.log(fillsReceipt.logs.length);
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });
  
  it("place 100 sell orders and take all 3 with market buy via fallback", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr = await market.getAddress();
    
    const sellHeader = makeHeader(marketAddr, 100);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(100).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      expect((await crystal.getPriceLevelsFromMid.staticCall(market.target, 10000, 1, 0))[3]).to.equal('0x0000000000000000000000012a05f20000000000000000056bc75e2d63100000')
      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market.target, false, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(501n);
      
      const buySize = BigInt(rawSize) * 100n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
      
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 100 fills:", fillsReceipt.gasUsed.toString());
      console.log(fillsReceipt.logs.length);
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("place 1000 sell orders and take all 3 with market buy via fallback", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr = await market.getAddress();
    
    const sellHeader = makeHeader(marketAddr, 1000);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(1000).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market.target, false, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(5001n);
      
      const buySize = BigInt(rawSize) * 1000n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
      
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 1000 fills:", fillsReceipt.gasUsed.toString());
      console.log(fillsReceipt.logs.length);
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("single action", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market1.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);

    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize);
    const marketAddr = await market1.getAddress();
    
    const header = makeHeader(marketAddr, 1, 0n);
    
    const chunks = Array.from({ length: 1 }, (_, i) => {
      const priceParam = BigInt(rawPrice) * priceFactor + BigInt(i);
      return encodeAction(2, priceParam, sizeParam);
    });
    let data = ethers.concat([header, ...chunks]);
    
    let placeGas = 0n;
    let cancelGas = 0n;
    try {
      await crystal.connect(maker).deposit(quote.target, 1_000_000_000n * 10n ** BigInt(await quote.decimals()));
      await crystal.connect(maker).deposit(base.target, 1_000_000_000n * 10n ** BigInt(await base.decimals()));
      await crystal.connect(taker).deposit(quote.target, 1_000_000_000n * 10n ** BigInt(await quote.decimals()));
      await crystal.connect(taker).deposit(base.target, 1_000_000_000n * 10n ** BigInt(await base.decimals()));
      const tx = await crystal.connect(maker).fallback({ data });
      const receipt = await tx.wait();
      placeGas = BigInt(receipt.gasUsed);
      const tx1 = await crystal.connect(maker).fallback({ data });
      const receipt1 = await tx1.wait();
      placeGas = BigInt(receipt1.gasUsed);
      const tx2 = await crystal.connect(maker).fallback({ data });
      const receipt2 = await tx2.wait();
      placeGas = BigInt(receipt2.gasUsed);
      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market1.target, true, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(4n);
      
      const firstOrderSize = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, 0, priceParam, 1n
      );
      expect(firstOrderSize).to.be.greaterThan(0n);
      
      const cancelHeader = makeHeader(marketAddr, 1, 0n);
      const cancelChunks = Array.from({ length: 1 }, (_, i) => {
        const priceParam = BigInt(rawPrice) * priceFactor + BigInt(i);
        return encodeAction(1, priceParam, 1);
      });
      const cancelData = ethers.concat([cancelHeader, ...cancelChunks]);
      const cancelTx = await crystal.connect(maker).fallback({ data: cancelData });
      const cancelReceipt = await cancelTx.wait();
      cancelGas = BigInt(cancelReceipt.gasUsed);
      
      const firstOrderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, 0, priceParam, 1n
      );
      expect(firstOrderSizeAfter).to.equal(0n);
      let sellSize = BigInt(rawSize) * 100n * scaleFactor / priceParam;
      const worstPrice = 0n;
      const sellHeader = makeHeader(marketAddr, 1, 1n);
      const sellChunk = encodeAction(7, worstPrice, sellSize);
      let sellData = ethers.concat([sellHeader, sellChunk]);
      await crystal.connect(taker).fallback({ data: sellData });
      await crystal.connect(taker).fallback({ data: sellData });
      await crystal.connect(taker).fallback({ data: sellData });
      sellSize = BigInt(rawSize) * scaleFactor / priceParam / 15n;
      sellData = ethers.concat([makeHeader(marketAddr, 1, 1n), encodeAction(7, worstPrice, sellSize)]);
      data = ethers.concat([makeHeader(marketAddr, 100, 1n), ...Array.from({ length: 100 }, (_, i) => {
        const priceParam = BigInt(rawPrice) * priceFactor + BigInt(i);
        return encodeAction(2, priceParam, sizeParam);
      })]);
      await crystal.connect(maker).fallback({ data });

      let fills = await crystal.connect(taker).fallback({ data: sellData });

      const fillsReceipt = await fills.wait();
      console.log("Gas used for 1 placement:", placeGas.toString());
      console.log("Gas used for 1 cancel:", cancelGas.toString());
      console.log("Gas used for 1 fill:", fillsReceipt.gasUsed.toString());
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("100 at different price levels", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market1.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);

    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize);
    const marketAddr = await market1.getAddress();
    
    const header = makeHeader(marketAddr, 100, 0n);
    
    const chunks = Array.from({ length: 100 }, (_, i) => {
      const priceParam = BigInt(rawPrice) * priceFactor + BigInt(i);
      return encodeAction(2, priceParam, sizeParam);
    });
    let data = ethers.concat([header, ...chunks]);
    
    let placeGas = 0n;
    let cancelGas = 0n;
    try {
      await crystal.connect(maker).deposit(quote.target, 1_000_000_000n * 10n ** BigInt(await quote.decimals()));
      await crystal.connect(maker).deposit(base.target, 1_000_000_000n * 10n ** BigInt(await base.decimals()));
      await crystal.connect(taker).deposit(quote.target, 1_000_000_000n * 10n ** BigInt(await quote.decimals()));
      await crystal.connect(taker).deposit(base.target, 1_000_000_000n * 10n ** BigInt(await base.decimals()));
      const tx = await crystal.connect(maker).fallback({ data });
      const receipt = await tx.wait();
      placeGas = BigInt(receipt.gasUsed);
      const tx1 = await crystal.connect(maker).fallback({ data });
      const receipt1 = await tx1.wait();
      placeGas = BigInt(receipt1.gasUsed);
      const tx2 = await crystal.connect(maker).fallback({ data });
      const receipt2 = await tx2.wait();
      placeGas = BigInt(receipt2.gasUsed);
      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market1.target, true, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(4n);
      
      const firstOrderSize = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, 0, priceParam, 1n
      );
      expect(firstOrderSize).to.be.greaterThan(0n);
      
      const cancelHeader = makeHeader(marketAddr, 100, 0n);
      const cancelChunks = Array.from({ length: 100 }, (_, i) => {
        const priceParam = BigInt(rawPrice) * priceFactor + BigInt(i);
        return encodeAction(1, priceParam, 1);
      });
      const cancelData = ethers.concat([cancelHeader, ...cancelChunks]);
      const cancelTx = await crystal.connect(maker).fallback({ data: cancelData });
      const cancelReceipt = await cancelTx.wait();
      cancelGas = BigInt(cancelReceipt.gasUsed);
      
      const firstOrderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, 0, priceParam, 1n
      );
      expect(firstOrderSizeAfter).to.equal(0n);
      const sellSize = BigInt(rawSize) * 99n * scaleFactor / priceParam;
      const worstPrice = 0n;
      const sellHeader = makeHeader(marketAddr, 1, 1n);
      const sellChunk = encodeAction(7, worstPrice, sellSize);
      const sellData = ethers.concat([sellHeader, sellChunk]);
      await crystal.connect(taker).fallback({ data: sellData });
      await crystal.connect(taker).fallback({ data: sellData });
      await crystal.connect(taker).fallback({ data: sellData });
      data = ethers.concat([makeHeader(marketAddr, 100, 1n), ...Array.from({ length: 100 }, (_, i) => {
        const priceParam = BigInt(rawPrice) * priceFactor + BigInt(i);
        return encodeAction(2, priceParam, sizeParam);
      })]);
      await crystal.connect(maker).fallback({ data });

      let fills = await crystal.connect(taker).fallback({ data: sellData });

      const fillsReceipt = await fills.wait();
      console.log("Gas used for 100 placements:", placeGas.toString(), "avg:", (placeGas/100n).toString());
      console.log("Gas used for 100 cancels:", cancelGas.toString(), "avg:", (cancelGas/100n).toString());
      console.log("Gas used for 100 fills:", fillsReceipt.gasUsed.toString(), "avg:", (fillsReceipt.gasUsed/100n).toString());
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("useless vanity metrics (1000 at same price level)", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    const scaleFactor = BigInt((await market1.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr = await market1.getAddress();
    
    const sellHeader = makeHeader(marketAddr, 1000, 1n);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(1000).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).deposit(quote.target, 1_000_000_000n * 10n ** BigInt(await quote.decimals()));
      await crystal.connect(maker).deposit(base.target, 1_000_000_000n * 10n ** BigInt(await base.decimals()));
      await crystal.connect(taker).deposit(quote.target, 1_000_000_000n * 10n ** BigInt(await quote.decimals()));
      await crystal.connect(taker).deposit(base.target, 1_000_000_000n * 10n ** BigInt(await base.decimals()));
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      const tx = await crystal.connect(maker).fallback({ data: sellData });
      const receipt = await tx.wait();
      placeGas = BigInt(receipt.gasUsed);
      await crystal.connect(maker).fallback({ data: sellData });
      const cancelHeader = makeHeader(marketAddr, 1000, 1n);
      const cancelChunks = Array.from({ length: 1000 }, (_, i) => {
        return encodeAction(1, priceParam, BigInt(i));
      });
      const cancelData = ethers.concat([cancelHeader, ...cancelChunks]);
      const cancelTx = await crystal.connect(maker).fallback({ data: cancelData });
      const cancelReceipt = await cancelTx.wait();
      cancelGas = BigInt(cancelReceipt.gasUsed);
      await crystal.connect(maker).fallback({ data: sellData });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market1.target, false, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(5001n);
      
      const buySize = BigInt(rawSize) * 1000n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr, 1, 1n);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
      
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 1000 placements:", placeGas.toString(), "avg:", (placeGas/1000n).toString());
      console.log("Gas used for 1000 cancels:", cancelGas.toString(), "avg:", (cancelGas/1000n).toString());
      console.log("Gas used for 1000 fills:", fillsReceipt.gasUsed.toString(), "avg:", (fillsReceipt.gasUsed/1000n).toString());
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("AMM n em", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr = await market.getAddress();
    const sellHeader = makeHeader(marketAddr, 1);
    let sellChunk = encodeAction(3, priceParam, sizeParam);
    const makerBuyHeader = makeHeader(marketAddr, 1);
    let makerBuyChunk = encodeAction(2, BigInt(4.84 * Number(priceFactor)), 1289392n);
    try {
      let tx = await (await crystal.connect(maker).addLiquidityETH(market.target, maker, 4500n * 10n ** BigInt(await quote.decimals()), 1000n * 10n ** BigInt(await base.decimals()), 0, 0, {value: 1000n * 10n ** BigInt(await base.decimals())})).wait()
      console.log(tx.gasUsed)

      console.log("normal:") // add balances too
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, sizeParam * priceParam / scaleFactor, 100000000000000000n, maker))[0]).to.equal(sizeParam * priceParam / scaleFactor)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, sizeParam * priceParam / scaleFactor, 100000000000000000n))[0]).to.equal(sizeParam * priceParam / scaleFactor)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, sizeParam, 100000000000000000n, maker))[1]).to.equal(sizeParam)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, sizeParam, 100000000000000000n))[1]).to.equal(sizeParam)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, sizeParam, 0, maker))[0]).to.equal(sizeParam)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, sizeParam, 0))[0]).to.equal(sizeParam)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, sizeParam * priceParam / scaleFactor, 0, maker))[1]).to.equal(sizeParam * priceParam / scaleFactor)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, sizeParam * priceParam / scaleFactor, 0))[1]).to.equal(sizeParam * priceParam / scaleFactor)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, sizeParam * priceParam / scaleFactor + 284237n, 100000000000000000n, maker))[0]).to.equal(sizeParam * priceParam / scaleFactor + 284237n)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, sizeParam * priceParam / scaleFactor + 284237n, 100000000000000000n))[0]).to.equal(sizeParam * priceParam / scaleFactor + 284237n)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, sizeParam + 284237n, 100000000000000000n, maker))[1]).to.equal(sizeParam + 284237n)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, sizeParam + 284237n, 100000000000000000n))[1]).to.equal(sizeParam + 284237n)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, sizeParam + 284237n, 0, maker))[0]).to.equal(sizeParam + 284237n)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, sizeParam + 284237n, 0))[0]).to.equal(sizeParam + 284237n)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, sizeParam * priceParam / scaleFactor + 284237n, 0, maker))[1]).to.equal(sizeParam * priceParam / scaleFactor + 284237n)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, sizeParam * priceParam / scaleFactor + 284237n, 0))[1]).to.equal(sizeParam * priceParam / scaleFactor + 284237n)

      console.log("big:")
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, 100000000000000000000000000n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, 100000000000000000000000000n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, 100000000000000000000000000n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, 100000000000000000000000000n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, 100000000000000000000000000n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, 100000000000000000000000000n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, 100000000000000000000000000n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, 100000000000000000000000000n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, 1000000000234000002923800000523n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, 1000000000234000002923800000523n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, 1000000000234000002923800000523n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, 1000000000234000002923800000523n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, 1000000000234000002923800000523n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, 1000000000234000002923800000523n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, 1000000000234000002923800000523n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, 1000000000234000002923800000523n, 0))
      console.log("small:")
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, 13n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, 13n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, 13n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, 13n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, 13n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, 13n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, 13n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, 13n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, 17n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, 17n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, 17n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, 17n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, 17n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, 17n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, 17n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, 17n, 0))

      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      let reserves = await crystal.connect(maker).getReserves.staticCall(marketAddr);
      console.log(reserves[0] * scaleFactor / reserves[1])
      await crystal.connect(taker).marketOrder(marketAddr, true, true, 0, 0, sizeParam * priceParam / scaleFactor, 100000000000000000n, maker)
      let orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(200000000000000000n);
      reserves = await crystal.connect(maker).getReserves.staticCall(marketAddr);
      await crystal.connect(taker).marketOrder(marketAddr, true, true, 0, 0, sizeParam * 250n * priceParam / scaleFactor, 100000000000000000n, maker)
      orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
      reserves = await crystal.connect(maker).getReserves.staticCall(marketAddr);
      console.log(reserves[0] * scaleFactor / reserves[1])
      reserves = await crystal.connect(maker).getReserves.staticCall(marketAddr);
      console.log(reserves[0] * scaleFactor / reserves[1])
      await crystal.connect(taker).marketOrder(marketAddr, false, true, 0, 0, sizeParam, 0, maker)
      orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, BigInt(4.84 * Number(priceFactor)), 1n
      );
      expect(orderSizeAfter).to.equal(1289392n);
      reserves = await crystal.connect(maker).getReserves.staticCall(marketAddr);
      await crystal.connect(taker).marketOrder(marketAddr, false, true, 0, 0, sizeParam * 250n, 0, maker)
      orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, BigInt(4.84 * Number(priceFactor)), 1n
      );
      expect(orderSizeAfter).to.equal(0n);
      reserves = await crystal.connect(maker).getReserves.staticCall(marketAddr);
      console.log(reserves[0] * scaleFactor / reserves[1])
      await market.connect(maker).approve(crystal.target, 129481923801283018239912830192830192830192831n)
      let liquidity = await market.connect(maker).balanceOf.staticCall(maker);
      await crystal.connect(maker).removeLiquidityETH(marketAddr, maker, liquidity, 0, 0);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("quoting n em", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr = await market.getAddress();
    
    const sellHeader = makeHeader(marketAddr, 1);
    let sellChunk = encodeAction(3, priceParam, sizeParam, 1n);
    const makerBuyHeader = makeHeader(marketAddr, 1);
    let makerBuyChunk = encodeAction(2, BigInt(4.234 * Number(priceFactor)), 1289392n);

    try {
      let sharesBalance = await vault.connect(vaultoperator).balanceOf.staticCall(vaultoperator)
      let tx = await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      let receipt = await tx.wait();
      let ordersUpdatedEvent = crystal.interface.parseLog(receipt.logs.find(log => {
        try {
          const parsed = crystal.interface.parseLog(log);
          return parsed.name === 'OrdersUpdated';
        } catch {
          return false;
        }
      }));
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 2n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 3n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 4n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      tx = await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 5n, param1: priceParam, param2: sizeParam}]);
      receipt = await tx.wait();
      ordersUpdatedEvent = crystal.interface.parseLog(receipt.logs.find(log => {
        try {
          const parsed = crystal.interface.parseLog(log);
          return parsed.name === 'OrdersUpdated';
        } catch {
          return false;
        }
      }));
      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market.target, false, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(4n);
      
      let buySize = BigInt(rawSize) * 6n;
      const worstPrice = priceParam;
      
      let buyHeader = makeHeader(marketAddr, 1);
      let buyChunk = encodeAction(6, worstPrice, buySize);
      let buyData = ethers.concat([buyHeader, buyChunk]);
        
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
      sellChunk = encodeAction(3, priceParam, sizeParam, 1n);
      tx = await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      receipt = await tx.wait();
      ordersUpdatedEvent = crystal.interface.parseLog(receipt.logs.find(log => {
        try {
          const parsed = crystal.interface.parseLog(log);
          return parsed.name === 'OrdersUpdated';
        } catch {
          return false;
        }
      }));
      sellChunk = encodeAction(3, priceParam, sizeParam, 2n);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam, 4n);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 2n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 3n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 4n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      tx = await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 5n, param1: priceParam, param2: sizeParam}]);
      tx = await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 6n, param1: priceParam, param2: sizeParam}]);
      fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });

      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 2n, param1: priceParam, param2: sizeParam}]);
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      buySize = BigInt(rawSize) / 34n * 23n;
      buyHeader = makeHeader(marketAddr, 1);
      buyChunk = encodeAction(6, worstPrice, buySize);
      buyData = ethers.concat([buyHeader, buyChunk]);
      fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      await crystal.connect(maker).addLiquidity(market.target, maker, 4500n * 10n ** BigInt(await quote.decimals()), 1000n * 10n ** BigInt(await base.decimals()), 0, 0)
      sharesBalance = await vault.connect(vaultoperator).balanceOf.staticCall(vaultoperator)
      sharesBalance = await vault.connect(depositer).balanceOf.staticCall(depositer)
      buySize = BigInt(rawSize) * 34n;
      buyHeader = makeHeader(marketAddr, 1);
      buyChunk = encodeAction(6, worstPrice, buySize);
      buyData = ethers.concat([buyHeader, buyChunk]);
      fills = await crystal.connect(taker).fallback({ data: buyData });
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 3n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await vault.connect(vaultoperator).execute([{requireSuccess: true, action: 1n, cloid: 1n, param1: priceParam, param2: sizeParam}]);
      sellChunk = encodeAction(3, priceParam, sizeParam);
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([sellHeader, ...Array(1).fill(sellChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });
      await crystal.connect(maker).fallback({ data: ethers.concat([makerBuyHeader, ...Array(1).fill(makerBuyChunk)]) });

      console.log("normal:") // add balances too
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, sizeParam * priceParam / scaleFactor, 100000000000000000n, maker))[0]).to.equal(sizeParam * priceParam / scaleFactor)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, sizeParam * priceParam / scaleFactor, 100000000000000000n))[0]).to.equal(sizeParam * priceParam / scaleFactor)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, sizeParam, 100000000000000000n, maker))[1]).to.equal(sizeParam)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, sizeParam, 100000000000000000n))[1]).to.equal(sizeParam)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, sizeParam, 0, maker))[0]).to.equal(sizeParam)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, sizeParam, 0))[0]).to.equal(sizeParam)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, sizeParam * priceParam / scaleFactor, 0, maker))[1]).to.equal(sizeParam * priceParam / scaleFactor)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, sizeParam * priceParam / scaleFactor, 0))[1]).to.equal(sizeParam * priceParam / scaleFactor)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, sizeParam * priceParam / scaleFactor + 284237n, 100000000000000000n, maker))[0]).to.equal(sizeParam * priceParam / scaleFactor + 284237n)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, sizeParam * priceParam / scaleFactor + 284237n, 100000000000000000n))[0]).to.equal(sizeParam * priceParam / scaleFactor + 284237n)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, sizeParam + 284237n, 100000000000000000n, maker))[1]).to.equal(sizeParam + 284237n)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, sizeParam + 284237n, 100000000000000000n))[1]).to.equal(sizeParam + 284237n)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, sizeParam + 284237n, 0, maker))[0]).to.equal(sizeParam + 284237n)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, sizeParam + 284237n, 0))[0]).to.equal(sizeParam + 284237n)
      expect((await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, sizeParam * priceParam / scaleFactor + 284237n, 0, maker))[1]).to.equal(sizeParam * priceParam / scaleFactor + 284237n)
      expect((await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, sizeParam * priceParam / scaleFactor + 284237n, 0))[1]).to.equal(sizeParam * priceParam / scaleFactor + 284237n)

      console.log("big:")
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, 100000000000000000000000000n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, 100000000000000000000000000n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, 100000000000000000000000000n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, 100000000000000000000000000n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, 100000000000000000000000000n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, 100000000000000000000000000n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, 100000000000000000000000000n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, 100000000000000000000000000n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, 1000000000234000002923800000523n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, 1000000000234000002923800000523n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, 1000000000234000002923800000523n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, 1000000000234000002923800000523n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, 1000000000234000002923800000523n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, 1000000000234000002923800000523n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, 1000000000234000002923800000523n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, 1000000000234000002923800000523n, 0))
      console.log("small:")
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, 13n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, 13n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, 13n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, 13n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, 13n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, 13n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, 13n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, 13n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, true, 0, 0, 17n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, true, false, 17n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, true, false, 0, 0, 17n, 100000000000000000n, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, true, false, false, 17n, 100000000000000000n))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, true, 0, 0, 17n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, true, false, 17n, 0))
      console.log(await crystal.connect(taker).marketOrder.staticCall(marketAddr, false, false, 0, 0, 17n, 0, maker))
      console.log(await crystal.connect(taker).getQuote.staticCall(marketAddr, false, false, false, 17n, 0))
      sharesBalance = await vault.connect(vaultoperator).balanceOf.staticCall(vaultoperator)
      sharesBalance = await vault.connect(depositer).balanceOf.staticCall(depositer)
      await vaultfactory.connect(depositer).withdraw(vault.target, quote.target, base.target, sharesBalance, 0, 0)
      sharesBalance = await vault.connect(vaultoperator).balanceOf.staticCall(vaultoperator)
      await vaultfactory.connect(vaultoperator).withdraw(vault.target, quote.target, base.target, sharesBalance, 0, 0)
      sharesBalance = await vault.connect(depositer).balanceOf.staticCall(depositer)
      sharesBalance = await vault.connect(depositer).balanceOf.staticCall(vaultoperator)
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("launchpad n em", async () => {
    try {
      const tx = await crystal.connect(taker).buy(true, tokenAddr, 1000000000000000000n, 0, { value: 1000000000000000000n });
      const receipt = await tx.wait();
      let placeGas = BigInt(receipt.gasUsed);
      console.log(await crystal.launchpadTokenToMarket.staticCall(tokenAddr))

      const tx2 = await crystal.connect(taker).buy(true, tokenAddr, 100000000000000000000000n, 0, { value: 100000000000000000000000n });
      const receipt2 = await tx2.wait();
      let placeGas2 = BigInt(receipt2.gasUsed);
      console.log(await crystal.launchpadTokenToMarket.staticCall(tokenAddr))
      const tx3 = await crystal.connect(taker).buy(true, tokenAddr, 1000000000000000000000000n, 0, { value: 1000000000000000000000000n });
      const receipt3 = await tx3.wait();
      let placeGas3 = BigInt(receipt3.gasUsed);
      console.log(await crystal.launchpadTokenToMarket.staticCall(tokenAddr))
      console.log(placeGas, placeGas2, placeGas3)

    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  /* it("place 10000 sell orders and take all 3 with market buy via fallback", async () => {
    const rawPrice = 5;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr = await market.getAddress();
    
    const sellHeader = makeHeader(marketAddr, 10000);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(10000).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market.target, false, 0, priceParam, sizeParam);
      expect(nextOrderId).to.equal(30001n);
      
      const buySize = BigInt(rawSize) * 10000n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
      
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 10000 fills:", fillsReceipt.gasUsed.toString());
      console.log(fillsReceipt.logs.length);
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market.target, 0, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  }); */

  /* it("place and cancel a limit order through fallback 1", async () => {
    const rawPrice = 1;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market1.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize);
    
    const marketAddr1 = await market1.getAddress();
    
    const header = makeHeader(marketAddr1, 1);
    const action = encodeAction(2, priceParam, sizeParam);
    
    const data = ethers.concat([header, action]);
    
    try {
      const tx = await maker.sendTransaction({
        to: crystal.target,
        data: data
      });
      
      await tx.wait();
      
      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market1.target, true, priceParam, sizeParam);
      
      expect(nextOrderId).to.equal(2n);
      
      const cancelledSize = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, priceParam, 1n
      );

      expect(BigInt(cancelledSize.toString())).to.equal(sizeParam * scaleFactor);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("place and cancel 100 limit orders through fallback 1", async () => {
    const rawPrice = 2563;
    const rawSize = 15728640;
    
    const scaleFactor = BigInt((await market1.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);

    const priceParam = BigInt(rawPrice) * priceFactor / BigInt(1000);
    const sizeParam = BigInt(rawSize);
    const marketAddr1 = await market1.getAddress();
    
    const header = makeHeader(marketAddr1, 100);
    
    const chunks = Array.from({ length: 100 }, (_, i) => {
      const priceParam = BigInt(rawPrice + i) * priceFactor / BigInt(1000);
      return encodeAction(2, priceParam, sizeParam);
    });
    const data = ethers.concat([header, ...chunks]);
    
    let placeGas = 0n;
    let cancelGas = 0n;
    try {
      const tx = await crystal.connect(maker).fallback({ data });
      const receipt = await tx.wait();
      placeGas = BigInt(receipt.gasUsed);
      const tx1 = await crystal.connect(maker).fallback({ data });
      const receipt1 = await tx1.wait();
      placeGas = BigInt(receipt1.gasUsed);
      const tx2 = await crystal.connect(maker).fallback({ data });
      const receipt2 = await tx2.wait();
      placeGas = BigInt(receipt2.gasUsed);
      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market1.target, true, priceParam, sizeParam);
      expect(nextOrderId).to.equal(4n);
      
      const firstOrderSize = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, priceParam, 1n
      );
      expect(firstOrderSize).to.be.greaterThan(0n);
      
      const cancelHeader = makeHeader(marketAddr1, 100);
      const cancelChunks = Array.from({ length: 100 }, (_, i) => {
        const priceParam = BigInt(rawPrice + i) * priceFactor / BigInt(1000);
        return encodeAction(1, priceParam, 1);
      });
      const cancelData = ethers.concat([cancelHeader, ...cancelChunks]);
      const cancelTx = await crystal.connect(maker).fallback({ data: cancelData });
      const cancelReceipt = await cancelTx.wait();
      cancelGas = BigInt(cancelReceipt.gasUsed);
      
      const firstOrderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, priceParam, 1n
      );
      expect(firstOrderSizeAfter).to.equal(0n);
      
      console.log("Gas used for 100 placements:", placeGas.toString());
      console.log("Gas used for 100 cancels:", cancelGas.toString());
      console.log("Total gas used (place + cancel):", (placeGas + cancelGas).toString());
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });

  it("place 1 sell orders and take all 3 with market buy via fallback 1", async () => {
    const rawPrice = 1;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market1.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr1 = await market1.getAddress();
    
    const sellHeader = makeHeader(marketAddr1, 1);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(1).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market1.target, false, priceParam, sizeParam);
      expect(nextOrderId).to.equal(7n);
      
      const buySize = BigInt(rawSize) * 1n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr1, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
      
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 1 fills:", fillsReceipt.gasUsed.toString());
      console.log(fillsReceipt.logs.length);
      const priceLevel = await crystal.connect(maker).getPriceLevel.staticCall(market1.target, priceParam);
      expect(priceLevel[0]).to.equal(4000000000000000000000n)
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });
  it("place 10 sell orders and take all 3 with market buy via fallback 1", async () => {
    const rawPrice = 1;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market1.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr1 = await market1.getAddress();
    
    const sellHeader = makeHeader(marketAddr1, 10);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(10).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market1.target, false, priceParam, sizeParam);
      expect(nextOrderId).to.equal(61n);
      
      const buySize = BigInt(rawSize) * 10n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr1, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
      
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 10 fills:", fillsReceipt.gasUsed.toString());
      console.log(fillsReceipt.logs.length);
      const priceLevel = await crystal.connect(maker).getPriceLevel.staticCall(market1.target, priceParam);
      expect(priceLevel[0]).to.equal(40000000000000000000000n)
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });
  it("place 100 sell orders and take all 3 with market buy via fallback 1", async () => {
    const rawPrice = 1;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market1.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr1 = await market1.getAddress();
    
    const sellHeader = makeHeader(marketAddr1, 100);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(100).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market1.target, false, priceParam, sizeParam);
      expect(nextOrderId).to.equal(601n);
      
      const buySize = BigInt(rawSize) * 100n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr1, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
      
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 100 fills:", fillsReceipt.gasUsed.toString());
      console.log(fillsReceipt.logs.length);
      const priceLevel = await crystal.connect(maker).getPriceLevel.staticCall(market1.target, priceParam);
      expect(priceLevel[0]).to.equal(400000000000000000000000n)
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });
  it("place 1000 sell orders and take all 3 with market buy via fallback 1", async () => {
    const rawPrice = 1;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market1.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr1 = await market1.getAddress();
    
    const sellHeader = makeHeader(marketAddr1, 1000);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(1000).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market1.target, false, priceParam, sizeParam);
      expect(nextOrderId).to.equal(6001n);
      
      const buySize = BigInt(rawSize) * 1000n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr1, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
      
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 1000 fills:", fillsReceipt.gasUsed.toString());
      console.log(fillsReceipt.logs.length);
      const priceLevel = await crystal.connect(maker).getPriceLevel.staticCall(market1.target, priceParam);
      expect(priceLevel[0]).to.equal(4000000000000000000000000n)
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  });
  it("place 10000 sell orders and take all 3 with market buy via fallback 1", async () => {
    const rawPrice = 1;
    const rawSize = 1_000_000;
    
    const scaleFactor = BigInt((await market1.scaleFactor()).toString());
    const quoteDecimals = BigInt(await quote.decimals());
    const baseDecimals = BigInt(await base.decimals());
    const priceFactor = quoteDecimals >= baseDecimals
      ? scaleFactor * 10n ** (quoteDecimals - baseDecimals)
      : scaleFactor / 10n ** (baseDecimals - quoteDecimals);
    
    const priceParam = BigInt(rawPrice) * priceFactor;
    const sizeParam = BigInt(rawSize) * scaleFactor / priceParam;
    
    const marketAddr1 = await market1.getAddress();
    
    const sellHeader = makeHeader(marketAddr1, 10000);
    const sellChunk = encodeAction(3, priceParam, sizeParam);
    const sellChunks = Array(10000).fill(sellChunk);
    const sellData = ethers.concat([sellHeader, ...sellChunks]);

    try {
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });
      await crystal.connect(maker).fallback({ data: sellData });

      const nextOrderId = await crystal
        .connect(maker)
        .limitOrder
        .staticCall(market1.target, false, priceParam, sizeParam);
      expect(nextOrderId).to.equal(30001n);
      
      const buySize = BigInt(rawSize) * 10000n;
      const worstPrice = priceParam;
      
      const buyHeader = makeHeader(marketAddr1, 1);
      const buyChunk = encodeAction(6, worstPrice, buySize);
      const buyData = ethers.concat([buyHeader, buyChunk]);
      
      let fills = await crystal.connect(taker).fallback({ data: buyData });
      fills = await crystal.connect(taker).fallback({ data: buyData });
      const fillsReceipt = await fills.wait();
      console.log("Gas used for 10000 fills:", fillsReceipt.gasUsed.toString());
      console.log(fillsReceipt.logs.length);
      const priceLevel = await crystal.connect(maker).getPriceLevel.staticCall(market1.target, priceParam);
      expect(priceLevel[0]).to.equal(10000000000000000000000000n)
      const orderSizeAfter = await crystal.connect(maker).cancelOrder.staticCall(
        market1.target, priceParam, 1n
      );
      expect(orderSizeAfter).to.equal(0n);
    } catch (error) {
      console.error("tx failed:", error);
      throw error;
    }
  }); */
});