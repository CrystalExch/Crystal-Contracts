// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from '../interfaces/IERC20.sol';

interface IVaultFactory {
    function deposit(address vault, address quoteAsset, address baseAsset, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external payable returns (uint256 shares, uint256 amountQuote, uint256 amountBase);
    function withdraw(address vault, address quoteAsset, address baseAsset, uint256 shares, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase);
}

struct Action {
    bool isRequireSuccess;
    uint256 action;
    uint256 param1;
    uint256 param2;
    uint256 param3;
}

struct Batch {
    address market;
    Action[] actions;
    uint256 options;
}

interface ICrystal {
    function addLiquidity(address market, address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external payable returns (uint256 amountQuote, uint256 amountBase, uint256 liquidity);
    function removeLiquidity(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase);
    function removeLiquidityETH(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase);
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts);
    function swapExactETHForTokens(uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external payable returns (uint256[] memory amounts);
    function swapETHForExactTokens(uint256 amountOut, address[] memory path, address to, uint256 deadline, address referrer) external payable returns (uint256[] memory amounts);
    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts);
    function swap(bool isExactInput, address tokenIn, address tokenOut, uint256 orderType, uint256 size, uint256 worstPrice, uint256 deadline, address referrer) external payable returns (uint256 userId, uint256 balance, uint256 id);
    function batchOrders(address market, Action[] calldata actions, uint256 options, uint256 deadline, address referrer, address user) external payable;
    function multiBatchOrders(Batch[] calldata batches, uint256 deadline, address referrer) external payable;
    function deposit(address token, uint256 amount) external payable returns (uint256 userId);
    function withdraw(address to, address token, uint256 amount) external;
    function claimFees(address to, address[] calldata tokens) external returns (uint256[] memory amounts);
    function addClaimableFee(address to, address[] calldata tokens, uint256[] calldata amounts) external payable;
    function routerDeposit(address token, uint256 amount) external payable;
    function routerWithdraw(address to, address token, uint256 amount) external;
    function sell(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external returns (uint256, uint256);
    function buy(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external payable returns (uint256, uint256, bool);
}

/// @notice Contract that rejects ETH transfers - used for testing ETH transfer failure branches
contract ETHRejecter {
    function approveToken(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }

    function depositToVault(
        address factory,
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 amountQuote,
        uint256 amountBase
    ) external payable {
        IVaultFactory(factory).deposit{value: msg.value}(
            vault, quoteAsset, baseAsset, amountQuote, amountBase, 0, 0
        );
    }

    function withdrawFromVault(
        address factory,
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 shares
    ) external {
        // Transfer shares to this contract first if needed
        IVaultFactory(factory).withdraw(vault, quoteAsset, baseAsset, shares, 0, 0);
    }

    // Crystal functions for testing TransferFailed branches
    function addLiquidityCrystal(
        address crystal,
        address market,
        uint256 amountQuote,
        uint256 amountBase
    ) external payable {
        // Note: This will revert if there's excess ETH to refund, which is what we want to test
        ICrystal(crystal).addLiquidity{value: msg.value}(market, address(this), amountQuote, amountBase, 0, 0);
    }

    function addLiquidityETHCrystal(
        address crystal,
        address market,
        uint256 amountQuote,
        uint256 amountBase
    ) external payable {
        // Used to test addLiquidity ETH refund failure (line 696)
        ICrystal(crystal).addLiquidity{value: msg.value}(market, address(this), amountQuote, amountBase, 0, 0);
    }

    function removeLiquidityETHCrystal(
        address crystal,
        address market,
        uint256 liquidity
    ) external {
        ICrystal(crystal).removeLiquidityETH(market, address(this), liquidity, 0, 0);
    }

    function swapExactTokensForETHCrystal(
        address crystal,
        uint256 amountIn,
        address[] memory path,
        uint256 deadline
    ) external {
        ICrystal(crystal).swapExactTokensForETH(amountIn, 0, path, address(this), deadline, address(0));
    }

    function swapTokensForExactETHCrystal(
        address crystal,
        uint256 amountOut,
        uint256 amountInMax,
        address[] memory path,
        uint256 deadline
    ) external {
        ICrystal(crystal).swapTokensForExactETH(amountOut, amountInMax, path, address(this), deadline, address(0));
    }

    function batchOrdersCrystal(
        address crystal,
        address market,
        Action[] calldata actions,
        uint256 options,
        uint256 deadline
    ) external payable {
        ICrystal(crystal).batchOrders{value: msg.value}(market, actions, options, deadline, address(0), address(this));
    }

    function multiBatchOrdersCrystal(
        address crystal,
        Batch[] calldata batches,
        uint256 deadline
    ) external payable {
        ICrystal(crystal).multiBatchOrders{value: msg.value}(batches, deadline, address(0));
    }

    function depositCrystal(
        address crystal,
        address token,
        uint256 amount
    ) external payable {
        ICrystal(crystal).deposit{value: msg.value}(token, amount);
    }

    function withdrawCrystal(
        address crystal,
        address token,
        uint256 amount
    ) external {
        ICrystal(crystal).withdraw(address(this), token, amount);
    }

    function claimFeesCrystal(
        address crystal,
        address[] calldata tokens
    ) external {
        ICrystal(crystal).claimFees(address(this), tokens);
    }

    function routerWithdrawCrystal(
        address crystal,
        address token,
        uint256 amount
    ) external {
        ICrystal(crystal).routerWithdraw(address(this), token, amount);
    }

    function callSwap(
        address crystal,
        bool isExactInput,
        address tokenIn,
        address tokenOut,
        uint256 orderType,
        uint256 size,
        uint256 worstPrice,
        uint256 deadline,
        address referrer
    ) external payable {
        ICrystal(crystal).swap{value: msg.value}(isExactInput, tokenIn, tokenOut, orderType, size, worstPrice, deadline, referrer);
    }

    function sellCrystal(
        address crystal,
        bool isExactInput,
        address token,
        uint256 amountIn,
        uint256 amountOut
    ) external {
        ICrystal(crystal).sell(isExactInput, token, amountIn, amountOut);
    }

    function buyCrystal(
        address crystal,
        bool isExactInput,
        address token,
        uint256 amountIn,
        uint256 amountOut
    ) external payable {
        ICrystal(crystal).buy{value: msg.value}(isExactInput, token, amountIn, amountOut);
    }

    // No receive() or fallback() - will reject ETH transfers
}

/// @notice Contract that can toggle ETH rejection - accepts ETH during deposit, rejects during withdraw
contract ETHToggler {
    bool public rejectETH;

    function setRejectETH(bool _reject) external {
        rejectETH = _reject;
    }

    function approveToken(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }

    function depositToVault(
        address factory,
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 amountQuote,
        uint256 amountBase
    ) external payable {
        IVaultFactory(factory).deposit{value: msg.value}(
            vault, quoteAsset, baseAsset, amountQuote, amountBase, 0, 0
        );
    }

    function withdrawFromVault(
        address factory,
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 shares
    ) external {
        IVaultFactory(factory).withdraw(vault, quoteAsset, baseAsset, shares, 0, 0);
    }

    receive() external payable {
        require(!rejectETH, "ETH rejected");
    }
}

/// @notice Contract that attempts reentrancy attack on VaultFactory
contract ReentrancyAttacker {
    address public factory;
    address public vault;
    address public quoteAsset;
    address public baseAsset;
    bool public attacked;
    bool public reenterSucceeded;
    uint8 public reenterAction; // 1 = deposit, 2 = withdraw
    uint256 public reenterAmountQuote;
    uint256 public reenterAmountBase;
    uint256 public reenterShares;

    function setup(address _factory, address _vault, address _quoteAsset, address _baseAsset) external {
        factory = _factory;
        vault = _vault;
        quoteAsset = _quoteAsset;
        baseAsset = _baseAsset;
    }

    function setReenter(uint8 action, uint256 amountQuote, uint256 amountBase, uint256 shares) external {
        reenterAction = action;
        reenterAmountQuote = amountQuote;
        reenterAmountBase = amountBase;
        reenterShares = shares;
    }

    function approveToken(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }

    function attackDepositReentrancy(uint256 amountQuote, uint256 amountBase) external payable {
        attacked = false;
        reenterSucceeded = false;
        IVaultFactory(factory).deposit{value: msg.value}(
            vault, quoteAsset, baseAsset, amountQuote, amountBase, 0, 0
        );
    }

    function attackWithdrawReentrancy(uint256 shares) external {
        attacked = false;
        reenterSucceeded = false;
        IVaultFactory(factory).withdraw(vault, quoteAsset, baseAsset, shares, 0, 0);
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            if (reenterAction == 1) {
                // Try to reenter deposit during ETH refund callback
                try IVaultFactory(factory).deposit{value: msg.value}(
                    vault, quoteAsset, baseAsset, reenterAmountQuote, reenterAmountBase, 0, 0
                ) {
                    reenterSucceeded = true;
                } catch {}
            } else if (reenterAction == 2) {
                // Try to reenter withdraw during ETH transfer callback
                uint256 shares = reenterShares;
                if (shares == 0) {
                    shares = IERC20(vault).balanceOf(address(this));
                }
                if (shares != 0) {
                    try IVaultFactory(factory).withdraw(
                        vault, quoteAsset, baseAsset, shares, 0, 0
                    ) {
                        reenterSucceeded = true;
                    } catch {}
                }
            }
        }
    }
}

/// @notice Contract that attempts reentrancy attacks against Crystal core functions
contract CrystalReentrancyAttacker {
    address public crystal;
    address public token;
    bool public attacked;
    bool public reenterSucceeded;
    uint8 public reenterAction; // 1 = withdraw, 2 = routerWithdraw
    uint256 public reenterAmount;
    bytes[] private reenterCalldata;

    function setup(address _crystal, address _token) external {
        crystal = _crystal;
        token = _token;
    }

    function depositCrystal(uint256 amount) external payable {
        ICrystal(crystal).deposit{value: msg.value}(token, amount);
    }

    function routerDepositCrystal(uint256 amount) external payable {
        ICrystal(crystal).routerDeposit{value: msg.value}(token, amount);
    }

    function attackWithdraw(uint256 amount, uint8 action, uint256 amountReenter) external {
        attacked = false;
        reenterSucceeded = false;
        reenterAction = action;
        reenterAmount = amountReenter;
        ICrystal(crystal).withdraw(address(this), token, amount);
    }

    function attackRouterWithdraw(uint256 amount, uint8 action, uint256 amountReenter) external {
        attacked = false;
        reenterSucceeded = false;
        reenterAction = action;
        reenterAmount = amountReenter;
        ICrystal(crystal).routerWithdraw(address(this), token, amount);
    }

    function setReenterCalldata(bytes[] calldata data) external {
        delete reenterCalldata;
        for (uint256 i = 0; i < data.length; ++i) {
            reenterCalldata.push(data[i]);
        }
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            if (reenterCalldata.length != 0) {
                for (uint256 i = 0; i < reenterCalldata.length; ++i) {
                    (bool success, ) = crystal.call(reenterCalldata[i]);
                    if (success) {
                        reenterSucceeded = true;
                    }
                }
            } else {
                if (reenterAction == 1) {
                    try ICrystal(crystal).withdraw(address(this), token, reenterAmount) {
                        reenterSucceeded = true;
                    } catch {}
                } else if (reenterAction == 2) {
                    try ICrystal(crystal).routerWithdraw(address(this), token, reenterAmount) {
                        reenterSucceeded = true;
                    } catch {}
                }
            }
        }
    }
}
