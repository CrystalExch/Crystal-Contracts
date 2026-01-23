// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "../libraries/ERC20.sol";

/// @notice Mock ERC20 token that can be configured to fail transfers
/// @dev Used for testing transfer failure handling paths in CrystalMarket
contract FailingToken is ERC20 {
    // Failure modes - return false
    bool public failAllTransfers;
    bool public failAllTransferFroms;
    mapping(address => bool) public blacklisted;
    mapping(address => bool) public failTransferTo;
    mapping(address => bool) public failTransferFromAddr;

    // Revert modes - for try/catch testing
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

    // Failure configuration functions (return false)
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

    // Revert configuration functions (revert instead of return false)
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
        // Revert modes (for try/catch)
        if (revertAllTransfers) {
            revert("FailingToken: transfer reverted");
        }
        if (revertTransferTo[to]) {
            revert("FailingToken: transfer to reverted");
        }
        if (revertTransferFromAddr[msg.sender]) {
            revert("FailingToken: transfer from reverted");
        }

        // Return false modes
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
        // Revert modes (for try/catch)
        if (revertAllTransferFroms) {
            revert("FailingToken: transferFrom reverted");
        }
        if (revertTransferTo[to]) {
            revert("FailingToken: transferFrom to reverted");
        }
        if (revertTransferFromAddr[from]) {
            revert("FailingToken: transferFrom from reverted");
        }

        // Return false modes
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
