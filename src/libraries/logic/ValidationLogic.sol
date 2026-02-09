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

/**
 * @title ValidationLogic
 * @notice Validates all user inputs and state transitions
 * @dev Centralized validation to ensure consistent checks across all operations
 */
library ValidationLogic {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    
    // ============ Constants ============
    
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;
    uint256 public constant MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 0.95e18;
    uint256 public constant MAX_LIQUIDATION_CLOSE_FACTOR = 5000; // 50%
    uint256 public constant REBALANCE_UP_LIQUIDITY_RATE_THRESHOLD = 0.9e27; // 90%
    
    // ============ Structs ============
    
    struct ValidateBorrowLocalVars {
        uint256 currentLtv;
        uint256 collateralNeededInBaseCurrency;
        uint256 userCollateralInBaseCurrency;
        uint256 userDebtInBaseCurrency;
        uint256 availableLiquidity;
        uint256 healthFactor;
        uint256 totalDebt;
        uint256 totalSupplyVariableDebt;
        uint256 reserveDecimals;
        uint256 borrowCap;
        uint256 amountInBaseCurrency;
        bool isActive;
        bool isFrozen;
        bool isPaused;
        bool borrowingEnabled;
        bool stableRateBorrowingEnabled;
    }
    
    struct ValidateLiquidationCallLocalVars {
        bool collateralReserveActive;
        bool collateralReservePaused;
        bool debtReserveActive;
        bool debtReservePaused;
        bool isCollateralEnabled;
    }
    
    // ============ Deposit Validation ============
    
    /**
     * @notice Validate deposit operation
     * @param reserve The reserve data
     * @param amount The amount to deposit
     * @param onBehalfOf The address that will receive aTokens
     */
    function validateDeposit(
        DataTypes.ReserveData storage reserve,
        uint256 amount,
        address onBehalfOf
    ) internal view {
        require(amount != 0, Errors.INVALID_AMOUNT);
        require(onBehalfOf != address(0), Errors.ZERO_ADDRESS_NOT_VALID);
        
        (bool isActive, bool isFrozen, , , bool isPaused) = reserve.configuration.getFlags();
        
        require(isActive, Errors.RESERVE_INACTIVE);
        require(!isPaused, Errors.RESERVE_PAUSED);
        require(!isFrozen, Errors.RESERVE_FROZEN);
        
        // Check supply cap
        uint256 supplyCap = reserve.configuration.getSupplyCap();
        if (supplyCap != 0) {
            uint256 decimals = reserve.configuration.getDecimals();
            uint256 supplyCapInUnits = supplyCap * (10 ** decimals);
            
            uint256 currentSupply = IAToken(reserve.aTokenAddress).totalSupply();
            require(currentSupply + amount <= supplyCapInUnits, Errors.SUPPLY_CAP_EXCEEDED);
        }
    }
    
    // ============ Withdraw Validation ============
    
    /**
     * @notice Validate withdraw operation
     * @param reserve The reserve data
     * @param amount The amount to withdraw
     * @param userBalance User's aToken balance
     */
    function validateWithdraw(
        DataTypes.ReserveData storage reserve,
        uint256 amount,
        uint256 userBalance
    ) internal view {
        require(amount != 0, Errors.INVALID_AMOUNT);
        require(amount <= userBalance, Errors.NOT_ENOUGH_AVAILABLE_USER_BALANCE);
        
        (bool isActive, , , , bool isPaused) = reserve.configuration.getFlags();
        
        require(isActive, Errors.RESERVE_INACTIVE);
        require(!isPaused, Errors.RESERVE_PAUSED);
        
        // Check available liquidity
        require(amount <= reserve.availableLiquidity, Errors.NOT_ENOUGH_LIQUIDITY);
    }
    
    /**
     * @notice Validate withdraw with health factor check
     * @param healthFactorAfter Health factor after withdrawal
     */
    function validateWithdrawHealthFactor(
        uint256 healthFactorAfter
    ) internal pure {
        require(
            healthFactorAfter >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
        );
    }
    
    // ============ Borrow Validation ============
    
    /**
     * @notice Validate borrow operation
     * @param reserve The reserve data
     * @param params The borrow parameters
     * @param userCollateralInBaseCurrency User's total collateral
     * @param userDebtInBaseCurrency User's total debt
     * @param currentLtv User's current LTV
     * @param healthFactor User's health factor after borrow
     */
    function validateBorrow(
        DataTypes.ReserveData storage reserve,
        DataTypes.ExecuteBorrowParams memory params,
        uint256 userCollateralInBaseCurrency,
        uint256 userDebtInBaseCurrency,
        uint256 currentLtv,
        uint256 healthFactor
    ) internal view {
        ValidateBorrowLocalVars memory vars;
        
        require(params.amount != 0, Errors.INVALID_AMOUNT);
        
        (
            vars.isActive,
            vars.isFrozen,
            vars.borrowingEnabled,
            vars.stableRateBorrowingEnabled,
            vars.isPaused
        ) = reserve.configuration.getFlags();
        
        require(vars.isActive, Errors.RESERVE_INACTIVE);
        require(!vars.isPaused, Errors.RESERVE_PAUSED);
        require(!vars.isFrozen, Errors.RESERVE_FROZEN);
        require(vars.borrowingEnabled, Errors.BORROWING_NOT_ENABLED);
        
        // Validate interest rate mode
        require(
            params.interestRateMode == DataTypes.INTEREST_RATE_MODE_STABLE ||
            params.interestRateMode == DataTypes.INTEREST_RATE_MODE_VARIABLE,
            Errors.INVALID_INTEREST_RATE_MODE_SELECTED
        );
        
        // Check stable rate enabled for stable borrows
        if (params.interestRateMode == DataTypes.INTEREST_RATE_MODE_STABLE) {
            require(vars.stableRateBorrowingEnabled, Errors.STABLE_BORROWING_NOT_ENABLED);
        }
        
        // Check borrow cap
        vars.borrowCap = reserve.configuration.getBorrowCap();
        if (vars.borrowCap != 0) {
            vars.reserveDecimals = reserve.configuration.getDecimals();
            uint256 borrowCapInUnits = vars.borrowCap * (10 ** vars.reserveDecimals);
            
            vars.totalSupplyVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress)
                .totalSupply();
            
            // Also get stable debt total
            uint256 totalStableDebt = IStableDebtToken(reserve.stableDebtTokenAddress).totalSupply();
            vars.totalDebt = vars.totalSupplyVariableDebt + totalStableDebt;
            
            require(vars.totalDebt + params.amount <= borrowCapInUnits, Errors.BORROW_CAP_EXCEEDED);
        }
        
        // Check available liquidity
        require(params.amount <= reserve.availableLiquidity, Errors.NOT_ENOUGH_LIQUIDITY);
        
        // Check user has collateral
        require(userCollateralInBaseCurrency > 0, Errors.COLLATERAL_BALANCE_IS_ZERO);
        require(currentLtv > 0, Errors.LTV_VALIDATION_FAILED);
        
        // Check health factor after borrow
        require(
            healthFactor >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
        );
        
        // Validate credit delegation if borrowing on behalf
        if (params.user != params.onBehalfOf) {
            require(
                params.delegatedAllowance >= params.amount,
                Errors.BORROW_ALLOWANCE_NOT_ENOUGH
            );
        }
    }
    
    // ============ Repay Validation ============
    
    /**
     * @notice Validate repay operation
     * @param reserve The reserve data
     * @param amountSent Amount being repaid
     * @param interestRateMode The interest rate mode
     * @param onBehalfOf User whose debt is being repaid
     * @param stableDebt User's stable debt
     * @param variableDebt User's variable debt
     */
    function validateRepay(
        DataTypes.ReserveData storage reserve,
        uint256 amountSent,
        uint256 interestRateMode,
        address onBehalfOf,
        uint256 stableDebt,
        uint256 variableDebt
    ) internal view {
        require(amountSent != 0, Errors.INVALID_AMOUNT);
        require(onBehalfOf != address(0), Errors.ZERO_ADDRESS_NOT_VALID);
        
        (bool isActive, , , , bool isPaused) = reserve.configuration.getFlags();
        require(isActive, Errors.RESERVE_INACTIVE);
        require(!isPaused, Errors.RESERVE_PAUSED);
        
        require(
            interestRateMode == DataTypes.INTEREST_RATE_MODE_STABLE ||
            interestRateMode == DataTypes.INTEREST_RATE_MODE_VARIABLE,
            Errors.INVALID_INTEREST_RATE_MODE_SELECTED
        );
        
        // Check user has debt in the selected mode
        if (interestRateMode == DataTypes.INTEREST_RATE_MODE_STABLE) {
            require(stableDebt > 0, Errors.NO_DEBT_OF_SELECTED_TYPE);
        } else {
            require(variableDebt > 0, Errors.NO_DEBT_OF_SELECTED_TYPE);
        }
    }
    
    // ============ Liquidation Validation ============
    
    /**
     * @notice Validate liquidation call
     * @param collateralReserve The collateral reserve
     * @param debtReserve The debt reserve
     * @param userHealthFactor User's current health factor
     * @param userStableDebt User's stable debt in debt asset
     * @param userVariableDebt User's variable debt in debt asset
     */
    function validateLiquidationCall(
        DataTypes.ReserveData storage collateralReserve,
        DataTypes.ReserveData storage debtReserve,
        uint256 userHealthFactor,
        uint256 userStableDebt,
        uint256 userVariableDebt
    ) internal view {
        ValidateLiquidationCallLocalVars memory vars;
        
        (vars.collateralReserveActive, , , , vars.collateralReservePaused) = 
            collateralReserve.configuration.getFlags();
        (vars.debtReserveActive, , , , vars.debtReservePaused) = 
            debtReserve.configuration.getFlags();
        
        require(vars.collateralReserveActive, Errors.RESERVE_INACTIVE);
        require(vars.debtReserveActive, Errors.RESERVE_INACTIVE);
        require(!vars.collateralReservePaused, Errors.RESERVE_PAUSED);
        require(!vars.debtReservePaused, Errors.RESERVE_PAUSED);
        
        // User must be liquidatable (health factor < 1)
        require(
            userHealthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.HEALTH_FACTOR_NOT_BELOW_THRESHOLD
        );
        
        // User must have debt in this asset
        require(
            userStableDebt > 0 || userVariableDebt > 0,
            Errors.SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER
        );
    }
    
    /**
     * @notice Calculate max liquidatable debt
     * @param userTotalDebt User's total debt in debt asset
     * @param healthFactor User's health factor
     * @return Max debt that can be liquidated
     */
    function calculateMaxLiquidatableDebt(
        uint256 userTotalDebt,
        uint256 healthFactor
    ) internal pure returns (uint256) {
        // If health factor is very low, allow 100% liquidation
        if (healthFactor < MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {
            return userTotalDebt;
        }
        
        // Otherwise, max 50% (close factor)
        return userTotalDebt.percentMul(MAX_LIQUIDATION_CLOSE_FACTOR);
    }
    
    // ============ Flash Loan Validation ============
    
    /**
     * @notice Validate flash loan
     * @param reservesData Mapping of all reserves
     * @param assets Array of asset addresses
     * @param amounts Array of amounts
     */
    function validateFlashLoan(
        mapping(address => DataTypes.ReserveData) storage reservesData,
        address[] memory assets,
        uint256[] memory amounts
    ) internal view {
        require(assets.length == amounts.length, Errors.INCONSISTENT_FLASHLOAN_PARAMS);
        require(assets.length > 0, Errors.INCONSISTENT_FLASHLOAN_PARAMS);
        
        for (uint256 i = 0; i < assets.length; i++) {
            require(amounts[i] != 0, Errors.INVALID_AMOUNT);
            
            DataTypes.ReserveData storage reserve = reservesData[assets[i]];
            
            (bool isActive, , , , bool isPaused) = reserve.configuration.getFlags();
            require(isActive, Errors.RESERVE_INACTIVE);
            require(!isPaused, Errors.RESERVE_PAUSED);
            require(reserve.configuration.getFlashLoanEnabled(), Errors.FLASHLOAN_DISABLED);
            
            require(amounts[i] <= reserve.availableLiquidity, Errors.NOT_ENOUGH_LIQUIDITY);
        }
    }
    
    /**
     * @notice Validate flash loan simple (single asset)
     * @param reserve The reserve data
     * @param amount The amount to borrow
     */
    function validateFlashLoanSimple(
        DataTypes.ReserveData storage reserve,
        uint256 amount
    ) internal view {
        require(amount != 0, Errors.INVALID_AMOUNT);
        
        (bool isActive, , , , bool isPaused) = reserve.configuration.getFlags();
        require(isActive, Errors.RESERVE_INACTIVE);
        require(!isPaused, Errors.RESERVE_PAUSED);
        require(reserve.configuration.getFlashLoanEnabled(), Errors.FLASHLOAN_DISABLED);
        require(amount <= reserve.availableLiquidity, Errors.NOT_ENOUGH_LIQUIDITY);
    }
    
    // ============ Health Factor Validation ============
    
    /**
     * @notice Validate health factor improvement after liquidation
     * @param healthFactorBefore Health factor before liquidation
     * @param healthFactorAfter Health factor after liquidation
     */
    function validateHealthFactorImprovement(
        uint256 healthFactorBefore,
        uint256 healthFactorAfter
    ) internal pure {
        require(
            healthFactorAfter > healthFactorBefore,
            Errors.HEALTH_FACTOR_NOT_IMPROVED
        );
    }
    
    /**
     * @notice Validate health factor is above threshold
     * @param healthFactor The health factor to check
     */
    function validateHealthFactor(uint256 healthFactor) internal pure {
        require(
            healthFactor >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
        );
    }
    
    // ============ Collateral Validation ============
    
    /**
     * @notice Validate set user as using reserve as collateral
     * @param reserve The reserve data
     * @param userBalance User's aToken balance
     */
    function validateSetUseReserveAsCollateral(
        DataTypes.ReserveData storage reserve,
        uint256 userBalance
    ) internal view {
        require(userBalance > 0, Errors.UNDERLYING_BALANCE_ZERO);
        
        (bool isActive, , , , bool isPaused) = reserve.configuration.getFlags();
        require(isActive, Errors.RESERVE_INACTIVE);
        require(!isPaused, Errors.RESERVE_PAUSED);
        
        // Check LTV > 0 (asset can be used as collateral)
        require(reserve.configuration.getLtv() > 0, Errors.LTV_VALIDATION_FAILED);
    }
}
