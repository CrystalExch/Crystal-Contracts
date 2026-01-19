const hardhat = require("hardhat")
const { ethers } = require("ethers")
require("dotenv").config()

const RPC_URL = "https://rpc.monad.xyz"
const CHAIN_ID = 143 // Monad Mainnet
const GAS_PRICE = 150000000000n // 150 gwei

const USDC = "0xf817257fed379853cDe0fa4F97AB987181B1E5Ea" // Canonical Stablecoin
const WETH = "0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701" // Wrapped Native Token

const MARKETS = [ // [Canonical, Quote Asset, Base Asset, Market Type, Scale Factor, Tick Size, Max Price, Min Size, Taker Fee, Maker Rebate]
  [
    true,
    USDC,
    WETH,
    2, // Dynamic Price Ticks, AMM Enabled
    21, // USDC is 6 Decimals, WETH is 18, 21 - 18 + 6 = 9, Minimum Price Tick of 0.000000001
    1,
    1_000_000_000_000_000n, // 1,000,000 USDC per WETH
    1_000_000n, // 1 USDC
    99970n, // 0.03%
    99995n // 0.005%
  ],
  [false, USDC, WETH, 0, 15, 1, 1_000_000n, 1_000_000n, 99970n, 99995n],
  [true, USDC, "", 0, 13, 1, 1_000_000n, 1_000_000n, 99970n, 99995n],
  [true, USDC, "", 0, 2, 1, 1_000_000n, 1_000_000n, 99970n, 99995n],
  [true, USDC, "", 0, 5, 1, 1_000_000n, 1_000_000n, 99970n, 99995n],
  [true, USDC, "", 0, 4, 1, 100000n, 1_000_000n, 99990n, 100000n],
  [true, WETH, "", 0, 4, 1, 100000n, 100000000000000000n, 99990n, 100000n],
  [true, WETH, "", 0, 4, 1, 100000n, 100000000000000000n, 99990n, 100000n],
  [true, WETH, "", 0, 4, 1, 100000n, 100000000000000000n, 99990n, 100000n],
  [true, WETH, "", 2, 9, 1, 1_000_000_000_000_000n, 100000000000000000n, 99950n, 99995n],
  [true, WETH, "", 2, 9, 1, 1_000_000_000_000_000n, 100000000000000000n, 99950n, 99995n],
  [true, WETH, "", 2, 9, 1, 1_000_000_000_000_000n, 100000000000000000n, 99950n, 99995n],
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
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider)

  const Crystal = await hardhat.ethers.getContractFactory("Crystal")
  const crystalAddr = await deploy(Crystal, wallet, provider, [ // [WETH, Owner, Fee Recipient, Referral Commission (x/100), Fee Claim Duration (s), Launchpad Parameters: [Initial Native Supply, Launchpad Fee, Launchpad Creator Fee Split, Graduated Minimum Size, Graduated Taker Fee, Graduated Maker Rebate, Graduated Creator Fee Split]]
    WETH,
    wallet.address,
    wallet.address,
    10, // 10%
    86400, // 1 Day
    [1000000000000000000000n, 99000n, 10n, 1000000000000000000n, 99910n, 99995n, 40] // [1000, 1%, 10%, 1, 0.09%, 0.005%, 40%]
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
    3600, // 1 Hour
  ])

  console.log({
    crystal: crystalAddr,
    vaultFactory: vaultFactoryAddr,
    markets
  })
}

main().catch(e => { console.error(e); process.exit(1) })