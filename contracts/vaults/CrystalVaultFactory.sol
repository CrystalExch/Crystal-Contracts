// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ICrystal} from "../interfaces/ICrystal.sol";
import {ICrystalVault} from "../interfaces/ICrystalVault.sol";
import {ICrystalVaultFactory} from "../interfaces/ICrystalVaultFactory.sol";
import {CrystalVault} from "./CrystalVault.sol";

/**
 * @title CrystalVaultFactory
 * @author Crystal Labs
 *
 * @notice
 * The factory contract responsible for deploying CrystalVault instances.
 *
 * The factory:
 * - Deploys new vaults.
 * - Routes deposits and withdrawals.
 * - Tracks vault metadata and configuration.
 * - Handles native token wrapping and unwrapping.
 *
 * @dev
 * - Vault logic lives entirely in CrystalVault.
 * - All deposits and withdrawals to/from individual vaults must go through this contract.
 * - Governance can only set default vault parameters.
 * - Vault operators interact with the vault directly to place and cancel orders.
 */
contract CrystalVaultFactory {
    /// @notice Wrapped native token address.
    address public immutable weth;

    /// @notice Placeholder native token address.
    address public immutable eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Governance address controlling factory-level parameters.
    address public gov;

    /// @notice Crystal core contract address.
    address public crystal;

    /// @notice List of all deployed vaults.
    address[] public allVaults;

    /// @notice Vault metadata indexed by vault address.
    mapping(address => ICrystalVaultFactory.Vault) public getVault;

    /// @notice Per-token minimum initial deposit override.
    mapping(address => uint256) public minDeposit;

    /// @notice Default minimum deposit when no per-token override exists.
    uint256 public globalMinDeposit;

    /// @notice Global maximum order cap for vaults.
    uint16 public maxOrderCap;

    /// @notice Global maximum lockup duration for vaults.
    uint40 public maxLockup;

    /// @notice Prevents reentrancy using transient storage.
    modifier nonReentrant() {
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        _;
        assembly {
            tstore(0x0, 0)
        }
    }
    
    /// @notice Reverts if called by any address other than gov.
    modifier onlyOwner() {
        require(msg.sender == gov, ICrystal.Unauthorized(msg.sender));
        _;
    }

    /**
     * @notice Deploys the vault factory and initializes global parameters.
     *
     * @param _crystal Address of the Crystal core contract.
     * @param _gov Governance address with permission to update factory settings.
     * @param _weth WETH contract used for ETH sentinel paths.
     * @param _globalMinDeposit Default minimum deposit amount.
     * @param _maxOrderCap Global maximum order cap for vaults.
     * @param _lockup Global maximum withdrawal lockup duration.
     */
    constructor(address _crystal, address _gov, address _weth, uint256 _globalMinDeposit, uint16 _maxOrderCap, uint40 _lockup) {
        require(_maxOrderCap < 1024, ICrystal.InvalidParams());
        crystal = _crystal;
        gov = _gov;
        weth = _weth;
        globalMinDeposit = _globalMinDeposit;
        maxOrderCap = _maxOrderCap;
        maxLockup = _lockup;
    }

    /**
     * @notice Accepts native token transfers for ETH deposits.
     */
    receive() external payable {}

    /**
     * @notice Deploys a new CrystalVault and registers it in factory storage.
     *
     * @param quoteAsset Quote asset token address.
     * @param baseAsset Base asset token address.
     * @param maxShares Optional max total shares (0 = uncapped).
     * @param lockup Optional withdrawal lockup (0 = factory default).
     * @param decreaseOnWithdraw Whether the vault scales orders on withdrawal.
     * @param symbol ERC20 symbol for the vault share token.
     * @param metadata Vault metadata forwarded to the vault.
     *
     * @return vault Address of the deployed vault.
     */
    function _createVault(address quoteAsset, address baseAsset, uint256 maxShares, uint40 lockup, bool decreaseOnWithdraw, string memory symbol, ICrystalVault.VaultMetaData memory metadata) private returns (address vault) {
        vault = address(new CrystalVault(crystal, quoteAsset, baseAsset, msg.sender, symbol, metadata));
        IERC20(quoteAsset).approve(vault, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        IERC20(baseAsset).approve(vault, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        if (lockup != 0) {
            ICrystalVault(vault).changeLockup(lockup);
        } else {
            lockup = maxLockup;
        }
        if (maxShares != 0) {
            ICrystalVault(vault).changeMaxShares(maxShares);
        }
        if (decreaseOnWithdraw) {
            ICrystalVault(vault).changeDecreaseOnWithdraw(decreaseOnWithdraw);
        }
        getVault[vault] = ICrystalVaultFactory.Vault(quoteAsset, baseAsset, msg.sender, 0, maxShares, lockup, decreaseOnWithdraw, false, false, metadata);
        allVaults.push(vault);
        emit ICrystalVaultFactory.VaultDeployed(vault, quoteAsset, baseAsset, msg.sender, maxShares, lockup, decreaseOnWithdraw, metadata);
    }

    /**
     * @notice Updates the governance address.
     *
     * @param newGov New governance address.
     */
    function changeGov(address newGov) external onlyOwner {
        gov = newGov;
    }

    /**
     * @notice Updates the global maximum order cap.
     *
     * @param newCap New maximum order cap.
     */
    function changeMaxOrderCap(uint16 newCap) external onlyOwner {
        require(newCap < 1024, ICrystal.InvalidParams());
        maxOrderCap = newCap;
    }

    /**
     * @notice Updates the global maximum lockup duration.
     *
     * @param newLockup New maximum lockup duration.
     */
    function changeMaxLockup(uint40 newLockup) external onlyOwner {
        maxLockup = newLockup;
    }

    /**
     * @notice Updates the global minimum initial deposit amount.
     *
     * @param newGlobalMinDeposit New minimum initial deposit amount.
     */
    function changeGlobalMinDeposit(uint256 newGlobalMinDeposit) external onlyOwner {
        globalMinDeposit = newGlobalMinDeposit;
    }

    /**
     * @notice Sets a per-token minimum initial deposit amount.
     *
     * @param token Token address (WETH for ETH sentinel).
     * @param newMinDeposit Minimum initial deposit amount.
     */
    function changeMinDeposit(address token, uint256 newMinDeposit) external onlyOwner {
        minDeposit[token == eth ? weth : token] = newMinDeposit;
    }

    /**
     * @notice Deploys a new vault and performs the initial deposit.
     *
     * @param quoteAsset Quote asset address (may be ETH sentinel).
     * @param baseAsset Base asset address (may be ETH sentinel).
     * @param amountQuote Initial quote deposit.
     * @param amountBase Initial base deposit.
     * @param maxShares Optional max shares (0 = uncapped).
     * @param lockup Optional lockup (0 = factory default).
     * @param decreaseOnWithdraw Whether to scale orders on withdrawal.
     * @param metadata Vault metadata.
     *
     * @return vault Address of the deployed vault.
     */
    function deploy(address quoteAsset, address baseAsset, uint256 amountQuote, uint256 amountBase, uint256 maxShares, uint40 lockup, bool decreaseOnWithdraw, ICrystalVault.VaultMetaData memory metadata) external payable returns (address vault) {
        if (minDeposit[quoteAsset == eth ? weth : quoteAsset] != 0) {
            require(amountQuote > minDeposit[quoteAsset == eth ? weth : quoteAsset], ICrystalVaultFactory.SizeBelowMin());
        } else {
            require(amountQuote > globalMinDeposit, ICrystalVaultFactory.SizeBelowMin());
        }

        if (minDeposit[baseAsset == eth ? weth : baseAsset] != 0) {
            require(amountBase > minDeposit[baseAsset == eth ? weth : baseAsset], ICrystalVaultFactory.SizeBelowMin());
        } else {
            require(amountBase > globalMinDeposit, ICrystalVaultFactory.SizeBelowMin());
        }
        string memory symbol = string.concat("CLV-", IERC20(baseAsset == eth ? weth : baseAsset).symbol(), IERC20(quoteAsset == eth ? weth : quoteAsset).symbol());

        vault = _createVault(quoteAsset == eth ? weth : quoteAsset, baseAsset == eth ? weth : baseAsset, maxShares, lockup, decreaseOnWithdraw, symbol, metadata);

        deposit(vault, quoteAsset, baseAsset, amountQuote, amountBase, 0, 0);
    }

    /**
     * @notice Returns the total number of deployed vaults.
     *
     * @return Number of vaults.
     */
    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
    }

    /**
     * @notice Previews a deposit into a vault.
     *
     * @param vault Vault address.
     * @param amountQuoteDesired Desired quote amount.
     * @param amountBaseDesired Desired base amount.
     *
     * @return shares Shares that would be minted.
     * @return amountQuote Actual quote amount used.
     * @return amountBase Actual base amount used.
     */
    function previewDeposit(address vault, uint256 amountQuoteDesired, uint256 amountBaseDesired) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        return ICrystalVault(vault).previewDeposit(amountQuoteDesired, amountBaseDesired);
    }

    /**
     * @notice Previews a withdrawal from a vault.
     *
     * @param vault Vault address.
     * @param shares Shares to redeem.
     *
     * @return amountQuote Quote amount returned.
     * @return amountBase Base amount returned.
     */
    function previewWithdrawal(address vault, uint256 shares) external view returns (uint256 amountQuote, uint256 amountBase) {
        return ICrystalVault(vault).previewWithdrawal(shares);
    }

    /**
     * @notice Returns a user's share balance and underlying asset amounts.
     *
     * @param vault Vault address.
     * @param user User address.
     *
     * @return shares Share balance.
     * @return amountQuote Quote amount represented.
     * @return amountBase Base amount represented.
     */
    function balanceOf(address vault, address user) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        shares = ICrystalVault(vault).balanceOf(user);
        (amountQuote, amountBase) = ICrystalVault(vault).previewWithdrawal(shares);
    }

    /**
     * @notice Deposits assets into a vault via the factory.
     *
     * @param vault Vault address.
     * @param quoteAsset Quote asset (may be ETH sentinel).
     * @param baseAsset Base asset (may be ETH sentinel).
     * @param amountQuoteDesired Desired quote amount.
     * @param amountBaseDesired Desired base amount.
     * @param amountQuoteMin Minimum acceptable quote used.
     * @param amountBaseMin Minimum acceptable base used.
     *
     * @return shares Shares minted.
     * @return amountQuote Actual quote deposited.
     * @return amountBase Actual base deposited.
     */
    function deposit(address vault, address quoteAsset, address baseAsset, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) public payable nonReentrant returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        ICrystalVaultFactory.Vault storage vaultInfo = getVault[vault];
        require(vaultInfo.quoteAsset == (quoteAsset == eth ? weth : quoteAsset) && vaultInfo.baseAsset == (baseAsset == eth ? weth : baseAsset), ICrystal.InvalidMarket(quoteAsset == eth ? weth : quoteAsset, baseAsset == eth ? weth : baseAsset));
        if (quoteAsset == eth) {
            require(msg.value == amountQuoteDesired, ICrystal.InvalidMsgValue());
            IWETH(weth).deposit{value: msg.value}();
            IERC20(baseAsset).transferFrom(msg.sender, address(this), amountBaseDesired);
        } else {
            IERC20(quoteAsset).transferFrom(msg.sender, address(this), amountQuoteDesired);
            if (baseAsset == eth) {
                require(msg.value == amountBaseDesired, ICrystal.InvalidMsgValue());
                IWETH(weth).deposit{value: msg.value}();
            } else {
                require(msg.value == 0, ICrystal.InvalidMsgValue());
                IERC20(baseAsset).transferFrom(msg.sender, address(this), amountBaseDesired);
            }
        }
        (shares, amountQuote, amountBase) = ICrystalVault(vault).deposit(msg.sender, amountQuoteDesired, amountBaseDesired, amountQuoteMin, amountBaseMin);
        if (quoteAsset == eth) {
            IWETH(weth).withdraw(msg.value - amountQuote);
            (bool success, ) = msg.sender.call{value: msg.value - amountQuote}("");
            require(success, ICrystal.TransferFailed(msg.sender));
            IERC20(baseAsset).transfer(msg.sender, amountBaseDesired - amountBase);
        } else {
            IERC20(quoteAsset).transfer(msg.sender, amountQuoteDesired - amountQuote);
            if (baseAsset == eth) {
                IWETH(weth).withdraw(msg.value - amountBase);
                (bool success, ) = msg.sender.call{value: msg.value - amountBase}("");
                require(success, ICrystal.TransferFailed(msg.sender));
            } else {
                IERC20(baseAsset).transfer(msg.sender, amountBaseDesired - amountBase);
            }
        }
        vaultInfo.totalShares += shares;
        emit ICrystalVaultFactory.Deposit(vault, msg.sender, shares, amountQuote, amountBase);
    }

    /**
     * @notice Withdraws assets from a vault via the factory.
     *
     * @param vault Vault address.
     * @param quoteAsset Quote asset (may be ETH sentinel).
     * @param baseAsset Base asset (may be ETH sentinel).
     * @param shares Shares to redeem.
     * @param amountQuoteMin Minimum acceptable quote returned.
     * @param amountBaseMin Minimum acceptable base returned.
     *
     * @return amountQuote Quote amount returned.
     * @return amountBase Base amount returned.
     */
    function withdraw(address vault, address quoteAsset, address baseAsset, uint256 shares, uint256 amountQuoteMin, uint256 amountBaseMin) external nonReentrant returns (uint256 amountQuote, uint256 amountBase) {
        ICrystalVaultFactory.Vault storage vaultInfo = getVault[vault];
        require(vaultInfo.quoteAsset == (quoteAsset == eth ? weth : quoteAsset) && vaultInfo.baseAsset == (baseAsset == eth ? weth : baseAsset), ICrystal.InvalidMarket(quoteAsset == eth ? weth : quoteAsset, baseAsset == eth ? weth : baseAsset));
        (amountQuote, amountBase) = ICrystalVault(vault).withdraw(msg.sender, shares, amountQuoteMin, amountBaseMin);
        if (quoteAsset == eth) {
            IWETH(weth).withdraw(amountQuote);
            (bool success, ) = msg.sender.call{value: amountQuote}("");
            require(success, ICrystal.TransferFailed(msg.sender));
        } else {
            IERC20(quoteAsset).transfer(msg.sender, amountQuote);
        }
        if (baseAsset == eth) {
            IWETH(weth).withdraw(amountBase);
            (bool success, ) = msg.sender.call{value: amountBase}("");
            require(success, ICrystal.TransferFailed(msg.sender));
        } else {
            IERC20(baseAsset).transfer(msg.sender, amountBase);
        }
        if (IERC20(vault).balanceOf(vaultInfo.owner) == 0 && !vaultInfo.closed) {
            if (!vaultInfo.locked) {
                vaultInfo.locked = true;
                emit ICrystalVaultFactory.Locked(vault);
            }
            vaultInfo.closed = true;
            emit ICrystalVaultFactory.Closed(vault);
        }
        vaultInfo.totalShares = ICrystalVault(vault).totalSupply();
        emit ICrystalVaultFactory.Withdraw(vault, msg.sender, shares, amountQuote, amountBase);
    }

    /**
     * @notice Pauses new deposits into a vault.
     *
     * @param vault Vault address.
     */
    function lock(address vault) external {
        require(msg.sender == getVault[vault].owner, ICrystal.Unauthorized(msg.sender));
        ICrystalVault(vault).lock();
        getVault[vault].locked = true;
        emit ICrystalVaultFactory.Locked(vault);
    }

    /**
     * @notice Resumes allowing new deposits into a vault.
     *
     * @param vault Vault address.
     */
    function unlock(address vault) external {
        require(msg.sender == getVault[vault].owner, ICrystal.Unauthorized(msg.sender));
        ICrystalVault(vault).unlock();
        getVault[vault].locked = false;
        emit ICrystalVaultFactory.Unlocked(vault);
    }

    /**
     * @notice Fully closes a vault by withdrawing owner shares.
     *
     * @param vault Vault address.
     *
     * @return amountQuote Quote amount returned to owner.
     * @return amountBase Base amount returned to owner.
     */
    function close(address vault) external returns (uint256 amountQuote, uint256 amountBase) {
        require(msg.sender == getVault[vault].owner, ICrystal.Unauthorized(msg.sender));
        ICrystalVaultFactory.Vault storage vaultInfo = getVault[vault];
        uint256 shares = ICrystalVault(vault).balanceOf(msg.sender);
        (amountQuote, amountBase) = ICrystalVault(vault).withdraw(msg.sender, shares, 0, 0);
        IERC20(vaultInfo.quoteAsset).transfer(msg.sender, amountQuote);
        IERC20(vaultInfo.baseAsset).transfer(msg.sender, amountBase);
        if (IERC20(vault).balanceOf(vaultInfo.owner) == 0 && !vaultInfo.closed) {
            if (!vaultInfo.locked) {
                vaultInfo.locked = true;
                emit ICrystalVaultFactory.Locked(vault);
            }
            vaultInfo.closed = true;
            emit ICrystalVaultFactory.Closed(vault);
        }
        vaultInfo.totalShares = ICrystalVault(vault).totalSupply();
        emit ICrystalVaultFactory.Withdraw(vault, msg.sender, shares, amountQuote, amountBase);
    }

    /**
     * @notice Updates a vault's max share cap.
     *
     * @param vault Vault address.
     * @param newMaxShares New max share value.
     */
    function changeMaxShares(address vault, uint256 newMaxShares) external {
        require(msg.sender == getVault[vault].owner, ICrystal.Unauthorized(msg.sender));
        ICrystalVault(vault).changeMaxShares(newMaxShares);
        getVault[vault].maxShares = newMaxShares;
        emit ICrystalVaultFactory.MaxSharesChanged(vault, newMaxShares);
    }

    /**
     * @notice Updates a vault's withdrawal lockup.
     *
     * @param vault Vault address.
     * @param newLockup New lockup duration.
     */
    function changeLockup(address vault, uint40 newLockup) external {
        require(msg.sender == getVault[vault].owner, ICrystal.Unauthorized(msg.sender));
        ICrystalVault(vault).changeLockup(newLockup);
        getVault[vault].lockup = newLockup;
        emit ICrystalVaultFactory.LockupChanged(vault, newLockup);
    }

    /**
     * @notice Toggles decrease-on-withdraw behavior for a vault.
     *
     * @param vault Vault address.
     * @param newDecrease New decrease flag.
     */
    function changeDecreaseOnWithdraw(address vault, bool newDecrease) external {
        require(msg.sender == getVault[vault].owner, ICrystal.Unauthorized(msg.sender));
        ICrystalVault(vault).changeDecreaseOnWithdraw(newDecrease);
        getVault[vault].decreaseOnWithdraw  = newDecrease;
        emit ICrystalVaultFactory.DecreaseOnWithdrawChanged(vault, newDecrease);
    }

    /**
     * @notice Updates a vault's order cap.
     *
     * @param vault Vault address.
     * @param newCap New order cap.
     */
    function changeOrderCap(address vault, uint16 newCap) external {
        require(msg.sender == getVault[vault].owner, ICrystal.Unauthorized(msg.sender));
        ICrystalVault(vault).changeOrderCap(newCap);
    }

    /**
     * @notice Updates a vault's market reference.
     *
     * @param vault Vault address.
     */
    function changeMarket(address vault) external {
        require(msg.sender == getVault[vault].owner, ICrystal.Unauthorized(msg.sender));
        ICrystalVault(vault).changeMarket();
    }

    /**
     * @notice Claims any available rewards to the vault owner.
     * 
     * @dev As a vault cannot create markets and is unlikely to be used as a referrer address, these rewards are likely in the form of incentives distributed by the protocol or third parties.
     *
     * @param vault Vault address.
     * @param tokens Token list to claim.
     */
    function claimFees(address vault, address[] calldata tokens) external {
        require(msg.sender == getVault[vault].owner, ICrystal.Unauthorized(msg.sender));
        ICrystalVault(vault).claimFees(tokens);
    }

    /**
     * @notice Clears cloid slots for a vault in the Crystal system.
     *
     * @param vault Vault address.
     * @param userId Crystal user id.
     * @param ids Cloid slot ids to clear.
     */
    function clearCloidSlots(address vault, uint256 userId, uint256[] calldata ids) external {
        require(msg.sender == getVault[vault].owner, ICrystal.Unauthorized(msg.sender));
        ICrystalVault(vault).clearCloidSlots(userId, ids);
    }
}
