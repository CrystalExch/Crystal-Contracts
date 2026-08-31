// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "../libraries/ERC20.sol";

contract TestToken is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract WETH is ERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    constructor() ERC20("Wrapped Ethereum", "WETH") {}

    fallback() external payable {
        deposit();
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }
}

/// @notice Mock ERC20 token that can be configured to fail transfers.
/// @dev Used for testing transfer failure handling paths in CrystalMarket.
contract FailingToken is ERC20 {
    bool public failAllTransfers;
    bool public failAllTransferFroms;
    mapping(address => bool) public blacklisted;
    mapping(address => bool) public failTransferTo;
    mapping(address => bool) public failTransferFromAddr;

    bool public revertAllTransfers;
    bool public revertAllTransferFroms;
    mapping(address => bool) public revertTransferTo;
    mapping(address => bool) public revertTransferFromAddr;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function setFailAllTransfers(bool fail) external {
        failAllTransfers = fail;
    }

    function setFailAllTransferFroms(bool fail) external {
        failAllTransferFroms = fail;
    }

    function setBlacklisted(address account, bool status) external {
        blacklisted[account] = status;
    }

    function setFailTransferTo(address account, bool fail) external {
        failTransferTo[account] = fail;
    }

    function setFailTransferFromAddr(address account, bool fail) external {
        failTransferFromAddr[account] = fail;
    }

    function setRevertAllTransfers(bool fail) external {
        revertAllTransfers = fail;
    }

    function setRevertAllTransferFroms(bool fail) external {
        revertAllTransferFroms = fail;
    }

    function setRevertTransferTo(address account, bool fail) external {
        revertTransferTo[account] = fail;
    }

    function setRevertTransferFromAddr(address account, bool fail) external {
        revertTransferFromAddr[account] = fail;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (revertAllTransfers) {
            revert("FailingToken: transfer reverted");
        }
        if (revertTransferTo[to]) {
            revert("FailingToken: transfer to reverted");
        }
        if (revertTransferFromAddr[msg.sender]) {
            revert("FailingToken: transfer from reverted");
        }

        if (failAllTransfers) {
            return false;
        }
        if (blacklisted[msg.sender] || blacklisted[to]) {
            return false;
        }
        if (failTransferTo[to]) {
            return false;
        }
        if (failTransferFromAddr[msg.sender]) {
            return false;
        }

        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        if (revertAllTransferFroms) {
            revert("FailingToken: transferFrom reverted");
        }
        if (revertTransferTo[to]) {
            revert("FailingToken: transferFrom to reverted");
        }
        if (revertTransferFromAddr[from]) {
            revert("FailingToken: transferFrom from reverted");
        }

        if (failAllTransferFroms) {
            return false;
        }
        if (blacklisted[from] || blacklisted[to]) {
            return false;
        }
        if (failTransferTo[to]) {
            return false;
        }
        if (failTransferFromAddr[from]) {
            return false;
        }
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        _transfer(from, to, amount);
        return true;
    }
}
