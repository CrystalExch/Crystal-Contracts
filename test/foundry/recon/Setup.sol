// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseSetup } from "@chimera/BaseSetup.sol";
import { vm } from "@chimera/Hevm.sol";
import { ActorManager } from "@recon/ActorManager.sol";
import { AssetManager } from "@recon/AssetManager.sol";
import { Utils } from "@recon/Utils.sol";

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { ICrystalVaultFactory } from "../../../contracts/interfaces/ICrystalVaultFactory.sol";
import { IERC20 } from "../../../contracts/interfaces/IERC20.sol";
import { CrystalVaultFactory } from "../../../contracts/vaults/CrystalVaultFactory.sol";
import { Deploy } from "../Deploy.t.sol";

contract ReconCaller {
    receive() external payable { }

    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory returnData) {
        (bool success, bytes memory result) = target.call{ value: value }(data);
        require(success);
        return result;
    }
}

abstract contract Setup is BaseSetup, ActorManager, AssetManager, Utils, Deploy {
    uint256 internal constant SETUP_ETH_BALANCE = 10_000 ether;
    uint256 internal constant SETUP_WETH_AMOUNT = 5_000 ether;
    uint256 internal constant SETUP_QUOTE_MINT = 2_000_000_000 * 1e6;
    uint256 internal constant SETUP_QUOTE_DEPOSIT = 250_000 * 1e6;
    uint256 internal constant SETUP_WETH_DEPOSIT = 2_000 ether;
    uint256 internal constant MAX_TARGET_QUOTE = 100_000 * 1e6;
    uint256 internal constant MAX_TARGET_BASE = 1_000 ether;
    uint256 internal constant MAX_TRACKED_ORDERS = 48;
    uint256 internal constant MAX_TRACKED_VAULTS = 12;
    uint256 internal constant MAX_TRACKED_LAUNCHPAD_TOKENS = 8;
    uint256 internal constant MAX_TRACKED_FRESH_MARKETS = 8;
    uint16 internal constant VAULT_MAX_ORDER_CAP = 64;
    uint256 internal constant ORDER_TYPES_NORMAL = 0;
    address internal constant RECON_FORWARDER = address(0xF0A0D);
    uint256 internal constant PERMIT_SIGNER_KEY = 0xA11CE;
    address internal constant PERMIT_SIGNER = 0xe05fcC23807536bEe418f142D19fa0d21BB0cfF7;

    enum BatchAction {
        None,
        CancelOrder,
        BuyLimit,
        SellLimit,
        MarketToLimitBuy,
        MarketToLimitSell,
        PartialBuy,
        PartialSell,
        GasAwarePartialBuy,
        GasAwarePartialSell,
        CompleteBuy,
        CompleteSell,
        DecreaseOrder
    }

    struct TrackedOrder {
        address owner;
        address tokenIn;
        address tokenOut;
        bool isBuy;
        uint256 price;
        uint256 id;
        uint256 cloid;
        uint256 minQuoteAtPlacement;
        uint256 size;
        bool live;
    }

    ICrystalVaultFactory internal vaultFactory;
    ReconCaller internal proxyActor;
    address internal permitSigner;
    address internal currentGovernance;

    TrackedOrder[] internal trackedOrders;
    address[] internal trackedVaults;
    address[] internal trackedLaunchpadTokens;
    address[] internal trackedFreshMarkets;
    uint256 internal extraAssetsDeployed;

    receive() external payable { }

    function setup() internal virtual override {
        deploy();

        vaultFactory = ICrystalVaultFactory(
            address(
                new CrystalVaultFactory(address(crystal), CRYSTAL_GOVERNANCE, address(weth), 0, VAULT_MAX_ORDER_CAP, 0)
            )
        );
        proxyActor = new ReconCaller();
        permitSigner = PERMIT_SIGNER;
        currentGovernance = CRYSTAL_GOVERNANCE;

        _addAsset(address(quote));
        _addAsset(address(weth));

        _fundApproveRegisterAndDeposit(address(this));
        _fundProxyApproveRegisterAndDeposit(address(proxyActor));
        _addActor(address(proxyActor));
        _addActor(CRYSTAL_GOVERNANCE);

        _seedClaimableFees();
        _seedInitialMarketState();
        _seedInitialVault();
        _seedInitialLaunchpadToken();
        _seedPermitSignerLaunchpadBalance();
    }

    modifier asActor() {
        vm.startPrank(_getActor());
        _;
        vm.stopPrank();
    }

    function _fundApproveRegisterAndDeposit(address actor) internal {
        quote.mint(actor, SETUP_QUOTE_MINT);
        vm.deal(actor, SETUP_ETH_BALANCE);

        if (actor == address(this)) {
            weth.deposit{ value: SETUP_WETH_AMOUNT }();
        } else {
            vm.prank(actor);
            weth.deposit{ value: SETUP_WETH_AMOUNT }();
        }

        _approveAll(actor);

        if (crystal.addressToUserId(actor) == 0) {
            vm.prank(actor);
            crystal.registerUser(actor);
        }

        vm.prank(actor);
        crystal.deposit(address(quote), SETUP_QUOTE_DEPOSIT);
        vm.prank(actor);
        crystal.deposit(address(weth), SETUP_WETH_DEPOSIT);
    }

    function _approveAll(address actor) internal {
        if (actor != address(this)) {
            vm.startPrank(actor);
        }

        quote.approve(address(crystal), type(uint256).max);
        quote.approve(address(vaultFactory), type(uint256).max);
        weth.approve(address(crystal), type(uint256).max);
        weth.approve(address(vaultFactory), type(uint256).max);
        market.approve(address(crystal), type(uint256).max);

        if (actor != address(this)) {
            vm.stopPrank();
        }
    }

    function _fundWalletOnly(address actor) internal {
        quote.mint(actor, SETUP_QUOTE_MINT);
        vm.deal(actor, SETUP_ETH_BALANCE);
        vm.prank(actor);
        weth.deposit{ value: SETUP_WETH_AMOUNT }();
        _approveAll(actor);
    }

    function _fundProxyApproveRegisterAndDeposit(address actor) internal {
        quote.mint(actor, SETUP_QUOTE_MINT);
        vm.deal(address(this), address(this).balance + SETUP_ETH_BALANCE);
        (bool sent,) = actor.call{ value: SETUP_ETH_BALANCE }("");
        require(sent);

        _proxyCall(actor, address(weth), SETUP_WETH_AMOUNT, abi.encodeWithSignature("deposit()"));
        _proxyCall(actor, address(quote), 0, abi.encodeCall(IERC20.approve, (address(crystal), type(uint256).max)));
        _proxyCall(actor, address(quote), 0, abi.encodeCall(IERC20.approve, (address(vaultFactory), type(uint256).max)));
        _proxyCall(actor, address(weth), 0, abi.encodeCall(IERC20.approve, (address(crystal), type(uint256).max)));
        _proxyCall(actor, address(weth), 0, abi.encodeCall(IERC20.approve, (address(vaultFactory), type(uint256).max)));
        _proxyCall(actor, address(market), 0, abi.encodeCall(IERC20.approve, (address(crystal), type(uint256).max)));

        _proxyCall(actor, address(crystal), 0, abi.encodeCall(ICrystal.registerUser, (actor)));
        _proxyCall(actor, address(crystal), 0, abi.encodeCall(ICrystal.deposit, (address(quote), SETUP_QUOTE_DEPOSIT)));
        _proxyCall(actor, address(crystal), 0, abi.encodeCall(ICrystal.deposit, (address(weth), SETUP_WETH_DEPOSIT)));
    }

    function _proxyCall(address actor, address target, uint256 value, bytes memory data)
        internal
        returns (bytes memory returnData)
    {
        return ReconCaller(payable(actor)).execute(target, value, data);
    }

    function _seedInitialMarketState() internal {
        crystal.addLiquidity(address(market), address(this), 300_000 * 1e6, 300 ether, 0, 0);

        uint256 bidPrice = _price(300);
        uint256 askPrice = _price(1_200);
        uint256 bidId = crystal.limitOrder(address(market), true, 0, bidPrice, MARKET_MIN_SIZE * 50, address(this));
        uint256 askId = crystal.limitOrder(address(market), false, 0, askPrice, 25 ether, address(this));

        _recordOrder(address(this), true, bidPrice, bidId, MARKET_MIN_SIZE * 50);
        _recordOrder(address(this), false, askPrice, askId, 25 ether);
    }

    function _seedClaimableFees() internal {
        address[] memory suiteActors = _getActors();
        uint256 amountQuote = 100 * 1e6;
        uint256 amountBase = 1 ether;
        address[] memory feeTokens = _tokens(address(quote), address(weth));
        uint256[] memory feeAmounts = _amounts(amountQuote, amountBase);

        quote.mint(address(this), amountQuote * suiteActors.length);
        vm.deal(address(this), address(this).balance + (amountBase * suiteActors.length * 2));
        weth.deposit{ value: amountBase * suiteActors.length }();
        quote.approve(address(crystal), type(uint256).max);
        weth.approve(address(crystal), type(uint256).max);

        address[] memory ethToken = new address[](1);
        ethToken[0] = crystal.eth();
        uint256[] memory ethAmount = new uint256[](1);
        ethAmount[0] = amountBase;

        for (uint256 i = 0; i < suiteActors.length; i++) {
            crystal.addClaimableFee(suiteActors[i], feeTokens, feeAmounts);
            crystal.addClaimableFee{ value: amountBase }(suiteActors[i], ethToken, ethAmount);
        }
    }

    function _seedInitialVault() internal {
        address vault = vaultFactory.deploy(
            address(quote), address(weth), MARKET_MIN_SIZE * 100, 10 ether, 0, 0, true, _metadata(1)
        );
        _recordVault(vault);
    }

    function _seedInitialLaunchpadToken() internal {
        address token = crystal.createToken{ value: LAUNCHPAD_FEE }(
            "Recon Seed Token", "RST", "recon", "stateful invariant seed token", "", "", "", ""
        );
        _recordLaunchpadToken(token);
    }

    function _seedPermitSignerLaunchpadBalance() internal {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address token = trackedLaunchpadTokens[0];
        uint256 amountIn = 1 ether;
        vm.deal(permitSigner, SETUP_ETH_BALANCE);
        (, uint256 amountOut,) = crystal.quoteBuy(true, token, amountIn, 0);
        if (amountOut == 0) {
            return;
        }

        crystal.buy{ value: amountIn }(true, token, amountIn, 0);
        IERC20(token).transfer(permitSigner, amountOut / 2);
    }

    function _actor(uint256) internal view returns (address) {
        return _getActor();
    }

    function _actors() internal view returns (address[] memory) {
        return _getActors();
    }

    function _trackedVault(uint256 seed) internal view returns (address) {
        return trackedVaults[seed % trackedVaults.length];
    }

    function _trackedLaunchpadToken(uint256 seed) internal view returns (address) {
        return trackedLaunchpadTokens[seed % trackedLaunchpadTokens.length];
    }

    function _trackedFreshMarket(uint256 seed) internal view returns (address) {
        return trackedFreshMarkets[seed % trackedFreshMarkets.length];
    }

    function _path(address tokenIn, address tokenOut) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    function _tokens(address tokenA, address tokenB) internal pure returns (address[] memory tokens) {
        tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
    }

    function _amounts(uint256 amountA, uint256 amountB) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amountA;
        amounts[1] = amountB;
    }

    function _recipient(address actor, uint256 seed) internal view returns (address recipient) {
        recipient = _actor(seed);
        if (recipient == actor) {
            address[] memory suiteActors = _getActors();
            recipient = suiteActors[seed % suiteActors.length];
        }
        if (recipient == actor) {
            recipient = address(0xBEEF);
        }
    }

    function _secondaryActor(address primary) internal view returns (address) {
        address secondary = address(proxyActor);
        if (primary != secondary && crystal.addressToUserId(secondary) != 0) {
            return secondary;
        }
        return address(this);
    }

    function _metadata(uint256 seed) internal pure returns (ICrystalVault.VaultMetaData memory) {
        string memory suffix = _smallUintString(seed % 1_000_000);
        return ICrystalVault.VaultMetaData({
            name: string.concat("Recon Vault ", suffix),
            description: "stateful invariant vault",
            social1: "",
            social2: "",
            social3: ""
        });
    }

    function _smallUintString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _recordOrder(address owner, bool isBuy, uint256 price, uint256 id, uint256 size) internal {
        _recordOrderWithMetadata(
            owner,
            isBuy,
            price,
            id,
            0,
            size,
            isBuy ? address(quote) : address(weth),
            isBuy ? address(weth) : address(quote)
        );
    }

    function _recordOrderWithCloid(address owner, bool isBuy, uint256 price, uint256 id, uint256 cloid, uint256 size)
        internal
    {
        _recordOrderWithMetadata(
            owner,
            isBuy,
            price,
            id,
            cloid,
            size,
            isBuy ? address(quote) : address(weth),
            isBuy ? address(weth) : address(quote)
        );
    }

    function _recordOrderWithTokens(
        address owner,
        bool isBuy,
        uint256 price,
        uint256 id,
        uint256 size,
        address tokenIn,
        address tokenOut
    ) internal {
        _recordOrderWithMetadata(owner, isBuy, price, id, 0, size, tokenIn, tokenOut);
    }

    function _recordOrderWithMetadata(
        address owner,
        bool isBuy,
        uint256 price,
        uint256 id,
        uint256 cloid,
        uint256 size,
        address tokenIn,
        address tokenOut
    ) internal {
        if (id == 0) {
            return;
        }

        uint256 ownerUserId = crystal.addressToUserId(owner);
        if (ownerUserId == 0) {
            return;
        }

        ICrystal.Order memory order = crystal.getOrder(address(market), price, id);
        if (order.size == 0 || order.userId != ownerUserId || order.isBuy != isBuy) {
            return;
        }

        TrackedOrder memory tracked = TrackedOrder({
            owner: owner,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            isBuy: isBuy,
            price: price,
            id: id,
            cloid: cloid,
            minQuoteAtPlacement: crystal.getMarket(address(market)).minSize,
            size: order.size,
            live: true
        });
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (!trackedOrders[i].live) {
                trackedOrders[i] = tracked;
                return;
            }
        }

        if (trackedOrders.length < MAX_TRACKED_ORDERS) {
            trackedOrders.push(tracked);
        }
    }

    function _singleAction(BatchAction action, uint256 param1, uint256 param2, uint256 param3)
        internal
        pure
        returns (ICrystal.Action[] memory actions)
    {
        actions = new ICrystal.Action[](1);
        actions[0] = ICrystal.Action({
            isRequireSuccess: true, action: uint256(action), param1: param1, param2: param2, param3: param3
        });
    }

    function _recordVault(address vault) internal {
        if (vault != address(0) && trackedVaults.length < MAX_TRACKED_VAULTS) {
            trackedVaults.push(vault);
        }
    }

    function _recordLaunchpadToken(address token) internal {
        if (token != address(0) && trackedLaunchpadTokens.length < MAX_TRACKED_LAUNCHPAD_TOKENS) {
            trackedLaunchpadTokens.push(token);
        }
    }

    function _recordFreshMarket(address marketAddress) internal {
        if (marketAddress != address(0) && trackedFreshMarkets.length < MAX_TRACKED_FRESH_MARKETS) {
            trackedFreshMarkets.push(marketAddress);
        }
    }

    function _syncTrackedOrders() internal {
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (!trackedOrders[i].live) {
                continue;
            }

            ICrystal.Order memory order = crystal.getOrder(address(market), trackedOrders[i].price, trackedOrders[i].id);
            if (
                order.size == 0 || order.userId != crystal.addressToUserId(trackedOrders[i].owner)
                    || order.isBuy != trackedOrders[i].isBuy
            ) {
                trackedOrders[i].live = false;
                trackedOrders[i].size = 0;
            } else {
                trackedOrders[i].size = order.size;
            }
        }
    }

    function _selectLiveOrder(uint256 seed) internal view returns (bool found, uint256 index) {
        uint256 liveCount;
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (trackedOrders[i].live) {
                liveCount++;
            }
        }
        if (liveCount == 0) {
            return (false, 0);
        }

        uint256 target = seed % liveCount;
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (!trackedOrders[i].live) {
                continue;
            }
            if (target == 0) {
                return (true, i);
            }
            target--;
        }
    }

    function _selectLiveOrderFor(address owner, uint256 seed) internal view returns (bool found, uint256 index) {
        uint256 liveCount;
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (trackedOrders[i].live && trackedOrders[i].owner == owner) {
                liveCount++;
            }
        }
        if (liveCount == 0) {
            return (false, 0);
        }

        uint256 target = seed % liveCount;
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (!trackedOrders[i].live || trackedOrders[i].owner != owner) {
                continue;
            }
            if (target == 0) {
                return (true, i);
            }
            target--;
        }
    }

    function _selectLiveCloidOrderFor(address owner, uint256 seed) internal view returns (bool found, uint256 index) {
        uint256 liveCount;
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (trackedOrders[i].live && trackedOrders[i].owner == owner && trackedOrders[i].cloid != 0) {
                liveCount++;
            }
        }
        if (liveCount == 0) {
            return (false, 0);
        }

        uint256 target = seed % liveCount;
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (!trackedOrders[i].live || trackedOrders[i].owner != owner || trackedOrders[i].cloid == 0) {
                continue;
            }
            if (target == 0) {
                return (true, i);
            }
            target--;
        }
    }

    function _canTrackOrder() internal view returns (bool) {
        if (trackedOrders.length < MAX_TRACKED_ORDERS) {
            return true;
        }

        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (!trackedOrders[i].live) {
                return true;
            }
        }

        return false;
    }

    function _available(address actor, address token) internal view returns (uint256 availableBalance) {
        (, availableBalance,) = crystal.getDepositedBalance(actor, token);
    }

    function _totalInternal(address actor, address token)
        internal
        view
        returns (uint256 totalBalance, uint256 availableBalance, uint256 lockedBalance)
    {
        (totalBalance, availableBalance, lockedBalance) = crystal.getDepositedBalance(actor, token);
    }

    function _price(uint256 quotePerBase) internal view returns (uint256) {
        return (quotePerBase * 1e6 * market.scaleFactor()) / 1 ether;
    }

    function _priceFromSeed(uint256 seed) internal view returns (uint256) {
        return _price(200 + (seed % 1_001));
    }

    function _nonCrossingBid(uint256 seed) internal view returns (uint256 price, bool ok) {
        price = _priceFromSeed(seed);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        if (info.lowestAsk != 0 && price >= info.lowestAsk) {
            return (price, false);
        }
        return (price, true);
    }

    function _nonCrossingAsk(uint256 seed) internal view returns (uint256 price, bool ok) {
        price = _priceFromSeed(seed);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        if (info.highestBid != 0 && price <= info.highestBid) {
            return (price, false);
        }
        return (price, true);
    }

    function _minBaseForQuote(uint256 quoteAmount, uint256 price) internal view returns (uint256) {
        uint256 numerator = quoteAmount * market.scaleFactor();
        return (numerator + price - 1) / price;
    }

    function _quoteValue(uint256 baseAmount, uint256 price) internal view returns (uint256) {
        return (baseAmount * price) / market.scaleFactor();
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
