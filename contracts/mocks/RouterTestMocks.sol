// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ToggleMarket {
    address immutable token0;
    address immutable token1;
    address immutable placeholder;
    bool immutable setPlaceholder;

    constructor(address _token0, address _token1, bool _setPlaceholder, address _placeholder) {
        token0 = _token0;
        token1 = _token1;
        setPlaceholder = _setPlaceholder;
        placeholder = _placeholder;
    }

    function getQuote(bool, bool, bool, uint256 size, uint256) external payable returns (uint256, uint256) {
        bytes32 inner = keccak256(abi.encode(token0, uint256(27)));
        bytes32 slot = keccak256(abi.encode(token1, inner));
        address value = setPlaceholder ? placeholder : address(0);
        assembly {
            sstore(slot, value)
        }
        return (size, size);
    }

    function marketOrder(bool, bool, uint256, uint256, uint256 size, uint256, address, address) external payable returns (uint256, uint256, uint256) {
        return (size, size, 0);
    }
}

contract InflatingMarket {
    function getQuote(bool, bool, bool, uint256 size, uint256) external payable returns (uint256, uint256) {
        return (size, size);
    }

    function marketOrder(bool, bool, uint256, uint256, uint256 size, uint256, address, address) external payable returns (uint256, uint256, uint256) {
        return (size + 1, size, 0);
    }
}

contract DrainWethMarket {
    address immutable weth;

    constructor(address _weth) {
        weth = _weth;
    }

    function getQuote(bool, bool, bool, uint256 size, uint256) external payable returns (uint256, uint256) {
        return (size, size);
    }

    function marketOrder(bool, bool, uint256, uint256, uint256 size, uint256, address, address) external payable returns (uint256, uint256, uint256) {
        bytes32 slot = keccak256(abi.encode(weth, keccak256(abi.encode(uint256(0), uint256(16)))));
        assembly {
            sstore(slot, 0)
        }
        return (size, size, 0);
    }
}

contract NoCreditMarket {
    function getQuote(bool, bool, bool, uint256 size, uint256) external payable returns (uint256, uint256) {
        return (size, size);
    }

    function marketOrder(bool, bool, uint256, uint256, uint256 size, uint256, address, address) external payable returns (uint256, uint256, uint256) {
        return (size, size, 0);
    }
}

contract CancelOrderMarket {
    address immutable weth;
    uint256 immutable amount;
    bool immutable credit;

    constructor(address _weth, uint256 _amount, bool _credit) {
        weth = _weth;
        amount = _amount;
        credit = _credit;
    }

    function cancelOrder(uint256, uint256, uint256, address) external payable returns (uint256) {
        if (credit) {
            bytes32 slot = keccak256(abi.encode(weth, keccak256(abi.encode(uint256(0), uint256(16)))));
            uint256 value = amount;
            assembly {
                sstore(slot, value)
            }
        }
        return amount;
    }
}

contract ReplaceOrderMarket {
    address immutable weth;
    uint256 immutable amount;

    constructor(address _weth, uint256 _amount) {
        weth = _weth;
        amount = _amount;
    }

    function replaceOrder(uint256, uint256, uint256, uint256, uint256, address, address) external payable returns (uint256) {
        bytes32 slot = keccak256(abi.encode(weth, keccak256(abi.encode(uint256(0), uint256(16)))));
        uint256 value = amount;
        assembly {
            sstore(slot, value)
        }
        return 1;
    }
}

contract RevertingQuoteMarket {
    function getQuote(bool, bool, bool, uint256, uint256) external payable returns (uint256, uint256) {
        revert();
    }

    function marketOrder(bool, bool, uint256, uint256, uint256 size, uint256, address, address) external payable returns (uint256, uint256, uint256) {
        return (size, size, 0);
    }
}

contract LimitOrderMarket {
    function limitOrder(bool, uint256, uint256, uint256, address) external payable returns (uint256) {
        return 1;
    }
}

contract NoRefundMarket {
    function removeLiquidity(address, uint256, uint256, uint256, uint256) external payable returns (uint256, uint256) {
        return (0, 0);
    }
}
