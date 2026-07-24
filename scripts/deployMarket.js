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

const MARKETS = [ // [Canonical, Quote Asset, Base Asset, Market Type, Scale Factor, Tick Size, Max Price, Min Size, Taker Fee, Maker Rebate]
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
  const crystalAddress = envOrDefault("CRYSTAL_ADDRESS")
  if (!crystalAddress) throw new Error("CRYSTAL_ADDRESS is required")
  const crystal = new ethers.Contract(crystalAddress, Crystal.interface, wallet)

  const markets = []
  for (const params of MARKETS) {
    const predicted = await crystal.deploy.staticCall(...params)
    await call(crystal, wallet, provider, "deploy", params)
    markets.push(predicted)
  }

  console.log({
    markets
  })
}

main().catch(e => { console.error(e); process.exit(1) })
