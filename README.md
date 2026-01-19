# Crystal

Crystal is a fully on-chain central limit order book exchange, created to bridge the gap between the transparency, security, and permissionless nature of decentralized exchanges and the speed, capital efficiency, and lower fees of traditional centralized exchanges. Built as an immutable protocol on the Ethereum Virtual Machine, Crystal allows for a seamless trading experience while remaining fully self-custodial, permissionless, and decentralized. Crystal is also fully composable and can serve as spot liquidity for any DeFi app as a substitute or addition to automatic market maker exchange liquidity.

## Documentation

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