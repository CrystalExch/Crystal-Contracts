const { ethers: hardhatEthers } = require("hardhat");
const { ethers } = require("ethers");
require("dotenv").config()

async function main() {
  // Get the transaction data from Hardhat (without sending)
  const [owner] = await hardhatEthers.getSigners();

  // Token addresses
  const quoteAddr = "0xf817257fed379853cDe0fa4F97AB987181B1E5Ea";
  const baseAddr = "0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701";

  // Set up regular ethers provider and wallet for signing/sending
  const provider = new ethers.JsonRpcProvider("https://testnet-rpc.monad.xyz"); // Replace with actual Monad RPC
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

  console.log("Deploying with address:", wallet.address);

  // Helper function to get deployment data and send via regular ethers
  async function deployWithEthers(contractFactory, ...args) {
    // Get deployment transaction data from Hardhat
    const deployTx = await contractFactory.getDeployTransaction(...args);
    const estimated = await provider.estimateGas({
        from: wallet.address,
        to: null,
        data: deployTx.data
      });
    // Prepare transaction for regular ethers
    const tx = {
      to: null, // deployment
      data: deployTx.data,
      gasLimit: estimated, // High gas limit for large contracts
      gasPrice: 162000000000,
      chainId: 10143,
      nonce: await provider.getTransactionCount(wallet.address),
    };
    
    // Sign and send with regular ethers
    const signedTx = await wallet.signTransaction(tx);
    const response = await provider.broadcastTransaction(signedTx);

    // Wait for deployment
    const receipt = await response.wait();
    console.log(`Contract deployed to: ${receipt.contractAddress}`);
    
    return {
      address: receipt.contractAddress,
      contract: new ethers.Contract(receipt.contractAddress, contractFactory.interface, wallet)
    };
  }

  // Deploy main Crystal contract
  const Crystal = await hardhatEthers.getContractFactory("Crystal");
  const crystalResult = await deployWithEthers(
    Crystal,
    baseAddr,
    wallet.address,
    wallet.address,
    10,
    86400,
    [1000000000000000000000n, 99000n, 10n, 1000000000000000000n, 99910n, 99990n, 40]
  );

  // Helper function for contract calls
  async function callWithEthers(contract, methodName, args = []) {
    const callData = contract.interface.encodeFunctionData(methodName, args);
    const estimated = await provider.estimateGas({
        from: wallet.address,
        to: await contract.getAddress(),
        data: callData
      });
    const tx = {
      to: await contract.getAddress(),
      data: callData,
      gasLimit: estimated,
      gasPrice: 162000000000,
      chainId: 10143,
      nonce: await provider.getTransactionCount(wallet.address),
    };

    const signedTx = await wallet.signTransaction(tx);
    const response = await provider.broadcastTransaction(signedTx);
    
    const receipt = await response.wait();
    return receipt;
  }
  const markets = []
  // Deploy markets using the Crystal contract
  let dummyParams = [
    true,
    quoteAddr,
    baseAddr,
    2,
    21,
    1,
    1_000_000_000_000_000,
    1_000_000,
    99_950,
    99_990,
  ];

  // First get the address that will be deployed
  let marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  // Then actually deploy
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);

  dummyParams = [
    false,
    quoteAddr,
    baseAddr,
    0,
    15,
    1,
    1_000_000,
    1_000_000,
    99_950,
    99_990,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);

  dummyParams = [
    true,
    quoteAddr,
    '0xB5a30b0FDc5EA94A52fDc42e3E9760Cb8449Fb37',
    0,
    13,
    1,
    1_000_000,
    1_000_000,
    99_970,
    99_990,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);

  dummyParams = [
    true,
    quoteAddr,
    '0xcf5a6076cfa32686c0Df13aBaDa2b40dec133F1d',
    0,
    2,
    1,
    1_000_000,
    1_000_000,
    99_970,
    99_990,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);

  dummyParams = [
    true,
    quoteAddr,
    '0x5387C85A4965769f6B0Df430638a1388493486F1',
    0,
    5,
    1,
    1_000_000,
    1_000_000,
    99_970,
    99_990,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);

  dummyParams = [
    true,
    quoteAddr,
    '0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D',
    0,
    4,
    1,
    100000,
    1000000,
    99_990,
    100_000,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);

  dummyParams = [
    true,
    baseAddr,
    '0xe1d2439b75fb9746E7Bc6cB777Ae10AA7f7ef9c5',
    0,
    4,
    1,
    100000,
    100000000000000000n,
    99_990,
    100_000,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);
  
  dummyParams = [
    true,
    baseAddr,
    '0xb2f82D0f38dc453D596Ad40A37799446Cc89274A',
    0,
    4,
    1,
    100000,
    100000000000000000n,
    99_990,
    100_000,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);
  
  dummyParams = [
    true,
    baseAddr,
    '0x3a98250F98Dd388C211206983453837C8365BDc1',
    0,
    4,
    1,
    100000,
    100000000000000000n,
    99_990,
    100_000,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);
  
  dummyParams = [
    true,
    baseAddr,
    '0x0F0BDEbF0F83cD1EE3974779Bcb7315f9808c714',
    2,
    9,
    1,
    1_000_000_000_000_000,
    100000000000000000n,
    99950n,
    99990n,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);
  
  dummyParams = [
    true,
    baseAddr,
    '0xE0590015A873bF326bd645c3E1266d4db41C4E6B',
    2,
    9,
    1,
    1_000_000_000_000_000,
    100000000000000000n,
    99950n,
    99990n,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);
  
  dummyParams = [
    true,
    baseAddr,
    '0xfe140e1dCe99Be9F4F15d657CD9b7BF622270C50',
    2,
    9,
    1,
    1_000_000_000_000_000,
    100000000000000000n,
    99950n,
    99990n,
  ];

  marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market will be deployed to:", marketAddr);
  markets.push(marketAddr)
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);
  
  // Deploy vault factory
  const CrystalVaultFactory = await hardhatEthers.getContractFactory("CrystalVaultFactory");
  const vaultfactoryResult = await deployWithEthers(
    CrystalVaultFactory,
    crystalResult.address,
    wallet.address,
    "0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701",
    100,
    100,
    5n
  );

  // deploy ref helper
  const CrystalHelper = await hardhatEthers.getContractFactory("CrystalReferralManager");
  const CrystalHelperResult = await deployWithEthers(
    CrystalHelper,
    wallet.address
  );

  console.log("\n=== Deployment Summary ===");
  console.log("Crystal:", crystalResult.address);
  console.log("VaultFactory:", vaultfactoryResult.address);
  console.log("Helper:", CrystalHelperResult.address)
  console.log("Markets:", markets);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});