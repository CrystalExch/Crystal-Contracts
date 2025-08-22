Crystal.sol contains router, launchpad, referral manager (not important), settings, 3 factories for 3 different market types which are largely the same code (static tick without amm, dynamic tick with amm, dynamic tick with amm, creator fee split, and pre-initialization of liquidity by launchpad)

all user interaction goes through Crystal.sol which delegatecalls the markets, the one exception is interacting with launchpad tokens and AMM LP tokens which are regular ERC-20 tokens

CrystalVault.sol contains vault factory + user operated vaults, deposits/withdrawals should go through the vault factory

deposits into user operated vaults are non-transferable ERC-20s, the use of totalShares currently is incorrect

will add margin + margin vault before deployment as well as trigger/twap orders with functions that have not been filled in

assembly is used to emit the data from multiple user actions into a single log, each action is a bytes32

assembly is also used to reset the memory pointer to limit memory expansion

lots of logic is unchecked to save gas, overflow is never intentional

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

Integrations are expected to interact through the default function endpoints

Users are expected to interact through the router endpoints

important invariants: protocol stays solvent, specifying an input amount/output amount expends/yields the exact specified amount, price time priority, interacting with one market should never affect other markets, rounding dust towards the protocol is acceptable

known issue:
call to registerUser() from markets has the protocol as msg.sender, either delegate call or forward the actual caller
