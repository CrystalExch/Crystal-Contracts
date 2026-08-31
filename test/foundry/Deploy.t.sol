// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Crystal } from "../../contracts/core/Crystal.sol";
import { CrystalMarket } from "../../contracts/core/CrystalMarket.sol";
import { ICrystal } from "../../contracts/interfaces/ICrystal.sol";
import { TestToken } from "../../contracts/mocks/TestToken.sol";
import { WETH } from "../../contracts/mocks/TestToken.sol";
import { CrystalDeploymentConfig } from "./scripts/CrystalDeploymentConfig.sol";
import { DeployCrystalScript } from "./scripts/DeployCrystal.s.sol";
import { DeployTestTokenScript } from "./scripts/DeployTestToken.s.sol";
import { DeployWETHScript } from "./scripts/DeployWETH.s.sol";

abstract contract Deploy {
    address internal constant CRYSTAL_GOVERNANCE = address(0x1000);

    string internal constant QUOTE_NAME = "Quote Token";
    string internal constant QUOTE_SYMBOL = "QUOTE";
    uint8 internal constant QUOTE_DECIMALS = 6;

    uint8 internal constant FEE_COMMISSION = 10;
    uint256 internal constant FEE_CLAIM_DURATION = 1 days;
    uint112 internal constant LAUNCHPAD_INITIAL_NATIVE_SUPPLY = uint112(1_000e18);
    uint256 internal constant LAUNCHPAD_FEE = 99_000;
    uint256 internal constant LAUNCHPAD_CREATOR_FEE_SPLIT = 5;
    uint256 internal constant GRADUATED_MIN_SIZE = 1 ether;
    uint256 internal constant GRADUATED_TAKER_FEE = 99_920;
    uint256 internal constant GRADUATED_MAKER_REBATE = 99_990;
    uint256 internal constant GRADUATED_CREATOR_FEE_SPLIT = 40;

    bool internal constant MARKET_IS_CANONICAL = false;
    uint256 internal constant MARKET_TYPE_LOGARITHMIC_AMM = 2;
    uint256 internal constant MARKET_SCALE_FACTOR = 21;
    uint256 internal constant MARKET_TICK_SIZE = 1;
    uint256 internal constant MARKET_MAX_PRICE = 1_000_000_000_000_000;
    uint256 internal constant MARKET_MIN_SIZE = 1_000_000;
    uint24 internal constant MARKET_TAKER_FEE = 99_970;
    uint24 internal constant MARKET_MAKER_REBATE = 99_990;

    Crystal internal crystal;
    CrystalMarket internal market;
    TestToken internal quote;
    WETH internal weth;

    function deploy() internal virtual {
        DeployWETHScript wethDeploymentScript = new DeployWETHScript();
        weth = wethDeploymentScript.deploy();

        DeployTestTokenScript tokenDeploymentScript = new DeployTestTokenScript();
        quote = tokenDeploymentScript.deploy(_tokenConfig());

        DeployCrystalScript crystalDeploymentScript = new DeployCrystalScript();
        crystal = crystalDeploymentScript.deploy(_crystalConfig());

        market = _deployMarket();
    }

    function _tokenConfig() internal pure returns (DeployTestTokenScript.TokenConfig memory) {
        return DeployTestTokenScript.TokenConfig({ name: QUOTE_NAME, symbol: QUOTE_SYMBOL, decimals: QUOTE_DECIMALS });
    }

    function _crystalConfig() internal view returns (CrystalDeploymentConfig.CrystalConfig memory) {
        return CrystalDeploymentConfig.CrystalConfig({
            weth: address(weth),
            governance: CRYSTAL_GOVERNANCE,
            feeRecipient: address(this),
            feeCommission: FEE_COMMISSION,
            feeClaimDuration: FEE_CLAIM_DURATION,
            launchpadParams: _launchpadParams()
        });
    }

    function _deployMarket() internal returns (CrystalMarket) {
        address marketAddress = crystal.deploy(
            MARKET_IS_CANONICAL,
            address(quote),
            address(weth),
            MARKET_TYPE_LOGARITHMIC_AMM,
            MARKET_SCALE_FACTOR,
            MARKET_TICK_SIZE,
            MARKET_MAX_PRICE,
            MARKET_MIN_SIZE,
            MARKET_TAKER_FEE,
            MARKET_MAKER_REBATE
        );

        return CrystalMarket(payable(marketAddress));
    }

    function _launchpadParams() private pure returns (ICrystal.LaunchpadParams memory) {
        return ICrystal.LaunchpadParams({
            launchpadInitialNativeSupply: LAUNCHPAD_INITIAL_NATIVE_SUPPLY,
            launchpadFee: LAUNCHPAD_FEE,
            launchpadCreatorFeeSplit: LAUNCHPAD_CREATOR_FEE_SPLIT,
            graduatedMinSize: GRADUATED_MIN_SIZE,
            graduatedTakerFee: GRADUATED_TAKER_FEE,
            graduatedMakerRebate: GRADUATED_MAKER_REBATE,
            graduatedCreatorFeeSplit: GRADUATED_CREATOR_FEE_SPLIT
        });
    }
}
