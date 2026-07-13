// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Malicious market for testing edge cases in Crystal.sol.
/// @dev This contract mimics CrystalMarket but doesn't update tokenBalances
/// When called via delegatecall, this causes balance checks to fail with ActionFailed.
contract MaliciousMarket {
    /// @notice getQuote - selector 0x638571e3.
    /// @dev Returns quote for a swap. Always returns 1:1 ratio.
    function getQuote(
        bool isBuy,
        bool isExactInput,
        bool useInternalBalance,
        uint256 size,
        uint256 worstPrice
    ) external pure returns (uint256 inputAmount, uint256 outputAmount) {
        // Always return 1:1 ratio - simple behavior for testing
        inputAmount = size;
        outputAmount = size;
    }

    /// @notice marketOrder - selector 0xe690552b.
    /// @dev Executes a market order. Returns values but doesn't update tokenBalances
    /// This causes ActionFailed when Crystal checks balances post-swap.
    function marketOrder(
        bool isBuy,
        bool isExactInput,
        uint256 options,
        uint256 orderType,
        uint256 size,
        uint256 worstPrice,
        address referrer,
        address user
    ) external payable returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        // Return claimed amounts but don't actually credit tokens to tokenBalances
        // This will cause ActionFailed when Crystal.sol checks:
        // if (uint128(tokenBalances[0][token]) < amount) revert ActionFailed();
        amountIn = size;
        amountOut = size;
        id = 0;

        // NOTE: We intentionally don't update tokenBalances[0][outputToken]
        // In a real market, the delegatecall would update Crystal's storage
        // By not doing this, the post-swap balance check fails
    }
}

/// @notice Malicious market that reverts on marketOrder.
contract FailingMarket {
    function getQuote(
        bool isBuy,
        bool isExactInput,
        bool useInternalBalance,
        uint256 size,
        uint256 worstPrice
    ) external pure returns (uint256 inputAmount, uint256 outputAmount) {
        inputAmount = size;
        outputAmount = size;
    }

    function marketOrder(
        bool isBuy,
        bool isExactInput,
        uint256 options,
        uint256 orderType,
        uint256 size,
        uint256 worstPrice,
        address referrer,
        address user
    ) external payable returns (uint256, uint256, uint256) {
        revert("FailingMarket: forced failure");
    }
}

/// @notice Market that uses inline assembly to return false from delegatecall
/// This is needed because normal reverts don't trigger coverage for the caller's error handling.
contract AssemblyFailingMarket {
    function getQuote(
        bool,
        bool,
        bool,
        uint256 size,
        uint256
    ) external pure returns (uint256 inputAmount, uint256 outputAmount) {
        inputAmount = size;
        outputAmount = size;
    }

    function marketOrder(
        bool,
        bool,
        uint256,
        uint256,
        uint256,
        uint256,
        address,
        address
    ) external payable returns (uint256, uint256, uint256) {
        // Use assembly to revert in a way that causes delegatecall to return false
        assembly {
            revert(0, 0)
        }
    }
}

/// @notice Market that returns inconsistent quote values
/// Used to trigger line 1642: if (i != 0 && amounts[i] != inputAmount).
contract InconsistentQuoteMarket {
    function getQuote(
        bool,
        bool,
        bool useInternalBalance,
        uint256 size,
        uint256
    ) external pure returns (uint256 inputAmount, uint256 outputAmount) {
        // On first hop (useInternalBalance = false), return normal values
        // On second hop (useInternalBalance = true), return different inputAmount
        if (useInternalBalance) {
            // Return a different input than what we received from previous hop
            inputAmount = size * 2; // Inconsistent!
            outputAmount = size;
        } else {
            inputAmount = size;
            outputAmount = size;
        }
    }

    function marketOrder(
        bool,
        bool,
        uint256,
        uint256,
        uint256 size,
        uint256,
        address,
        address
    ) external payable returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        amountIn = size;
        amountOut = size;
        id = 0;
    }
}

/// @notice Market that fails on getQuote (selector 0x638571e3).
/// @dev Used to test quoteBuy/quoteSell delegatecall failure branches (lines 3236-3237, 3333-3334).
contract FailingQuoteMarket {
    function getQuote(
        bool,
        bool,
        bool,
        uint256,
        uint256
    ) external pure returns (uint256, uint256) {
        assembly {
            revert(0, 0)
        }
    }

    function marketOrder(
        bool,
        bool,
        uint256,
        uint256,
        uint256,
        uint256,
        address,
        address
    ) external payable returns (uint256, uint256, uint256) {
        return (0, 0, 0);
    }
}
