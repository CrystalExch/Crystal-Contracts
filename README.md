# Crystal

[Crystal](https://crystal.exchange/whitepaper.pdf) is a fully on-chain central limit order book exchange, created to bridge the gap between the transparency, security, and permissionless nature of decentralized exchanges and the speed, capital efficiency, and lower fees of traditional centralized exchanges. Built as an immutable protocol on the Ethereum Virtual Machine, Crystal allows for a seamless trading experience while remaining fully self-custodial, permissionless, and decentralized. Crystal is also fully composable and can serve as spot liquidity for any DeFi app as a substitute or addition to automatic market maker exchange liquidity.

## Documentation

Crystal uses a singleton architecture, where all external methods and state live in the central exchange contract. In order to bring a protocol as complex as an orderbook to the blockchain, a couple optimizations have been made.

### Memory

Notably, Crystal manually reserves memory to store intermediary variables and emit events during the order matching process. The schema used is outlined here:

| Offset | Field                         | Description                                                                                     |
| ------ | ----------------------------- | ----------------------------------------------------------------------------------------------- |
| 0x00   | Scratch                       | Used by Solidity                                                                                |
| 0x20   | Scratch                       | Used by Solidity                                                                                |
| 0x40   | Free memory pointer           | Set to 0x100, Solidity default is 0x80                                                          |
| 0x60   | Original exact input buy size | Preserves original input size for market-to-limit orders                                        |
| 0x80   | Trade event price             | High 128 bits = start price, low 128 bits = end price                                           |
| 0xa0   | AMM reserves                  | High 128 bits = reserveQuote, low 128 bits = reserveBase                                        |
| 0xc0   | Referrer address              | Optional field applicable only to market orders                                                 |
| 0xe0   | OrdersUpdated event length    | Tracks the number of 32-byte order updates to be emitted                                        |
| 0x100  | OrdersUpdated event data      | Free memory pointer is moved after this region                                                  |

### Storage

Additionally, Crystal packs multiple values into singular storage slots to represent state such as price levels and resting orders in order to save gas. These slots are made consecutive to take advantage of [MIP-8](https://github.com/monad-crypto/MIPs/blob/main/MIPS/MIP-8.md), making so that storage slots within a consecutive 128-slot page share warm access.

The storage helpers in [`CrystalStorage.sol`](./contracts/libraries/CrystalStorage.sol) expose three namespaced regions:

| Namespace | Constant | Purpose |
| --------- | -------- | ------- |
| `ORDERS_KEY` | `0x100` | Both cloid and non-cloid resting limit orders |
| `PRICELEVELS_KEY` | `0x200` | Packed per-price liquidity state and first-level activated tick bitmaps |
| `GROUPS_KEY` | `0x300` | Second-level bitmap tracking which first-level bitmap words are non-empty |

Within those namespaces, Crystal uses packed words rather than one-slot-per-field storage:

| Packed word | Bits | Meaning |
| ----------- | ---- | ------- |
| Order | `0..111` | Remaining size |
| Order | `112` | Balance mode flag |
| Order | `113..153` | Owner `userId` |
| Order | `154..204` | `fillBefore` pointer |
| Order | `205..255` | `fillAfter` pointer |
| Verify cloid | `0..79` | Odd cloid price |
| Verify cloid | `80..127` | Odd cloid market id |
| Verify cloid | `128..207` | Even cloid price |
| Verify cloid | `208..255` | Even cloid market id |
| Price level | `0..111` | Total resting liquidity at that price |
| Price level | `113..153` | Latest native order id |
| Price level | `154..204` | Latest resting order pointer |
| Price level | `205..255` | `fillNext` pointer |

Orders are addressed in two ways:

- Native orders are keyed by `marketId | (price << 48) | (id >> 7)` with `id & 127` used as the page-local offset.
- Cloid orders are keyed by `userId << 128 | (((cloid - 1) >> 1) / 42)` with the offset selecting one of the packed order or verification words for that cloid pair.

For cloid-backed orders, storage is intentionally laid out as repeating triplets where `n = ((cloid - 1) >> 1) % 42`:

| Local offset pattern | Meaning |
| -------------------- | ------- |
| `3n + 0` | Odd cloid order word |
| `3n + 1` | Even cloid order word |
| `3n + 2` | Shared cloid verification word |

In other words, the physical layout is:

`order, order, verifyCloid, order, order, verifyCloid, ...`

Each cloid pair shares one verification word that stores the market and price metadata for both cloids, while the two adjacent order words store the packed order state. The key buckets cloIds in groups of `42` pairs, so each bucket consumes `42 * 3 = 126` consecutive storage words and fits within a single warm 128-slot page.

The namespaced storage helpers use the pattern:

`keccak256(abi.encode(key, slot)) + offset`

The `key` and namespace `slot` are hashed once to find the base page, while `offset` is added afterwards rather than included in the hash. This is what allows Crystal to walk through consecutive storage words inside the same page and benefit from warm page access instead of paying for a fresh mapping hash on every neighboring word.

Active price discovery is also hierarchical:

- Price levels are arranged in a linear sequence where every `255` price-level words are followed by `1` first-level bitmap word.
- Importantly, price levels are stored by their corresponding tick, where consecutive ticks are defined as the closest valid price levels.
- The price-level index uses `tick + floor(tick / 255)`, which is equivalent to `(tick << 8) / 255`, so an extra bitmap word is inserted every 255 prices.

Each first-level bitmap word stores 255 bits and indicates which of those 255 price levels currently contain resting liquidity. Conceptually, the first layer looks like this:

`255 price levels -> 1 activated bitmap -> 255 price levels -> 1 activated bitmap -> ...`

A second-level bitmap word tracks which first-level bitmap words are non-empty:

- bit `i` in a groups word means first-level bitmap word `i` for that market range is non-empty
- when a first-level bitmap becomes empty, its corresponding bit in the groups layer is cleared
- when a first-level bitmap becomes non-empty, its corresponding bit in the groups layer is set

To find the next active price level when both the second-level and first-level activated slots are empty, `_searchUp` and `_searchDown` iterate across the second-level bitmap until they find an active group, then find the correct first-level activated slot by finding the closest nonzero bit. The same process is repeated within the first-level activated slot where the closest nonzero bit is found, which corresponds to the tick of the next active price level. If either the second-level or first-level activated slots are non-empty to begin with, the process starts with finding the next active bit within the lowest level non-empty bitmap.

### Fallback

The fallback function is gas-optimized and intended for use by market makers and other high frequency automated trading strategies. By default, msg.sender is used in place of all address parameters for each action. Calldata is a sequence of market batches:

```text
calldata = batch0 || batch1 || batch2 || ...
```

Each batch is:

```text
batch = batchHeader || action0 || action1 || ... || actionN
```

There is no function selector.

#### Batch Header

Each batch starts with one 32-byte word.

| Bits | Field | Type | Notes |
| --- | --- | --- | --- |
| `0..159` | `market` | `address` | target market |
| `160..171` | `actionCount` | `uint12` | number of 32-byte action words that follow |
| `172..251` | `bid` | `uint80` | optional priority bid sent to `block.coinbase` |
| `252..255` | `balanceMode` | `uint4` | currently expected to be `0` or `1` |

#### Batch Header Formula

```text
batchHeader =
    uint160(market)
    | (actionCount << 160)
    | (bid << 172)
    | (balanceMode << 252)
```

#### Balance Modes

- `0`: external settlement
- `1`: internal settlement

When `Crystal.sol` delegates into `CrystalMarket.sol`, it automatically rebuilds the inner header as:

```text
marketHeader = userId | (balanceMode << 44)
```

So when calling `Crystal.sol` fallback, you do not encode `userId` yourself in calldata. `Crystal.sol` loads the caller's `userId` from storage and injects it.

#### Action Word

Each action is still one 32-byte word.

| Bits | Field | Type | Notes |
| --- | --- | --- | --- |
| `0..111` | `param2` | `uint112` | meaning depends on action |
| `112..191` | `param1` | `uint80` | meaning depends on action |
| `192..201` | `cloid` | `uint10` | client order id |
| `202..247` | unused | - | set to `0` |
| `248` | `isRequireSuccess` | `uint1` | `1` reverts whole batch on failure (a failed complete fill market order will always revert the entire batch) |
| `249..251` | unused | - | set to `0` |
| `252..255` | `action` | `uint4` | action code |

#### Generic Action Formula

```text
word =
    param2
    | (param1 << 112)
    | (cloid << 192)
    | (isRequireSuccess << 248)
    | (action << 252)
```

#### Action Codes

| Code | Meaning |
| --- | --- |
| `1` | cancel order |
| `2` | limit buy |
| `3` | limit sell |
| `4` | market-to-limit buy |
| `5` | market-to-limit sell |
| `6` | partial buy |
| `7` | partial sell |
| `8` | partial buy, gas-aware |
| `9` | partial sell, gas-aware |
| `10` | complete buy |
| `11` | complete sell |
| `12` | decrease order |

#### `1` Cancel Order

Cancel by native order id:

| Field | Value |
| --- | --- |
| `param1` | `price` |
| `param2` | `id` |
| `cloid` | `0` |

Cancel by cloid:

| Field | Value |
| --- | --- |
| `param1` | `0` |
| `param2` | `0` |
| `cloid` | client order id |

#### `2` Limit Buy

| Field | Value |
| --- | --- |
| `param1` | `price` |
| `param2` | `size` |
| `cloid` | optional client order id |

#### `3` Limit Sell

| Field | Value |
| --- | --- |
| `param1` | `price` |
| `param2` | `size` |
| `cloid` | optional client order id |

#### `4` to `11` Market-Style Orders

| Field | Value |
| --- | --- |
| `param1` | `worstPrice` |
| `param2` | `size` |
| `cloid` | optional client order id |

Meanings:

| Code | Meaning |
| --- | --- |
| `4` | market-to-limit buy |
| `5` | market-to-limit sell |
| `6` | partial buy |
| `7` | partial sell |
| `8` | partial buy, gas-aware |
| `9` | partial sell, gas-aware |
| `10` | complete buy |
| `11` | complete sell |

#### `12` Decrease Order

Decrease by native order id:

| Field | Value |
| --- | --- |
| `param1` | `price` |
| bits `192..232` | native order `id` (`uint41`) |
| `param2` | `decreaseAmount` |

Decrease by cloid:

| Field | Value |
| --- | --- |
| `param1` | `0` |
| bits `192..201` | `cloid` |
| `param2` | `decreaseAmount` |

#### Limits

| Field | Size |
| --- | --- |
| `actionCount` | `uint12` |
| `bid` | `uint80` |
| `cloid` | `uint10` |
| `param1` | `uint80` |
| `param2` | `uint112` |
| native order `id` | `uint41` |

All unused bits should be zeroed.

Crystal does not support non-standard ERC-20 tokens, including fee-on-transfer tokens and tokens that do not revert on failure.

Further documentation is available at [docs.crystal.exchange](https://docs.crystal.exchange)

## Repository Structure

[`Crystal.sol`](./contracts/core/Crystal.sol) is the central exchange contract at the heart of the Crystal protocol.
Additional components of the core protocol can be found in the [`contracts/core`](./contracts/core) folder.

Contracts enabling the permissionless creation of liquidity vaults on top of the Crystal protocol can be found in the [`contracts/vaults`](./contracts/vaults) folder.
This displays one of the many use-cases enabled by composability.

Crystal does not rely on any external dependencies or libraries. All code is original with the exception of the standard ERC20 token found in the [`contracts/libraries`](./contracts/libraries) directory.

The [`contracts/mocks`](./contracts/mocks) directory contains contracts solely built for testing.

Interfaces for interacting with the Crystal protocol can be found in the [`contracts/interfaces`](./contracts/interfaces) folder.

## Install Dependencies

If npx is not installed yet:
`npm install -g npx`

Install packages:
`npm i`

## Compile Contracts

`npx hardhat compile`

## Run Tests

In addition to formal security audits, Crystal uses multiple testing frameworks in order to minimize the probability of a vulnerability being present in the codebase:

- 99% unit test coverage via Hardhat
- Stateful invariant tests via Foundry
- Stateless fuzz tests via Foundry
- Advanced fuzzing configuration via Echidna and Medusa

```bash
npx hardhat test
npm run test:foundry
npm run coverage
npm run fuzz:echidna
npm run fuzz:medusa
```

## Protocol Invariants

A non-exhaustive list of protocol invariants that should be satisfied at all times:

### Governance and Registry

- Governance authorization must be exclusive to governance or authorized canonical deployers for privileged configuration, canonical market deployment, and routing updates. Governance actions must not seize user funds, rewrite resting orders, or mutate user balances outside documented fee/configuration flows.
- Governance state must remain synchronized with the active governance account. `crystal.gov()` should always equal the account expected to control privileged actions.
- Registered users must roundtrip through the compact user ID registry. For every registered account, `userIdToAddress(addressToUserId(account))` should return the original account, and no account should resolve to a user ID greater than `latestUserId`.

### Internal Balances

- Exchange ledger accounting must conserve balances. For every `(user, token)`, `total == available + locked`, and locked value must be attributable to active orders or liquidity. Neither available nor locked balance may exceed total balance.
- ERC20 and native deposits must increase `total` and `available` by the deposited amount, leave the deposited amount unlocked, and register the user exactly once.
- Withdrawals must decrease `total` and `available` by the withdrawn amount, transfer the same asset to the recipient, unwrap native ETH when requested, and never spend locked balance.
- Buy limit orders must lock quote asset, sell limit orders must lock base asset, and neither side may change the user's total deposited balance.
- Canceling or decreasing an order must release exactly the reduced locked collateral back to available balance.
- Fills must conserve value across maker, taker, and fee accounting: maker locked input decreases, maker output increases, taker input decreases, taker output increases, and protocol/referral/creator fee accounting explains any spread.

### Market Reserves and Metadata

- Market configuration must remain stable after creation. Quote asset, base asset, scale factor, tick size, max price, and minimum size must continue to match the configured market.
- Reserve views must agree after adds, swaps, and removals. `getReserves(market)` and `getMarket(market).reserveQuote/reserveBase` should report the same quote and base reserves.
- Reported AMM reserves must be backed by real assets held by `Crystal`; reserves may not exceed the protocol's actual quote and base token balances.
- Market index views must remain valid. Market lists should contain nonzero markets, and token-pair routing should resolve to the expected active market.

### Orderbook

- Resting limit orders may only exist at valid market ticks, with `price > 0`, `price < maxPrice`, `price % tickSize == 0`, and size satisfying the market minimum in the correct denomination.
- The primary book must never remain crossed. If both sides of the book exist, `highestBid < lowestAsk`; otherwise executable liquidity was left unmatched.
- Market buys must consume the lowest ask before higher asks, and market sells must consume the highest bid before lower bids.
- Orders at the same price must fill by time priority: older resting orders fill before newer resting orders.
- Limit orders must execute at the specified price or better, never worse, and maker orders must not pay taker fees.
- Market orders must stop at `worstPrice`; complete-fill orders must revert without mutation if constraints cannot be satisfied; partial-fill orders must cancel the unfilled remainder.
- Market-to-limit orders must consume executable liquidity up to the limit price, then rest any remaining quantity as a limit order on the same side at that limit price.
- Live tracked orders must match on-chain storage, and aggregate price-level liquidity must cover live orders resting at that price.
- Client order IDs must stay in `1..1023`, be unique while active for a user, be cancelable/decreaseable by CLOID, and be reusable after cancellation or fill. CLOID list views and single-order views must agree.
- Replacing a partially filled order must move only remaining liquidity to the new price and must not resurrect filled quantity.

### Price and Quote Views

- `getPrice`, `getPriceLevels`, and `getPriceLevelsFromMid` must return active levels that are bounded, sorted in the requested direction, and consistent with direct `getPriceLevel` values.
- For fixed state and inputs, `getQuote(...)` must predict the next successful `marketOrder(...)` within explicit rounding tolerance and must not mutate state.
- `getAmountsOut` and `getAmountsIn` must match direct market quotes for each valid full-fill hop and must not mutate state. Partial-fill path quotes must not be treated as exact execution guarantees.

### Vaults

- Initial vault share supply must equal `sqrt(amountQuote * amountBase)`, and the owner must receive exactly that supply.
- Follow-on vault deposits must mint proportional shares and consume only the proportional quote/base amounts.
- `previewDeposit` and `previewWithdrawal` must equal the next successful deposit/withdrawal result, be caller-independent, and be non-mutating.
- Vault `totalSupply`, user share balances, and factory `totalShares` must stay synchronized across deposits, withdrawals, and close.
- A user who deposits into a vault and withdraws the received shares should not end with more quote or base than before, absent external fills or fees.
- Vault shares must be non-transferable, even after approval.
- Withdrawals before `unlockTimestamp` must revert; withdrawals at or after lockup must return previewed assets.
- Vault buy and sell limit orders must lock collateral owned by the vault address and must not directly mutate depositor wallets.
- Active-order withdrawal behavior must follow `decreaseOnWithdraw`: active orders are reduced proportionally or only by needed locked liquidity according to the vault setting.
- Vault risk parameters must respect owner and factory-wide bounds, including `maxShares`, `orderCap`, `lockup`, and owner minimum stake constraints. Unsafe deposits or operator actions must reject without moving funds.
- Closing a vault must return all previewed assets to the owner, burn all shares, set `closed == true`, and leave no factory total shares.
- Vault actions must use the same exchange interface, fees, constraints, and order semantics as any other account.

### Fees and Rewards

- Taker fees, maker rebates, referral commission, creator commission, and protocol rewards must not exceed the taker notional fee budget unless explicitly funded.
- Fee and rebate parameter updates must respect protocol bounds and must not mutate existing orders or user balances by configuration change alone.
- Claiming fees must transfer exactly claimable amounts, clear claimed rewards, and keep claimable liabilities backed by assets held by `Crystal`. Expired-fee execution must only succeed after its deadline.

### AMM and Liquidity

- Initial AMM liquidity must mint `sqrt(amountQuote * amountBase)` LP shares and set reserves to the deposited amounts.
- Exact-input AMM swaps must preserve the reserve product lower bound, with `reserveQuoteAfter * reserveBaseAfter >= reserveQuoteBefore * reserveBaseBefore`, while moving reserves in the expected direction.
- Removing LP liquidity must burn exactly the requested liquidity and return quote/base amounts greater than the specified minimums.
- When both book and AMM liquidity are available, execution should use the lower effective marginal price source, subject to slippage and maker rebate rules.
- Add-liquidity-only orders that cross AMM-implied executable liquidity must revert or leave reserves unchanged according to the documented mode.

### Batching, Fallback, and Router

- If a batch action marked `isRequireSuccess == true` fails, all prior successful actions in the same batch must roll back.
- If a batch action marked `isRequireSuccess == false` fails, later valid actions may still execute and earlier successful optional actions should remain.
- Multi-batch and multi-market calls must settle atomically at the transaction boundary, including netted settlement and rollback on required failure.
- Fallback calldata action words must decode to the same semantic operations as structured `batchOrders` actions for limit, cancel, market, and decrease flows.
- Fallback internal-balance mode must debit and lock deposited balances instead of taking a fresh wallet transfer, while preserving `total == available + locked`.
- Router exact-input and exact-output swaps must enforce deadline and slippage, transfer outputs to `to`, and support ERC20/native sentinel paths.
- Invalid paths or missing markets must revert without changing balances, reserves, or orderbook state.
- `routerDeposit` and `routerWithdraw` must use the same exchange ledger slots as direct deposit/withdraw and preserve native wrap/unwrap semantics.

### Launchpad

- `createToken` must initialize token metadata, virtual reserves, `k`, creator, market mapping, and token registry consistently.
- Launchpad virtual reserves must be internally consistent: both reserves should be zero or both nonzero.
- Launchpad buys and sells must move virtual native/token reserves in opposite directions while preserving bonding-curve constraints and the constant-product lower bound.
- `quoteBuy` and `quoteSell` must predict `buy` and `sell` for exact-input and exact-output modes within explicit rounding tolerance, bound outputs by available virtual reserves, and avoid mutating virtual reserves.
- Launchpad token metadata must remain valid, with nonempty name, nonempty symbol, 18 decimals, and nonzero total supply. `Crystal` must not hold more of a launchpad token than the token total supply.

### Token and Event Surfaces

- Market LP token `transferFrom` must update balances and finite allowances exactly, while max allowance must not be decremented.
- Market LP token `mint` and `burn` must be callable only by `Crystal`; authorized mint/burn must change balance and total supply by the same amount.
- Deposits, withdrawals, placements, cancellations, fills, mints, burns, and syncs must emit enough data to reconstruct account and market state from the exchange address.
- Structured and fallback batches must emit order/fill events whose aggregate deltas match post-execution view snapshots.

## Deploy Contracts

Crystal includes two deployment scripts:

- `scripts/deploy.js` deploys the core `Crystal` contract, the configured markets, and `CrystalVaultFactory`.
- `scripts/deployMarket.js` deploys additional markets against an existing `Crystal` deployment.

Before deploying the smart contracts, create a `.env` file in the root directory with the following configuration:

```env
PRIVATE_KEY=0x...
RPC_URL=https://rpc.monad.xyz
CHAIN_ID=143
GAS_PRICE=150000000000
USDC=0x754704Bc059F8C67012fEd69BC8A327a5aafb603
WETH=0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A
CRYSTAL_ADDRESS=0x...
```

Variable definitions:

- `PRIVATE_KEY`: deployer key. Required for both scripts.
- `RPC_URL`: JSON-RPC endpoint. Defaults to Monad mainnet RPC.
- `CHAIN_ID`: chain id used for manual transaction signing. Defaults to `143`.
- `GAS_PRICE`: gas price used by the deployment scripts. Defaults to `150000000000` wei.
- `USDC`: quote token address used by the example market configs.
- `WETH`: wrapped native token address used by the core deployment script.
- `CRYSTAL_ADDRESS`: existing Crystal deployment address. Required only for `deployMarket.js`.

```bash
npx hardhat run scripts/deploy.js
```

- deploys `Crystal`
- deploys the default markets listed in [`scripts/deploy.js`](./scripts/deploy.js)
- deploys `CrystalVaultFactory`
- logs the deployed `crystal`, `vaultFactory`, and individual market addresses

```bash
npx hardhat run scripts/deployMarket.js
```

- reads `CRYSTAL_ADDRESS` from `.env`
- deploys any additional markets listed in [`scripts/deployMarket.js`](./scripts/deployMarket.js)
- logs the deployed market addresses

To customize deployment parameters, edit the `MARKETS` arrays in [`scripts/deploy.js`](./scripts/deploy.js) or [`scripts/deployMarket.js`](./scripts/deployMarket.js). The market tuple format is:

```text
[canonical, quoteAsset, baseAsset, marketType, scaleFactor, tickSize, maxPrice, minSize, takerFee, makerRebate]
```

The core deployment script also hardcodes `Crystal` constructor parameters, launchpad parameters, and `CrystalVaultFactory` constructor parameters in [`scripts/deploy.js`](./scripts/deploy.js)

## License

Crystal is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
