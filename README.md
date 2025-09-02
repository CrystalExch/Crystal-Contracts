all user interaction goes through Crystal which delegatecalls the markets, the one exception is interacting with launchpad tokens and AMM LP tokens which are regular ERC-20 tokens

vault deposits/withdrawals should go through the vault factory

deposits into user operated vaults are non-transferable ERC-20s

assembly is used to emit the data from multiple user actions into a single log, each action is a bytes32

assembly is also used to reset the memory pointer to limit memory expansion

lots of logic is unchecked to save gas, overflow is never intentional and should never happen

in storage addressses are mapped to uint41 userIds to save space and allow the packing of orders into a single storage slot, registerUser assigns an Id

in the future a single address should support multiple userIds as margin subaccounts

delegatecall is so market parameters don't have to be loaded from storage, instead they are immutable

some variable names are no longer accurate after being reassigned to avoid stack too deep

assume the maximum contract limit is 128kb, as is the case on monad

a malicious user deployed ERC-20 should not be able to cause harm across markets

rebasing/fee on transfer tokens are not supported

price time priority should always hold true

there are probably a lot of rounding errors

MMs are expected to interact through the fallback endpoint

integrations are expected to interact through the default function endpoints

users are expected to interact through the router endpoints

important invariants: protocol stays solvent, specifying an input amount/output amount expends/yields the exact specified amount, price time priority, interacting with one market should never affect other markets, rounding dust towards the protocol is acceptable

things about the design we don't like:

use of canonical pairs to allow for swaps specifying token->token is weird architecture and shouldn't be part of the core protocol

referral param making the abi slightly different from univ2router

seperate tx to approve a forwarder, forwarder has to deposit/withdraw from router to use its own balances

forwarder can use transferfrom instead of only being allowed to place/cancel on behalf of user

entire math i have no idea how/why it works/doesn't

afaik some quoting on the quoter is slightly different from the ob execution bc of rounding

stored ob values/emitted values are in quote for buy and base for sell instead of base for both like cexs

sometimes division is early to avoid overflow but loses precision

batch orders/replace orders can only specify input/output behavior not quote/base behavior (whether to use the router balance or normal balance)

launchpad and router are together with the factory which isn't an idealistic permissionless protocol

governance param changes either require way too many methods or require adding already existing values

client order ids only go up to 1024, orders and users only go up to like a trillion or so

in general too many functions

some params are encoded as options instead of their own variables

variable naming is inaccurate when reused to avoid stack too deep

no space in the order object for different types of resting orders for example grid orders

bitmasks and variable sizes often aren't multiples of 8s

internal balance storage isn't carried over meaning extra sloads/sstores, as is amm reserves for limit orders

premint function honestly shouldn't exist