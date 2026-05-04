# Crystal

Crystal is a fully on-chain central limit order book exchange, created to bridge the gap between the transparency, security, and permissionless nature of decentralized exchanges and the speed, capital efficiency, and lower fees of traditional centralized exchanges. Built as an immutable protocol on the Ethereum Virtual Machine, Crystal allows for a seamless trading experience while remaining fully self-custodial, permissionless, and decentralized. Crystal is also fully composable and can serve as spot liquidity for any DeFi app as a substitute or addition to automatic market maker exchange liquidity.

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
| `248` | `isRequireSuccess` | `uint1` | `1` reverts whole batch on failure |
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

`npx hardhat test`

## License

Crystal is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
