const hardhat = require("hardhat")
const { ethers } = require("ethers")
require("dotenv").config()

function envOrDefault(name, fallback) {
  const value = process.env[name]
  return value && value.trim() !== "" ? value : fallback
}

const RPC_URL = envOrDefault("RPC_URL", "https://rpc.monad.xyz")
const CHAIN_ID = BigInt(envOrDefault("CHAIN_ID", "143"))
const GAS_PRICE = BigInt(envOrDefault("GAS_PRICE", "150000000000")) // 150 gwei

const USDC = envOrDefault("USDC", "0x754704Bc059F8C67012fEd69BC8A327a5aafb603") // Canonical Stablecoin
const WETH = envOrDefault("WETH", "0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A") // Wrapped Native Token (WMON)

const MARKETS = [ // [Canonical, Quote Asset, Base Asset, Market Type, Scale Factor, Tick Size, Max Price, Min Size, Taker Fee, Maker Rebate]
  [
    true,
    USDC,
    WETH,
    2, // Dynamic Price Ticks, AMM Enabled
    21, // USDC is 6 Decimals, WMON is 18, 21 - 18 + 6 = 9, Minimum Price Tick of 0.000000001
    1, // Tick size of 1
    1_000_000_000_000_000n, // 1,000,000 USDC per WMON
    1_000_000n, // 1 USDC
    99970n, // 0.03%
    99995n // 0.005%
  ],
  [ // Duplicate WMON/USDC market, non-canonical
    false,
    USDC,
    WETH,
    0, // Static Price Ticks, AMM Disabled
    17, // USDC is 6 Decimals, WMON is 18, 17 - 18 + 6 = 5, Minimum Price Tick of 0.00001
    1, // Tick size of 1
    1_000_000n, // 10 USDC per WMON
    1_000_000n, // 1 USDC
    99970n, // 0.03%
    99995n // 0.005%
  ],
  [ // AUSD/USDC market, canonical
    true,
    USDC,
    "0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a",
    0, // Static Price Ticks, AMM Disabled
    4, // USDC is 6 Decimals, AUSD is 6, 4 - 6 + 6 = 4, Minimum Price Tick of 0.0001
    1, // Tick size of 1
    100_000n, // 10 USDC per AUSD
    1_000_000n, // 1 USDC
    99990n, // 0.01%
    100000n // 0.00%
  ],
  [ // XAUt0/USDC market, canonical
    true,
    USDC,
    '0x01bFF41798a0BcF287b996046Ca68b395DbC1071',
    2, // Dynamic Price Ticks, AMM Enabled
    9, // USDC is 6 Decimals, XAUt0 is 6, 9 - 6 + 6 = 9, Minimum Price Tick of 0.000000001
    1, // Tick size of 1
    1_000_000_000_000_000n, // 1,000,000 USDC per XAUt0
    1_000_000n, // 1 USDC
    99970n, // 0.03%
    99995n // 0.005%
  ],
]

async function deploy(factory, signer, provider, args = []) {
  const txReq = await factory.getDeployTransaction(...args)
  const gas = await provider.estimateGas({ from: signer.address, data: txReq.data })
  const signed = await signer.signTransaction({
    data: txReq.data,
    gasLimit: gas,
    gasPrice: GAS_PRICE,
    chainId: CHAIN_ID,
    nonce: await provider.getTransactionCount(signer.address)
  })
  const receipt = await (await provider.broadcastTransaction(signed)).wait()
  return receipt.contractAddress
}

async function call(contract, signer, provider, fn, args = []) {
  const data = contract.interface.encodeFunctionData(fn, args)
  const gas = await provider.estimateGas({ from: signer.address, to: await contract.getAddress(), data })
  const signed = await signer.signTransaction({
    to: await contract.getAddress(),
    data,
    gasLimit: gas,
    gasPrice: GAS_PRICE,
    chainId: CHAIN_ID,
    nonce: await provider.getTransactionCount(signer.address)
  })
  return (await provider.broadcastTransaction(signed)).wait()
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL)
  const privateKey = envOrDefault("PRIVATE_KEY")
  if (!privateKey) throw new Error("PRIVATE_KEY is required")
  const wallet = new ethers.Wallet(privateKey, provider)

  const Crystal = await hardhat.ethers.getContractFactory("Crystal", wallet)
  const crystalAddr = await deploy(Crystal, wallet, provider, [ // [WETH, Owner, Fee Recipient, Referral Commission (x/100), Fee Claim Duration (s), Launchpad Parameters: [Initial Native Supply, Launchpad Fee, Launchpad Creator Fee Split, Graduated Minimum Size, Graduated Taker Fee, Graduated Maker Rebate, Graduated Creator Fee Split]]
    WETH,
    wallet.address,
    wallet.address,
    10, // 10%
    86400, // 1 Day
    [1000000000000000000000n, 99000n, 10n, 100000000000000000000n, 99970n, 99995n, 50] // [1000 MON, 1%, 10%, 100 MON, 0.03%, 0.005%, 50%]
  ])
  const crystal = new ethers.Contract(crystalAddr, Crystal.interface, wallet)

  const markets = []
  for (const params of MARKETS) {
    const predicted = await crystal.deploy.staticCall(...params)
    await call(crystal, wallet, provider, "deploy", params)
    markets.push(predicted)
  }

  const VaultFactory = await hardhat.ethers.getContractFactory("CrystalVaultFactory")
  const vaultFactoryAddr = await deploy(VaultFactory, wallet, provider, [ // [Crystal, Owner, WETH, Minimum Deposit, Order Cap, Maximum Lockup Duration (s)]
    crystalAddr,
    wallet.address,
    WETH,
    1000, // 1000 Wei
    100, // 100 Orders
    86400 * 30, // 1 Month
  ])

  console.log({
    crystal: crystalAddr,
    vaultFactory: vaultFactoryAddr,
    markets
  })
}

main().catch(e => { console.error(e); process.exit(1) })