// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from '../types/DataTypes.sol';
import {Errors} from '../helpers/Errors.sol';
import {ReserveConfiguration} from '../configuration/ReserveConfiguration.sol';
import {PercentageMath} from '../math/PercentageMath.sol';
import {WadRayMath} from '../math/WadRayMath.sol';
import {IAToken} from '../../interfaces/IAToken.sol';
import {IStableDebtToken} from '../../interfaces/IStableDebtToken.sol';
import {IVariableDebtToken} from '../../interfaces/IVariableDebtToken.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {IInterestRateStrategy} from '../../interfaces/IInterestRateStrategy.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title LiquidationLogic
 * @notice Handles liquidation of undercollateralized positions
 * @dev When a user's health factor drops below 1.0, liquidators can repay
 * part of their debt in exchange for collateral + bonus
 * 
 * Liquidation Process:
 * 1. Check user is liquidatable (HF < 1.0)
 * 2. Calculate max debt to cover (up to 50% close factor)
 * 3. Calculate collateral to seize (debt value + liquidation bonus)
 * 4. Transfer debt repayment from liquidator
 * 5. Burn user's debt tokens
 * 6. Transfer/burn collateral to liquidator
 * 7. Update interest rates
 */
library LiquidationLogic {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    
    // ============ Constants ============
    
    uint256 public constant CLOSE_FACTOR_HF_THRESHOLD = 0.95e18;
    uint256 public constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 5000; // 50%
    uint256 public constant MAX_LIQUIDATION_CLOSE_FACTOR = 10000; // 100%
    
    // ============ Events ============
    
    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken
    );
    
    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );
    
    // ============ Structs ============
    
    struct LiquidationCallLocalVars {
        uint256 userCollateralBalance;
        uint256 userStableDebt;
        uint256 userVariableDebt;
        uint256 userTotalDebt;
        uint256 maxDebtToCover;
        uint256 actualDebtToLiquidate;
        uint256 collateralPrice;
        uint256 debtPrice;
        uint256 collateralDecimals;
        uint256 debtDecimals;
        uint256 collateralToSeize;
        uint256 liquidationBonus;
        uint256 liquidationProtocolFee;
        uint256 protocolFeeAmount;
        uint256 healthFactor;
        IAToken collateralAToken;
        IVariableDebtToken variableDebtToken;
        IStableDebtToken stableDebtToken;
    }
    
    // ============ Validation ============
    
    /**
     * @notice Validate liquidation call
     * @param collateralReserve The collateral reserve
     * @param debtReserve The debt reserve
     * @param userHealthFactor User's health factor
     * @param userStableDebt User's stable debt
     * @param userVariableDebt User's variable debt
     */
    function validateLiquidationCall(
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage debtReserve,
        uint256 userHealthFactor,
        uint256 userStableDebt,
        uint256 userVariableDebt
    ) internal view {
        (bool collateralActive, , , , bool collateralPaused) = 
            collateralReserve.configuration.getFlags();
        (bool debtActive, , , , bool debtPaused) = 
            debtReserve.configuration.getFlags();
        
        require(collateralActive, Errors.RESERVE_INACTIVE);
        require(debtActive, Errors.RESERVE_INACTIVE);
        require(!collateralPaused, Errors.RESERVE_PAUSED);
        require(!debtPaused, Errors.RESERVE_PAUSED);
        
        require(userHealthFactor < 1e18, Errors.HEALTH_FACTOR_NOT_BELOW_THRESHOLD);
        require(userStableDebt > 0 || userVariableDebt > 0, Errors.SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER);
    }
    
    // ============ Main Functions ============
    
    /**
     * @notice Execute liquidation call
     * @param collateralReserve The collateral reserve data
     * @param debtReserve The debt reserve data
     * @param params The liquidation parameters
     * @param oracle The price oracle address
     * @return actualDebtToLiquidate Amount of debt actually liquidated
     * @return actualCollateralToSeize Amount of collateral seized
     */
    function executeLiquidationCall(
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage debtReserve,
        DataTypes.ExecuteLiquidationCallParams memory params,
        address oracle
    ) internal returns (uint256, uint256) {
        LiquidationCallLocalVars memory vars;
        
        // Get user's collateral and debt balances
        vars.collateralAToken = IAToken(collateralReserve.aTokenAddress);
        vars.variableDebtToken = IVariableDebtToken(debtReserve.variableDebtTokenAddress);
        vars.stableDebtToken = IStableDebtToken(debtReserve.stableDebtTokenAddress);
        
        vars.userCollateralBalance = vars.collateralAToken.balanceOf(params.user);
        vars.userVariableDebt = vars.variableDebtToken.balanceOf(params.user);
        vars.userStableDebt = vars.stableDebtToken.balanceOf(params.user);
        vars.userTotalDebt = vars.userVariableDebt + vars.userStableDebt;
        
        require(vars.userCollateralBalance > 0, Errors.COLLATERAL_CANNOT_BE_LIQUIDATED);
        require(vars.userTotalDebt > 0, Errors.SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER);
        
        // Get prices from oracle
        vars.collateralPrice = IPriceOracle(oracle).getAssetPrice(params.collateralAsset);
        vars.debtPrice = IPriceOracle(oracle).getAssetPrice(params.debtAsset);
        
        require(vars.collateralPrice > 0 && vars.debtPrice > 0, Errors.ORACLE_ERROR);
        
        // Get decimals and liquidation parameters
        (
            ,
            ,
            vars.liquidationBonus,
            vars.collateralDecimals,
            
        ) = collateralReserve.configuration.getParams();
        
        vars.debtDecimals = debtReserve.configuration.getDecimals();
        vars.liquidationProtocolFee = collateralReserve.configuration.getLiquidationProtocolFee();
        
        // Calculate max debt to cover based on close factor
        vars.maxDebtToCover = _calculateMaxDebtToCover(vars.userTotalDebt, vars.healthFactor);
        
        // Actual debt to liquidate is min of requested and max allowed
        vars.actualDebtToLiquidate = params.debtToCover > vars.maxDebtToCover
            ? vars.maxDebtToCover
            : params.debtToCover;
        
        // Calculate collateral to seize
        vars.collateralToSeize = _calculateCollateralToSeize(
            vars.collateralPrice,
            vars.debtPrice,
            vars.actualDebtToLiquidate,
            vars.collateralDecimals,
            vars.debtDecimals,
            vars.liquidationBonus
        );
        
        // If not enough collateral, reduce debt to cover
        if (vars.collateralToSeize > vars.userCollateralBalance) {
            vars.collateralToSeize = vars.userCollateralBalance;
            vars.actualDebtToLiquidate = _calculateDebtFromCollateral(
                vars.collateralPrice,
                vars.debtPrice,
                vars.collateralToSeize,
                vars.collateralDecimals,
                vars.debtDecimals,
                vars.liquidationBonus
            );
        }
        
        // Calculate protocol fee
        if (vars.liquidationProtocolFee > 0) {
            vars.protocolFeeAmount = vars.collateralToSeize.percentMul(vars.liquidationProtocolFee);
            vars.collateralToSeize -= vars.protocolFeeAmount;
        }
        
        // Transfer debt from liquidator to aToken (repaying the debt)
        IERC20(params.debtAsset).safeTransferFrom(
            msg.sender,
            debtReserve.aTokenAddress,
            vars.actualDebtToLiquidate
        );
        
        // Burn debt tokens (variable first, then stable)
        _burnDebtTokens(
            vars.variableDebtToken,
            vars.stableDebtToken,
            params.user,
            vars.actualDebtToLiquidate,
            vars.userVariableDebt,
            debtReserve.variableBorrowIndex
        );
        
        // Update debt reserve liquidity
        debtReserve.availableLiquidity += vars.actualDebtToLiquidate;
        
        // Transfer or burn collateral
        if (params.receiveAToken) {
            // Transfer aTokens to liquidator
            vars.collateralAToken.transferFrom(params.user, msg.sender, vars.collateralToSeize);
        } else {
            // Burn aTokens and transfer underlying to liquidator
            vars.collateralAToken.burn(
                params.user,
                msg.sender,
                vars.collateralToSeize,
                collateralReserve.liquidityIndex
            );
            collateralReserve.availableLiquidity -= vars.collateralToSeize;
        }
        
        // Update interest rates for both reserves
        _updateInterestRates(collateralReserve, params.collateralAsset);
        _updateInterestRates(debtReserve, params.debtAsset);
        
        emit LiquidationCall(
            params.collateralAsset,
            params.debtAsset,
            params.user,
            vars.actualDebtToLiquidate,
            vars.collateralToSeize,
            msg.sender,
            params.receiveAToken
        );
        
        return (vars.actualDebtToLiquidate, vars.collateralToSeize);
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Calculate max debt that can be covered
     */
    function _calculateMaxDebtToCover(
        uint256 userTotalDebt,
        uint256 healthFactor
    ) internal pure returns (uint256) {
        if (healthFactor < CLOSE_FACTOR_HF_THRESHOLD) {
            return userTotalDebt;
        }
        return userTotalDebt.percentMul(DEFAULT_LIQUIDATION_CLOSE_FACTOR);
    }
    
    /**
     * @notice Calculate collateral to seize for given debt
     */
    function _calculateCollateralToSeize(
        uint256 collateralPrice,
        uint256 debtPrice,
        uint256 debtAmount,
        uint256 collateralDecimals,
        uint256 debtDecimals,
        uint256 liquidationBonus
    ) internal pure returns (uint256) {
        uint256 debtValueInBase = (debtAmount * debtPrice) / (10 ** debtDecimals);
        uint256 collateralValueInBase = debtValueInBase.percentMul(liquidationBonus);
        return (collateralValueInBase * (10 ** collateralDecimals)) / collateralPrice;
    }
    
    /**
     * @notice Calculate debt amount for given collateral
     */
    function _calculateDebtFromCollateral(
        uint256 collateralPrice,
        uint256 debtPrice,
        uint256 collateralAmount,
        uint256 collateralDecimals,
        uint256 debtDecimals,
        uint256 liquidationBonus
    ) internal pure returns (uint256) {
        uint256 collateralValueInBase = (collateralAmount * collateralPrice) / (10 ** collateralDecimals);
        uint256 debtValueInBase = collateralValueInBase.percentDiv(liquidationBonus);
        return (debtValueInBase * (10 ** debtDecimals)) / debtPrice;
    }
    
    /**
     * @notice Burn debt tokens for liquidation
     */
    function _burnDebtTokens(
        IVariableDebtToken variableDebtToken,
        IStableDebtToken stableDebtToken,
        address user,
        uint256 amount,
        uint256 variableDebt,
        uint256 variableBorrowIndex
    ) internal {
        if (variableDebt >= amount) {
            variableDebtToken.burn(user, amount, variableBorrowIndex);
        } else {
            if (variableDebt > 0) {
                variableDebtToken.burn(user, variableDebt, variableBorrowIndex);
            }
            stableDebtToken.burn(user, amount - variableDebt);
        }
    }
    
    /**
     * @notice Update interest rates after liquidation
     */
    function _updateInterestRates(
        DataTypes.ReserveData storage reserve,
        address asset
    ) internal {
        uint256 totalStableDebt = IStableDebtToken(reserve.stableDebtTokenAddress).totalSupply();
        uint256 totalVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).totalSupply();
        uint256 totalDebt = totalStableDebt + totalVariableDebt;
        
        (
            uint256 newLiquidityRate,
            uint256 newVariableRate,
            uint256 newStableRate
        ) = IInterestRateStrategy(reserve.interestRateStrategyAddress).calculateInterestRate(
            reserve.availableLiquidity,
            totalDebt
        );
        
        reserve.currentLiquidityRate = uint128(newLiquidityRate);
        reserve.currentVariableBorrowRate = uint128(newVariableRate);
        reserve.currentStableBorrowRate = uint128(newStableRate);
        
        emit ReserveDataUpdated(
            asset,
            newLiquidityRate,
            newStableRate,
            newVariableRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex
        );
    }
}
