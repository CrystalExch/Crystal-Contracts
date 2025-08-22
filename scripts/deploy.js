const { ethers: hardhatEthers } = require("hardhat");
const { ethers } = require("ethers");

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
      gasPrice: 62000000000,
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

  // Deploy factory contracts
  console.log("Deploying CrystalMarket0Factory...");
  const CrystalFactory0 = await hardhatEthers.getContractFactory("CrystalMarket0Factory");
  const crystalfactory0Result = await deployWithEthers(CrystalFactory0);

  console.log("Deploying CrystalMarket1Factory...");
  const CrystalFactory1 = await hardhatEthers.getContractFactory("CrystalMarket1Factory");
  const crystalfactory1Result = await deployWithEthers(CrystalFactory1);

  console.log("Deploying CrystalMarket2Factory...");
  const CrystalFactory2 = await hardhatEthers.getContractFactory("CrystalMarket2Factory");
  const crystalfactory2Result = await deployWithEthers(CrystalFactory2);

  // Deploy main Crystal contract
  console.log("Deploying Crystal...");
  const Crystal = await hardhatEthers.getContractFactory("Crystal");
  const crystalResult = await deployWithEthers(
    Crystal,
    baseAddr,
    wallet.address,
    wallet.address,
    10,
    10,
    86400,
    [crystalfactory0Result.address, crystalfactory1Result.address, crystalfactory2Result.address],
    [1000000000000000000000n, 99000n, 5n, 1000000000000000000n, 99920, 99990, 40]
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
      gasPrice: 62000000000,
      chainId: 10143,
      nonce: await provider.getTransactionCount(wallet.address),
    };

    const signedTx = await wallet.signTransaction(tx);
    const response = await provider.broadcastTransaction(signedTx);
    console.log(`${methodName} transaction sent: ${response.hash}`);
    
    const receipt = await response.wait();
    return receipt;
  }

  // Deploy markets using the Crystal contract
  const dummyParams = [
    true,
    quoteAddr,
    baseAddr,
    2,
    21,
    1,
    1_000_000_000_000_000,
    1_000_000,
    99_970,
    99_990,
  ];

  console.log("Creating market1...");
  // First get the address that will be deployed
  const marketAddr = await crystalResult.contract["deploy"].staticCall(...dummyParams);
  console.log("Market1 will be deployed to:", marketAddr);
  
  // Then actually deploy
  await callWithEthers(crystalResult.contract, "deploy", dummyParams);
  const market = new ethers.Contract(marketAddr, (await hardhatEthers.getContractFactory("CrystalMarket1")).interface, wallet);

  const dummyParams1 = [
    false,
    quoteAddr,
    baseAddr,
    0,
    15,
    1,
    1_000_000,
    1_000_000,
    99_970,
    99_990,
  ];

  console.log("Creating market0...");
  const marketAddr1 = await crystalResult.contract["deploy"].staticCall(...dummyParams1);
  console.log("Market0 will be deployed to:", marketAddr1);
  
  await callWithEthers(crystalResult.contract, "deploy", dummyParams1);
  const market1 = new ethers.Contract(marketAddr1, (await hardhatEthers.getContractFactory("CrystalMarket0")).interface, wallet);

  // Deploy vault factory
  console.log("Deploying CrystalVaultFactory...");
  const CrystalVaultFactory = await hardhatEthers.getContractFactory("CrystalVaultFactory");
  const vaultfactoryResult = await deployWithEthers(
    CrystalVaultFactory,
    crystalResult.address,
    wallet.address,
    ethers.ZeroAddress,
    100,
    100000000000000000000n,
    100,
    0n
  );

  console.log("\n=== Deployment Summary ===");
  console.log("Quote token:", quoteAddr);
  console.log("Base token:", baseAddr);
  console.log("Crystal:", crystalResult.address);
  console.log("Market1:", marketAddr);
  console.log("Market0:", marketAddr1);
  console.log("VaultFactory:", vaultfactoryResult.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});