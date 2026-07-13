// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {ICrystal} from "../interfaces/ICrystal.sol";
import {ICrystalVault} from "../interfaces/ICrystalVault.sol";
import {ICrystalVaultFactory} from "../interfaces/ICrystalVaultFactory.sol";
import {ERC20} from "../libraries/ERC20.sol";
import {CrystalMath} from "../libraries/CrystalMath.sol";

/**
 * @title CrystalVault
 * @author Crystal Labs
 *
 * @notice
 * A non-transferable ERC20-style vault share token representing proportional
 * ownership of assets deposited into the Crystal protocol.
 *
 * - Users deposit quote and base assets via the factory and receive vault shares.
 * - Shares represent a proportional claim on the vault's total assets including active orders.
 * - Withdrawals can optionally be timelocked.
 * - Vault operators interact with this contract directly to place and cancel orders.
 *
 * @dev
 * - Shares are non-transferable.
 * - Deposits and withdrawals are only callable by the factory.
 * - The owner must maintain a minimum ownership percentage unless closing.
 * - An atomic proportional decrease of all active orders upon withdrawal is optional.
 * - A vault can be in three states: open, locked, and closed.
 */
contract CrystalVault is ERC20 {
    /// @notice Timestamp of the user's last deposit, used to enforce lockup.
    mapping(address => uint256) public unlockTimestamp;

    /// @notice Maximum total shares allowed (0 = uncapped).
    uint256 public maxShares;

    /// @notice Crystal market this vault trades on.
    address public market;

    /// @notice Lockup duration in seconds after deposit before withdrawal.
    uint40 public lockup;

    /// @notice Maximum cloid index allowed for active orders.
    uint16 public orderCap;

    /// @notice Whether to proportionally decrease all active orders upon withdrawal.
    bool public decrease;

    /// @notice Whether new deposits into the vault are paused.
    bool public locked;

    /// @notice Whether the vault has been permanently closed.
    bool public closed;

    /// @notice Vault metadata.
    ICrystalVault.VaultMetaData public metadata;

    /// @notice Crystal core contract address.
    address public immutable crystal;

    /// @notice Quote asset token address.
    address public immutable quoteAsset;

    /// @notice Base asset token address.
    address public immutable baseAsset;

    /// @notice Vault owner.
    address public immutable owner;

    /// @notice Factory contract that deployed this vault.
    address public immutable factory;

    /// @notice Reverts if called by any address other than the vault factory.
    modifier onlyFactory() {
        require(msg.sender == factory, ICrystal.Unauthorized(msg.sender));
        _;
    }

    /**
     * @notice Initializes a new CrystalVault.
     *
     * @param _crystal Address of the Crystal core contract.
     * @param _quoteAsset Quote asset token address.
     * @param _baseAsset Base asset token address.
     * @param _owner Vault owner and strategist.
     * @param _symbol ERC20 symbol for vault share token.
     * @param _metadata Vault metadata struct.
     */
    constructor(address _crystal, address _quoteAsset, address _baseAsset, address _owner, string memory _symbol, ICrystalVault.VaultMetaData memory _metadata) ERC20(_metadata.name, _symbol) {
        crystal = _crystal;
        metadata = _metadata;
        market = ICrystal(crystal).getMarketByTokens(_quoteAsset, _baseAsset);
        require(ICrystal(crystal).getMarket(market).quoteAsset == _quoteAsset, ICrystal.InvalidMarket(_quoteAsset, _baseAsset)); // Validate market exists for token pair
        quoteAsset = _quoteAsset;
        baseAsset = _baseAsset;
        owner = _owner;
        factory = msg.sender;
        orderCap = ICrystalVaultFactory(factory).maxOrderCap();
        lockup = ICrystalVaultFactory(factory).maxLockup();
        ICrystal(crystal).registerUser(address(this));
        IERC20(quoteAsset).approve(crystal, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        IERC20(baseAsset).approve(crystal, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }

    /**
     * @notice Accepts native token transfers for priority bid.
     */
    receive() external payable {}

    /**
     * @notice Returns total and available balances for both vault assets.
     *
     * @return quoteBalance Total deposited quote balance.
     * @return baseBalance Total deposited base balance.
     * @return availableBalanceQuote Unlocked quote balance.
     * @return availableBalanceBase Unlocked base balance.
     */
    function getBalances() public view returns (uint256 quoteBalance, uint256 baseBalance, uint256 availableBalanceQuote, uint256 availableBalanceBase) {
        (quoteBalance, availableBalanceQuote, ) = ICrystal(crystal).getDepositedBalance(address(this), quoteAsset);
        (baseBalance, availableBalanceBase, ) = ICrystal(crystal).getDepositedBalance(address(this), baseAsset);
    }

    /**
     * @notice Vault shares are non-transferable. Always reverts.
     */
    function transfer(address, uint) external pure override returns (bool) {
        revert();
    }

    /**
     * @notice Vault shares are non-transferable. Always reverts.
     */
    function transferFrom(address, address, uint) external pure override returns (bool) {
        revert();
    }

    /**
     * @notice Pauses new deposits into the vault.
     */
    function lock() external onlyFactory {
        require(!locked, ICrystalVault.InvalidState());
        locked = true;
    }

    /**
     * @notice Resumes allowing new deposits into the vault.
     */
    function unlock() external onlyFactory {
        require(locked && !closed, ICrystalVault.InvalidState());
        locked = false;
    }

    /**
     * @notice Updates the maximum share supply.
     *
     * @param _maxShares New max share value (0 = uncapped).
     */
    function changeMaxShares(uint256 _maxShares) external onlyFactory {
        maxShares = _maxShares;
    }

    /**
     * @notice Updates the market reference used by the vault.
     *
     * @dev Cancels all existing orders before switching markets.
     */
    function changeMarket() external onlyFactory {
        cancelAll();
        address newMarket = ICrystal(crystal).getMarketByTokens(quoteAsset, baseAsset);
        require(ICrystal(crystal).getMarket(newMarket).quoteAsset == quoteAsset, ICrystal.InvalidMarket(quoteAsset, baseAsset));
        market = newMarket;
    }

    /**
     * @notice Updates the maximum order cap.
     *
     * @param newCap New order cap value.
     */
    function changeOrderCap(uint16 newCap) external onlyFactory {
        uint256 maxOrderCap = ICrystalVaultFactory(factory).maxOrderCap();
        require(newCap <= maxOrderCap, ICrystal.InvalidParams());
        (uint256[] memory cloids, ) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
        for (uint256 i = 0; i < cloids.length; ++i) {
            require(newCap > cloids[i], ICrystal.InvalidParams());
        }
        orderCap = newCap;
    }

    /**
     * @notice Updates withdrawal order-handling mode.
     *
     * @param newDecrease New decrease-on-withdraw flag.
     */
    function changeDecreaseOnWithdraw(bool newDecrease) external onlyFactory {
        decrease = newDecrease;
    }

    /**
     * @notice Updates the withdrawal lockup duration.
     *
     * @param newLockup New lockup duration.
     */
    function changeLockup(uint40 newLockup) external onlyFactory {
        uint256 maxLockup = ICrystalVaultFactory(factory).maxLockup();
        require(newLockup <= maxLockup, ICrystal.InvalidParams());
        lockup = newLockup;
    }

    /**
     * @notice Claims any available rewards to the vault owner.
     * 
     * @dev As a vault cannot create markets and is unlikely to be used as a referrer address, these rewards are likely in the form of incentives distributed by the protocol or third parties.
     *
     * @param tokens Token list to claim.
     */
    function claimFees(address[] calldata tokens) external onlyFactory {
        ICrystal(crystal).claimFees(owner, tokens);
    }

    /**
     * @notice Clears cloid slots for this vault in the Crystal system.
     *
     * @param userId Crystal user id.
     * @param ids Cloid slot ids to clear.
     */
    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external onlyFactory {
        ICrystal(crystal).clearCloidSlots(userId, ids);
    }

    /**
     * @notice Previews a deposit into the vault.
     *
     * @param amountQuoteDesired Desired quote amount.
     * @param amountBaseDesired Desired base amount.
     *
     * @return shares Shares that would be minted.
     * @return amountQuote Actual quote amount used.
     * @return amountBase Actual base amount used.
     */
    function previewDeposit(uint256 amountQuoteDesired, uint256 amountBaseDesired) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        (uint256 quoteBalance, uint256 baseBalance, , ) = getBalances();
        if (totalSupply == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            shares = CrystalMath._sqrt(amountQuote * amountBase);
        } else {
            require(quoteBalance != 0 && baseBalance != 0, ICrystalVault.InvalidState()); // Pause deposits if the vault is entirely skewed to one side
            uint256 amountBaseOptimal = (amountQuoteDesired * baseBalance) / quoteBalance;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * quoteBalance) / baseBalance;
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
            shares = CrystalMath._min((amountQuote * totalSupply) / quoteBalance, (amountBase * totalSupply) / baseBalance);
        }
    }

    /**
     * @notice Previews a withdrawal from the vault.
     *
     * @param shares Shares to redeem.
     *
     * @return amountQuote Quote amount returned.
     * @return amountBase Base amount returned.
     */
    function previewWithdrawal(uint256 shares) external view returns (uint256 amountQuote, uint256 amountBase) {
        if (totalSupply == 0 || shares == 0) {
            return (0, 0);
        }
        (uint256 quoteBalance, uint256 baseBalance, , ) = getBalances();
        amountQuote = (quoteBalance * shares) / totalSupply;
        amountBase = (baseBalance * shares) / totalSupply;
    }

    /**
     * @notice Deposits assets and mints vault shares.
     *
     * @param user Recipient of minted shares.
     * @param amountQuoteDesired Desired quote amount.
     * @param amountBaseDesired Desired base amount.
     * @param amountQuoteMin Minimum acceptable quote used.
     * @param amountBaseMin Minimum acceptable base used.
     *
     * @return shares Shares minted.
     * @return amountQuote Quote amount deposited.
     * @return amountBase Base amount deposited.
     */
    function deposit(address user, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external onlyFactory returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        require(!locked && amountQuoteDesired != 0 && amountBaseDesired != 0, ICrystal.InvalidParams());
        (uint256 quoteBalance, uint256 baseBalance, , ) = getBalances();

        if (totalSupply == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            shares = CrystalMath._sqrt(amountQuote * amountBase);
        } else {
            require(quoteBalance != 0 && baseBalance != 0, ICrystalVault.InvalidState()); // Pause deposits if the vault is entirely skewed to one side
            uint256 amountBaseOptimal = (amountQuoteDesired * baseBalance) / quoteBalance;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * quoteBalance) / baseBalance;
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
            shares = CrystalMath._min((amountQuote * totalSupply) / quoteBalance, (amountBase * totalSupply) / baseBalance);
        }

        require(amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && shares != 0 && (maxShares == 0 || totalSupply + shares <= maxShares), ICrystal.InvalidParams());

        if (amountQuote > 0) {
            IERC20(quoteAsset).transferFrom(msg.sender, address(this), amountQuote);
            ICrystal(crystal).deposit(quoteAsset, amountQuote);
        }
        if (amountBase > 0) {
            IERC20(baseAsset).transferFrom(msg.sender, address(this), amountBase);
            ICrystal(crystal).deposit(baseAsset, amountBase);
        }

        _mint(user, shares);
        unlockTimestamp[user] = block.timestamp + lockup;
        require(balanceOf[owner] * 20 > totalSupply, ICrystalVault.InvalidOwnerShare());
    }

    /**
     * @notice Withdraws assets by burning vault shares.
     *
     * @param user Address whose shares are burned.
     * @param shares Number of shares to redeem.
     * @param amountQuoteMin Minimum acceptable quote returned.
     * @param amountBaseMin Minimum acceptable base returned.
     *
     * @return amountQuote Quote amount returned.
     * @return amountBase Base amount returned.
     */
    function withdraw(address user, uint256 shares, uint256 amountQuoteMin, uint256 amountBaseMin) external onlyFactory returns (uint256 amountQuote, uint256 amountBase) {
        require(shares != 0 && shares <= balanceOf[user] && unlockTimestamp[user] <= block.timestamp, ICrystal.InvalidParams());
        (uint256 quoteBalance, uint256 baseBalance, uint256 availableQuote, uint256 availableBase) = getBalances();
        amountQuote = (quoteBalance * shares) / totalSupply;
        amountBase = (baseBalance * shares) / totalSupply;
        require(amountQuote >= amountQuoteMin && amountBase >= amountBaseMin, ICrystal.SlippageExceeded());
        _burn(user, shares);
        if (user == owner && !closed) {
            if (balanceOf[owner] == 0) {
                cancelAll();
                (quoteBalance, baseBalance, availableQuote, availableBase) = getBalances();
                closed = true;
                if (!locked) {
                    locked = true;
                }
            } else {
                require(balanceOf[owner] * 20 > totalSupply, ICrystalVault.InvalidOwnerShare());
            }
        }
        if (decrease) { // Round with cumulative ceiling rounding
            (uint256[] memory cloids, ICrystal.Order[] memory orders) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
            bytes32[] memory data = new bytes32[](cloids.length + 1);
            data[0] = bytes32((1 << 252) | (cloids.length << 160) | uint160(market));
            uint256 quote;
            uint256 base;
            for (uint256 i; i < cloids.length; ++i) {
                if (orders[i].isBuy) {
                    data[i + 1] = bytes32((uint256(12) << 252) | ((cloids[i] & 0x3FF) << 192) | ((((quote + orders[i].size) * amountQuote + quoteBalance - 1) / quoteBalance) - ((quote * amountQuote + quoteBalance - 1) / quoteBalance) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                    quote += orders[i].size;
                } else {
                    data[i + 1] = bytes32((uint256(12) << 252) | ((cloids[i] & 0x3FF) << 192) | ((((base + orders[i].size) * amountBase + baseBalance - 1) / baseBalance) - ((base * amountBase + baseBalance - 1) / baseBalance) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                    base += orders[i].size;
                }
            }
            (bool success, bytes memory returnData) = crystal.call(abi.encodePacked(data));
            if (!success) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
        } else if (amountQuote > availableQuote || amountBase > availableBase) {
            (uint256[] memory cloids, ICrystal.Order[] memory orders) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
            bytes32[] memory data = new bytes32[](cloids.length + 1);
            ICrystal.Order memory order;
            uint256 cloid;
            uint256 excessQuote = amountQuote > availableQuote ? (amountQuote - availableQuote) : 0;
            uint256 excessBase = amountBase > availableBase ? (amountBase - availableBase) : 0;
            uint256 lockedQuote = quoteBalance - availableQuote;
            uint256 lockedBase = baseBalance - availableBase;
            uint256 idx;
            for (uint256 i; i < cloids.length; ++i) {
                order = orders[i];
                cloid = cloids[i];
                if (order.isBuy && excessQuote != 0) {
                    data[++idx] = bytes32((12 << 252) | ((cloid & 0x3FF) << 192) | (((order.size * excessQuote + lockedQuote - 1) / lockedQuote) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                } else if (!order.isBuy && excessBase != 0) {
                    data[++idx] = bytes32((12 << 252) | ((cloid & 0x3FF) << 192) | (((order.size * excessBase + lockedBase - 1) / lockedBase) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                }
            }
            data[0] = bytes32((1 << 252) | (idx << 160) | uint160(market));
            idx += 1;
            assembly {
                mstore(data, idx)
            }
            (bool success, bytes memory returnData) = crystal.call(abi.encodePacked(data));
            if (!success) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
        }
        if (balanceOf[user] == 0) {
            unlockTimestamp[user] = 0;
        }
        if (amountQuote > 0) {
            ICrystal(crystal).withdraw(msg.sender, quoteAsset, amountQuote);
        }
        if (amountBase > 0) {
            ICrystal(crystal).withdraw(msg.sender, baseAsset, amountBase);
        }
    }

    /**
     * @notice Cancels all open orders for the vault.
     */
    function cancelAll() public {
        require(msg.sender == owner || msg.sender == factory, ICrystal.Unauthorized(msg.sender));
        (uint256[] memory cloids, ) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
        bytes32[] memory data = new bytes32[](cloids.length + 1);
        uint256 cloid;
        data[0] = bytes32((1 << 252) | (cloids.length << 160) | uint160(market));
        for (uint256 i; i < cloids.length; ++i) {
            cloid = cloids[i];
            uint256 word = (1 << 252) | ((cloid & 0x3FF) << 192);
            data[i + 1] = bytes32(word);
        }
        (bool success, bytes memory returnData) = crystal.call(abi.encodePacked(data));
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    /**
     * @notice Withdraws any ETH balance held by the vault to the owner.
     */
    function sweep() external {
        require(msg.sender == owner, ICrystal.Unauthorized(msg.sender));
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, ICrystal.TransferFailed(msg.sender));
    }

    /**
     * @notice Executes a batch of trading actions on the Crystal market.
     *
     * @param actions Array of encoded trading actions.
     * @param bid ETH value forwarded to Crystal.
     */
    function execute(ICrystalVault.Action[] calldata actions, uint256 bid) external payable {
        require(msg.sender == owner, ICrystal.Unauthorized(msg.sender));
        require(actions.length < 0xFFF && !closed && bid < 0xFFFFFFFFFFFFFFFFFFFF, ICrystal.InvalidParams());
        bytes32[] memory data = new bytes32[](actions.length + 1);
        ICrystalVault.Action memory action;
        data[0] = bytes32((1 << 252) | (bid << 172) | (actions.length << 160) | uint160(market));
        for (uint256 i; i < actions.length; ++i) {
            action = actions[i];
            require(action.action < 13, ICrystal.InvalidParams());
            if (action.action == 2 || action.action == 3 || action.action == 4 || action.action == 5) {
                require(action.cloid != 0 && action.cloid < orderCap, ICrystal.InvalidParams());
            }
            data[i + 1] = bytes32((action.action << 252) | (action.requireSuccess ? (1 << 248) : 0) | ((action.cloid & 0x3FF) << 192) | ((action.param1 & 0xFFFFFFFFFFFFFFFFFFFF) << 112) | (action.param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
        }
        (bool success, bytes memory returnData) = crystal.call{value: bid}(abi.encodePacked(data));
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }
}
