// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from "../types/DataTypes.sol";
import {ReserveConfiguration} from "../configuration/ReserveConfiguration.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {IAToken} from "../../interfaces/IAToken.sol";
import {IVariableDebtToken} from "../../interfaces/IVariableDebtToken.sol";
import {IStableDebtToken} from "../../interfaces/IStableDebtToken.sol";

/**
 * @title HealthFactor
 * @notice Library for health factor calculations
 * @dev Health factor determines if a position can be liquidated
 * 
 * Health Factor Formula:
 * HF = (Σ collateralᵢ × priceᵢ × liquidationThresholdᵢ) / (Σ debtⱼ × priceⱼ)
 * 
 * Where:
 * - collateralᵢ = user's aToken balance for asset i
 * - priceᵢ = USD price of asset i (8 decimals)
 * - liquidationThresholdᵢ = threshold for asset i (e.g., 8000 = 80%)
 * - debtⱼ = user's debt balance for asset j
 * - priceⱼ = USD price of asset j
 * 
 * If HF < 1e18 (1.0), the position is liquidatable
 */
library HealthFactor {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    
    // ============ Constants ============
    
    /// @notice Health factor below this threshold means position is liquidatable
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // 1.0
    
    /// @notice Minimum health factor after any borrow/withdraw operation
    uint256 public constant MINIMUM_HEALTH_FACTOR = 1e18; // 1.0
    
    /// @notice Maximum health factor value (no debt = infinite health)
    uint256 public constant MAX_HEALTH_FACTOR = type(uint256).max;
    
    // ============ Structs ============
    
    struct CalculateHealthFactorVars {
        uint256 i;
        uint256 assetPrice;
        uint256 assetUnit;
        uint256 userBalanceInBaseCurrency;
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 reserveFactor;
    }
    
    struct UserAccountVars {
        uint256 totalCollateralInBaseCurrency;
        uint256 totalDebtInBaseCurrency;
        uint256 avgLtv;
        uint256 avgLiquidationThreshold;
        uint256 healthFactor;
        uint256 availableBorrowsInBaseCurrency;
        bool hasZeroLtvCollateral;
    }
    
    // ============ Core Functions ============
    
    /**
     * @notice Calculate health factor from collateral and debt balances
     * @param totalCollateralInBaseCurrency Total collateral value in USD (8 decimals)
     * @param totalDebtInBaseCurrency Total debt value in USD (8 decimals)
     * @param liquidationThreshold Weighted avg liquidation threshold (basis points)
     * @return The health factor scaled by 1e18 (1.0 = 1e18)
     * 
     * @dev Formula: HF = (collateral * liquidationThreshold / 10000) / debt * 1e18
     * @dev Returns MAX_HEALTH_FACTOR if debt is 0
     */
    function calculateHealthFactorFromBalances(
        uint256 totalCollateralInBaseCurrency,
        uint256 totalDebtInBaseCurrency,
        uint256 liquidationThreshold
    ) internal pure returns (uint256) {
        if (totalDebtInBaseCurrency == 0) {
            return MAX_HEALTH_FACTOR;
        }
        
        // Apply liquidation threshold to collateral
        // liquidationThreshold is in basis points (e.g., 8000 = 80%)
        uint256 adjustedCollateral = totalCollateralInBaseCurrency.percentMul(liquidationThreshold);
        
        // Calculate health factor with 1e18 precision
        // HF = adjustedCollateral * 1e18 / debt
        return (adjustedCollateral * 1e18) / totalDebtInBaseCurrency;
    }
    
    /**
     * @notice Calculate user's complete account data across all reserves
     * @param user The user address
     * @param reservesData Mapping of all reserves
     * @param reservesList Array of reserve addresses
     * @param oracle The price oracle address
     * @return totalCollateralInBaseCurrency Total collateral in base currency
     * @return totalDebtInBaseCurrency Total debt in base currency
     * @return availableBorrowsInBaseCurrency Remaining borrowing power
     * @return currentLiquidationThreshold Weighted avg liquidation threshold
     * @return currentLtv Weighted avg LTV
     * @return healthFactor The health factor
     */
    function calculateUserAccountData(
        address user,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        address[] storage reservesList,
        address oracle
    )
        internal
        view
        returns (
            uint256 totalCollateralInBaseCurrency,
            uint256 totalDebtInBaseCurrency,
            uint256 availableBorrowsInBaseCurrency,
            uint256 currentLiquidationThreshold,
            uint256 currentLtv,
            uint256 healthFactor
        )
    {
        if (reservesList.length == 0) {
            return (0, 0, 0, 0, 0, MAX_HEALTH_FACTOR);
        }
        
        UserAccountVars memory vars;
        CalculateHealthFactorVars memory calcVars;
        
        // Iterate through all reserves
        for (calcVars.i = 0; calcVars.i < reservesList.length; calcVars.i++) {
            address currentReserveAddress = reservesList[calcVars.i];
            
            if (currentReserveAddress == address(0)) {
                continue;
            }
            
            DataTypes.ReserveData storage currentReserve = reservesData[currentReserveAddress];
            
            // Get reserve configuration
            (
                calcVars.ltv,
                calcVars.liquidationThreshold,
                calcVars.liquidationBonus,
                calcVars.decimals,
                calcVars.reserveFactor
            ) = currentReserve.configuration.getParams();
            
            calcVars.assetUnit = 10 ** calcVars.decimals;
            
            // Get asset price from oracle
            calcVars.assetPrice = IPriceOracle(oracle).getAssetPrice(currentReserveAddress);
            
            // ============ Calculate Collateral ============
            if (calcVars.liquidationThreshold != 0 && currentReserve.aTokenAddress != address(0)) {
                uint256 userBalance = IAToken(currentReserve.aTokenAddress).balanceOf(user);
                
                if (userBalance > 0) {
                    // Convert balance to base currency (USD)
                    calcVars.userBalanceInBaseCurrency = 
                        (calcVars.assetPrice * userBalance) / calcVars.assetUnit;
                    
                    vars.totalCollateralInBaseCurrency += calcVars.userBalanceInBaseCurrency;
                    
                    // Accumulate weighted LTV and liquidation threshold
                    vars.avgLtv += calcVars.userBalanceInBaseCurrency * calcVars.ltv;
                    vars.avgLiquidationThreshold += 
                        calcVars.userBalanceInBaseCurrency * calcVars.liquidationThreshold;
                }
            } else if (calcVars.ltv == 0) {
                // Track if user has collateral that can't be borrowed against
                vars.hasZeroLtvCollateral = true;
            }
            
            // ============ Calculate Variable Debt ============
            if (currentReserve.variableDebtTokenAddress != address(0)) {
                uint256 userVariableDebt = IVariableDebtToken(currentReserve.variableDebtTokenAddress)
                    .balanceOf(user);
                
                if (userVariableDebt > 0) {
                    vars.totalDebtInBaseCurrency += 
                        (calcVars.assetPrice * userVariableDebt) / calcVars.assetUnit;
                }
            }
            
            // ============ Calculate Stable Debt ============
            if (currentReserve.stableDebtTokenAddress != address(0)) {
                uint256 userStableDebt = IStableDebtToken(currentReserve.stableDebtTokenAddress)
                    .balanceOf(user);
                
                if (userStableDebt > 0) {
                    vars.totalDebtInBaseCurrency += 
                        (calcVars.assetPrice * userStableDebt) / calcVars.assetUnit;
                }
            }
        }
        
        // ============ Calculate Weighted Averages ============
        if (vars.totalCollateralInBaseCurrency > 0) {
            vars.avgLtv = vars.avgLtv / vars.totalCollateralInBaseCurrency;
            vars.avgLiquidationThreshold = 
                vars.avgLiquidationThreshold / vars.totalCollateralInBaseCurrency;
        }
        
        // ============ Calculate Health Factor ============
        vars.healthFactor = calculateHealthFactorFromBalances(
            vars.totalCollateralInBaseCurrency,
            vars.totalDebtInBaseCurrency,
            vars.avgLiquidationThreshold
        );
        
        // ============ Calculate Available Borrows ============
        vars.availableBorrowsInBaseCurrency = calculateAvailableBorrows(
            vars.totalCollateralInBaseCurrency,
            vars.totalDebtInBaseCurrency,
            vars.avgLtv
        );
        
        return (
            vars.totalCollateralInBaseCurrency,
            vars.totalDebtInBaseCurrency,
            vars.availableBorrowsInBaseCurrency,
            vars.avgLiquidationThreshold,
            vars.avgLtv,
            vars.healthFactor
        );
    }
    
    /**
     * @notice Calculate available borrowing power
     * @param totalCollateralInBaseCurrency Total collateral in base currency
     * @param totalDebtInBaseCurrency Total debt in base currency
     * @param avgLtv Weighted average LTV (basis points)
     * @return Available borrowing power in base currency
     */
    function calculateAvailableBorrows(
        uint256 totalCollateralInBaseCurrency,
        uint256 totalDebtInBaseCurrency,
        uint256 avgLtv
    ) internal pure returns (uint256) {
        // Max borrow = collateral * LTV
        uint256 maxBorrowInBaseCurrency = totalCollateralInBaseCurrency.percentMul(avgLtv);
        
        if (maxBorrowInBaseCurrency <= totalDebtInBaseCurrency) {
            return 0;
        }
        
        return maxBorrowInBaseCurrency - totalDebtInBaseCurrency;
    }
    
    /**
     * @notice Check if health factor is above liquidation threshold
     * @param healthFactor The health factor to check
     * @return True if position is safe (not liquidatable)
     */
    function isHealthFactorSafe(uint256 healthFactor) internal pure returns (bool) {
        return healthFactor >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }
    
    /**
     * @notice Check if a position is liquidatable
     * @param healthFactor The health factor to check
     * @return True if position can be liquidated
     */
    function isLiquidatable(uint256 healthFactor) internal pure returns (bool) {
        return healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }
    
    /**
     * @notice Calculate health factor after a potential operation
     * @param currentCollateral Current total collateral in base currency
     * @param currentDebt Current total debt in base currency
     * @param liquidationThreshold Weighted avg liquidation threshold
     * @param collateralChange Change in collateral (negative for withdrawal)
     * @param debtChange Change in debt (positive for new borrow)
     * @return The resulting health factor
     */
    function calculateHealthFactorAfterOperation(
        uint256 currentCollateral,
        uint256 currentDebt,
        uint256 liquidationThreshold,
        int256 collateralChange,
        int256 debtChange
    ) internal pure returns (uint256) {
        uint256 newCollateral;
        uint256 newDebt;
        
        // Apply collateral change
        if (collateralChange >= 0) {
            newCollateral = currentCollateral + uint256(collateralChange);
        } else {
            uint256 decrease = uint256(-collateralChange);
            require(currentCollateral >= decrease, "Invalid collateral decrease");
            newCollateral = currentCollateral - decrease;
        }
        
        // Apply debt change
        if (debtChange >= 0) {
            newDebt = currentDebt + uint256(debtChange);
        } else {
            uint256 decrease = uint256(-debtChange);
            require(currentDebt >= decrease, "Invalid debt decrease");
            newDebt = currentDebt - decrease;
        }
        
        return calculateHealthFactorFromBalances(newCollateral, newDebt, liquidationThreshold);
    }
    
    /**
     * @notice Validate that health factor will remain above minimum after operation
     * @param currentCollateral Current collateral in base currency
     * @param currentDebt Current debt in base currency
     * @param liquidationThreshold Weighted avg liquidation threshold
     * @param collateralChange Change in collateral
     * @param debtChange Change in debt
     * @return True if operation is safe
     */
    function validateHealthFactor(
        uint256 currentCollateral,
        uint256 currentDebt,
        uint256 liquidationThreshold,
        int256 collateralChange,
        int256 debtChange
    ) internal pure returns (bool) {
        uint256 newHealthFactor = calculateHealthFactorAfterOperation(
            currentCollateral,
            currentDebt,
            liquidationThreshold,
            collateralChange,
            debtChange
        );
        
        return isHealthFactorSafe(newHealthFactor);
    }
    
    /**
     * @notice Calculate the maximum amount that can be withdrawn while keeping HF >= 1
     * @param totalCollateral Current total collateral in base currency
     * @param totalDebt Current total debt in base currency
     * @param liquidationThreshold Weighted avg liquidation threshold
     * @param assetPrice Price of the asset to withdraw
     * @param assetDecimals Decimals of the asset
     * @param assetLiqThreshold Liquidation threshold of the asset
     * @return Maximum withdrawable amount in asset units
     */
    function calculateMaxWithdrawable(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 liquidationThreshold,
        uint256 assetPrice,
        uint256 assetDecimals,
        uint256 assetLiqThreshold
    ) internal pure returns (uint256) {
        if (totalDebt == 0) {
            // No debt = can withdraw everything
            return type(uint256).max;
        }
        
        // Current adjusted collateral = collateral * avgLiqThreshold
        uint256 currentAdjustedCollateral = totalCollateral.percentMul(liquidationThreshold);
        
        // Required collateral to maintain HF = 1
        // requiredAdjusted >= debt (for HF >= 1)
        // So: maxWithdrawAdjusted = currentAdjusted - debt
        
        if (currentAdjustedCollateral <= totalDebt) {
            return 0; // Already at or below threshold
        }
        
        uint256 excessAdjustedCollateral = currentAdjustedCollateral - totalDebt;
        
        // Convert excess adjusted collateral back to actual asset amount
        // excessAdjusted = excessAmount * assetPrice * assetLiqThreshold / 10000
        // excessAmount = excessAdjusted * 10000 / (assetPrice * assetLiqThreshold)
        
        if (assetLiqThreshold == 0 || assetPrice == 0) {
            return 0;
        }
        
        uint256 assetUnit = 10 ** assetDecimals;
        uint256 maxWithdrawInBaseCurrency = (excessAdjustedCollateral * 10000) / assetLiqThreshold;
        
        return (maxWithdrawInBaseCurrency * assetUnit) / assetPrice;
    }
    
    /**
     * @notice Calculate the maximum amount that can be borrowed while keeping HF >= 1
     * @param totalCollateral Current total collateral in base currency
     * @param totalDebt Current total debt in base currency
     * @param avgLtv Weighted avg LTV
     * @param assetPrice Price of the asset to borrow
     * @param assetDecimals Decimals of the asset
     * @return Maximum borrowable amount in asset units
     */
    function calculateMaxBorrowable(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 avgLtv,
        uint256 assetPrice,
        uint256 assetDecimals
    ) internal pure returns (uint256) {
        uint256 maxBorrowInBaseCurrency = totalCollateral.percentMul(avgLtv);
        
        if (maxBorrowInBaseCurrency <= totalDebt) {
            return 0;
        }
        
        uint256 availableBorrowInBaseCurrency = maxBorrowInBaseCurrency - totalDebt;
        uint256 assetUnit = 10 ** assetDecimals;
        
        return (availableBorrowInBaseCurrency * assetUnit) / assetPrice;
    }
    
    /**
     * @notice Calculate maximum liquidatable debt for a given health factor
     * @param totalDebt Total debt in base currency
     * @param healthFactor Current health factor
     * @param closeFactor Maximum percentage that can be liquidated (e.g., 5000 = 50%)
     * @return Maximum debt that can be liquidated in base currency
     */
    function calculateMaxLiquidatableDebt(
        uint256 totalDebt,
        uint256 healthFactor,
        uint256 closeFactor
    ) internal pure returns (uint256) {
        if (!isLiquidatable(healthFactor)) {
            return 0;
        }
        
        // Apply close factor (typically 50%)
        return totalDebt.percentMul(closeFactor);
    }
    
    /**
     * @notice Calculate collateral to seize during liquidation
     * @param debtToCover Debt amount being covered
     * @param debtAssetPrice Price of debt asset
     * @param collateralAssetPrice Price of collateral asset
     * @param liquidationBonus Liquidation bonus (e.g., 10500 = 5% bonus)
     * @param collateralDecimals Decimals of collateral asset
     * @return Amount of collateral to seize
     */
    function calculateCollateralToSeize(
        uint256 debtToCover,
        uint256 debtAssetPrice,
        uint256 collateralAssetPrice,
        uint256 liquidationBonus,
        uint256 collateralDecimals
    ) internal pure returns (uint256) {
        // Convert debt to base currency value
        uint256 debtInBaseCurrency = debtToCover * debtAssetPrice;
        
        // Apply liquidation bonus (bonus is 10000 + bonus%, e.g., 10500 for 5% bonus)
        uint256 collateralInBaseCurrency = debtInBaseCurrency.percentMul(liquidationBonus);
        
        // Convert to collateral asset units
        uint256 collateralUnit = 10 ** collateralDecimals;
        
        return (collateralInBaseCurrency * collateralUnit) / collateralAssetPrice;
    }
}
