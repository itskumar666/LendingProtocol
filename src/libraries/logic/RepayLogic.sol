// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from '../types/DataTypes.sol';
import {Errors} from '../helpers/Errors.sol';
import {IAToken} from '../../interfaces/IAToken.sol';
import {WadRayMath} from '../math/WadRayMath.sol';
import {IStableDebtToken} from '../../interfaces/IStableDebtToken.sol';
import {IVariableDebtToken} from '../../interfaces/IVariableDebtToken.sol';
import {IInterestRateStrategy} from '../../interfaces/IInterestRateStrategy.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title RepayLogic
 * @notice Handles ALL repay-related operations
 * - Validation
 * - Execution
 * - Debt token burning
 * 
 * TODO: Implement repay validation and execution
 */
library RepayLogic {
    using SafeERC20 for IERC20;
    
    event Repay(
        address indexed reserve,
        address indexed user,
        address indexed repayer,
        uint256 amount,
        uint8 interestRateMode
    );
    
    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );
    
    /**
     * Validate repay operation
     * 
     * TODO: Implement validation checks:
     * 1. require(amount > 0, Errors.INVALID_AMOUNT)
     * 2. require(reserve.isActive, Errors.RESERVE_INACTIVE)
     * 3. require(!reserve.isPaused, Errors.RESERVE_PAUSED)
     * 4. Check interest rate mode valid:
     *    - require(interestRateMode == 1 || interestRateMode == 2, Errors.INVALID_INTEREST_RATE_MODE_SELECTED)
     * 5. Check user has debt in selected mode:
     *    - If mode == 1: 
     *        uint256 stableDebt = IStableDebtToken(reserve.stableDebtTokenAddress).balanceOf(onBehalfOf)
     *        require(stableDebt > 0, Errors.NO_OUTSTANDING_STABLE_DEBT)
     *    - If mode == 2:
     *        uint256 variableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).balanceOf(onBehalfOf)
     *        require(variableDebt > 0, Errors.NO_OUTSTANDING_VARIABLE_DEBT)
     * 
     * @param reserve The reserve state
     * @param params Repay parameters
     */
    function validateRepay(
        DataTypes.ReserveData storage reserve,
        DataTypes.ExecuteRepayParams memory params
    ) internal view {
        require(params.amount > 0, Errors.INVALID_AMOUNT);
        require(reserve.isActive, Errors.RESERVE_INACTIVE);
        require(!reserve.isPaused, Errors.RESERVE_PAUSED);
        require(
            params.interestRateMode == 1 || params.interestRateMode == 2,
            Errors.INVALID_INTEREST_RATE_MODE_SELECTED
        );
        
        if (params.interestRateMode == 1) {
            uint256 stableDebt = IStableDebtToken(reserve.stableDebtTokenAddress).balanceOf(params.onBehalfOf);
            require(stableDebt > 0, Errors.NO_OUTSTANDING_STABLE_DEBT);
        } else {
            uint256 variableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).balanceOf(params.onBehalfOf);
            require(variableDebt > 0, Errors.NO_OUTSTANDING_VARIABLE_DEBT);
        }
    }
    
    /**
     * Execute repay operation
     * 
     * TODO: Implement repay execution:
     * 1. Update reserve state:
     *    - Call updateState(reserve) to accrue interest
     * 
     * 2. Get current debt:
     *    - If interestRateMode == 1:
     *        currentDebt = IStableDebtToken(reserve.stableDebtTokenAddress).balanceOf(onBehalfOf)
     *    - If interestRateMode == 2:
     *        currentDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).balanceOf(onBehalfOf)
     * 
     * 3. Calculate actual repay amount:
     *    - uint256 paybackAmount = (amount == type(uint256).max) ? currentDebt : amount
     *    - if (paybackAmount > currentDebt): paybackAmount = currentDebt
     * 
     * 4. Transfer tokens from payer:
     *    - IERC20(asset).safeTransferFrom(msg.sender, reserve.aTokenAddress, paybackAmount)
     *    - Anyone can repay anyone's debt!
     * 
     * 5. Burn debt tokens:
     *    - If interestRateMode == 1:
     *        IStableDebtToken(reserve.stableDebtTokenAddress).burn(onBehalfOf, paybackAmount)
     *    - If interestRateMode == 2:
     *        IVariableDebtToken(reserve.variableDebtTokenAddress).burn(onBehalfOf, paybackAmount)
     * 
     * 6. Update reserve liquidity:
     *    - reserve.availableLiquidity += paybackAmount
     * 
     * 7. Update user configuration (if fully repaid):
     *    - Check if user has any remaining debt in this asset
     *    - If both stable and variable debt == 0:
     *        userConfig.setBorrowing(reserve.id, false)
     * 
     * 8. Update interest rates:
     *    - Calculate new rates based on new utilization
     * 
     * 9. Emit event:
     *    - emit Repay(onBehalfOf, asset, paybackAmount, msg.sender)
     * 
     * @param reserve The reserve state
     * @param params Repay parameters
     * @return uint256 Actual amount repaid
     */
    function executeRepay(
        DataTypes.ReserveData storage reserve,
        DataTypes.ExecuteRepayParams memory params
    ) internal returns (uint256) {
        // 1. Update state
        updateState(reserve);
        
        // 2. Get current debt
        uint256 currentDebt;
        if (params.interestRateMode == 1) {
            currentDebt = IStableDebtToken(reserve.stableDebtTokenAddress).balanceOf(params.onBehalfOf);
        } else {
            currentDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).balanceOf(params.onBehalfOf);
        }
        
        // 3. Calculate actual payback amount
        uint256 paybackAmount = (params.amount == type(uint256).max) ? currentDebt : params.amount;
        if (paybackAmount > currentDebt) {
            paybackAmount = currentDebt;
        }
        
        // 4. Transfer tokens from payer to aToken
        IERC20(params.asset).safeTransferFrom(msg.sender, reserve.aTokenAddress, paybackAmount);
        
        // 5. Burn debt tokens
        if (params.interestRateMode == 1) {
            IStableDebtToken(reserve.stableDebtTokenAddress).burn(params.onBehalfOf, paybackAmount);
        } else {
            IVariableDebtToken(reserve.variableDebtTokenAddress).burn(
                params.onBehalfOf,
                paybackAmount,
                reserve.variableBorrowIndex
            );
        }
        
        // 6. Update reserve liquidity
        reserve.availableLiquidity += paybackAmount;
        
        // 7. TODO: Update user configuration if fully repaid
        
        // 8. Update interest rates
        updateInterestRate(reserve, params.asset, paybackAmount, 0);
        
        // 9. Emit event
        emit Repay(params.asset, params.onBehalfOf, msg.sender, paybackAmount, uint8(params.interestRateMode));
        
        return paybackAmount;
    }
    
    function updateState(DataTypes.ReserveData storage reserve) internal {
        uint256 currentTimestamp = block.timestamp;
        uint40 lastUpdateTimestamp = reserve.lastUpdateTimestamp;
        
        if (currentTimestamp == lastUpdateTimestamp) {
            return;
        }
        
        uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;
        uint256 liquidityRate = reserve.currentLiquidityRate;
        uint256 variableBorrowRate = reserve.currentVariableBorrowRate;
        
        if (liquidityRate > 0) {
            uint256 linearInterest = WadRayMath.calculateLinearInterest(liquidityRate, timeDelta);
            reserve.liquidityIndex = uint128((uint256(reserve.liquidityIndex) * linearInterest) / 1e27);
        }
        
        if (variableBorrowRate > 0) {
            uint256 compoundedInterest = WadRayMath.calculateCompoundedInterest(variableBorrowRate, timeDelta);
            reserve.variableBorrowIndex = uint128((uint256(reserve.variableBorrowIndex) * compoundedInterest) / 1e27);
        }
        
        reserve.lastUpdateTimestamp = uint40(currentTimestamp);
    }
    
    function updateInterestRate(
        DataTypes.ReserveData storage reserve,
        address asset,
        uint256 addedLiquidity,
        uint256 removedLiquidity
    ) internal {
        uint256 totalStableDebt = IStableDebtToken(reserve.stableDebtTokenAddress).totalSupply();
        uint256 totalVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).totalSupply();
        uint256 totalDebt = totalStableDebt + totalVariableDebt;
        
        uint256 availableLiquidity = reserve.availableLiquidity + addedLiquidity - removedLiquidity;
        
        (uint256 newLiquidityRate, uint256 newVariableRate, uint256 newStableRate) = 
            IInterestRateStrategy(reserve.interestRateStrategyAddress)
                .calculateInterestRate(availableLiquidity, totalDebt);
        
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
