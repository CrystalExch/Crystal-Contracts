const hardhat = require("hardhat")
const { ethers } = require("ethers")
require("dotenv").config()

const RPC_URL = "https://rpc.monad.xyz"
const CHAIN_ID = 143 // Monad Mainnet
const GAS_PRICE = 150000000000n // 150 gwei

const USDC = "0xf817257fed379853cDe0fa4F97AB987181B1E5Ea"
const WETH = "0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701"

const MARKETS = [ // [Canonical, Quote Asset, Base Asset, Market Type, Scale Factor, Tick Size, Max Price, Min Size, Taker Fee, Maker Rebate]
  [true, USDC, WETH, 2, 21, 1, 1_000_000_000_000_000n, 1_000_000n, 99970n, 99995n],
  [false, USDC, WETH, 0, 15, 1, 1_000_000n, 1_000_000n, 99970n, 99995n],
  [true, USDC, "0xB5a30b0FDc5EA94A52fDc42e3E9760Cb8449Fb37", 0, 13, 1, 1_000_000n, 1_000_000n, 99970n, 99995n],
  [true, USDC, "0xcf5a6076cfa32686c0Df13aBaDa2b40dec133F1d", 0, 2, 1, 1_000_000n, 1_000_000n, 99970n, 99995n],
  [true, USDC, "0x5387C85A4965769f6B0Df430638a1388493486F1", 0, 5, 1, 1_000_000n, 1_000_000n, 99970n, 99995n],
  [true, USDC, "0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D", 0, 4, 1, 100000n, 1_000_000n, 99990n, 100000n],
  [true, WETH, "0xe1d2439b75fb9746E7Bc6cB777Ae10AA7f7ef9c5", 0, 4, 1, 100000n, 100000000000000000n, 99990n, 100000n],
  [true, WETH, "0xb2f82D0f38dc453D596Ad40A37799446Cc89274A", 0, 4, 1, 100000n, 100000000000000000n, 99990n, 100000n],
  [true, WETH, "0x3a98250F98Dd388C211206983453837C8365BDc1", 0, 4, 1, 100000n, 100000000000000000n, 99990n, 100000n],
  [true, WETH, "0x0F0BDEbF0F83cD1EE3974779Bcb7315f9808c714", 2, 9, 1, 1_000_000_000_000_000n, 100000000000000000n, 99950n, 99995n],
  [true, WETH, "0xE0590015A873bF326bd645c3E1266d4db41C4E6B", 2, 9, 1, 1_000_000_000_000_000n, 100000000000000000n, 99950n, 99995n],
  [true, WETH, "0xfe140e1dCe99Be9F4F15d657CD9b7BF622270C50", 2, 9, 1, 1_000_000_000_000_000n, 100000000000000000n, 99950n, 99995n],
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
    10,
    86400,
    [1000000000000000000000n, 99000n, 10n, 1000000000000000000n, 99910n, 99995n, 40]
  ])
  const crystal = new ethers.Contract(crystalAddr, Crystal.interface, wallet)

  const markets = []
  for (const params of MARKETS) {
    const predicted = await crystal.deploy.staticCall(...params)
    await call(crystal, wallet, provider, "deploy", params)
    markets.push(predicted)
  }

  const VaultFactory = await hardhat.ethers.getContractFactory("CrystalVaultFactory")
  const vaultFactoryAddr = await deploy(VaultFactory, wallet, provider, [
    crystalAddr,
    wallet.address,
    WETH,
    100,
    100,
    5n
  ])

  console.log({
    crystal: crystalAddr,
    vaultFactory: vaultFactoryAddr,
    markets
  })
}

main().catch(e => { console.error(e); process.exit(1) })