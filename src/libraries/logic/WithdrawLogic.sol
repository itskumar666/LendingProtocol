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
 * @title WithdrawLogic
 * @notice Handles ALL withdraw-related operations
 * - Validation
 * - Execution
 * - Health factor checks
 * 
 * TODO: Implement withdraw validation and execution
 */
library WithdrawLogic {
    using SafeERC20 for IERC20;
    
    event Withdraw(
        address indexed reserve,
        address indexed user,
        address indexed to,
        uint256 amount
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
     * Validate withdraw operation
     * 
     * TODO: Implement validation checks:
     * 1. require(amount > 0, Errors.INVALID_AMOUNT)
     * 2. require(reserve.isActive, Errors.RESERVE_INACTIVE)
     * 3. require(!reserve.isPaused, Errors.RESERVE_PAUSED)
     * 4. Check user has enough balance:
     *    - uint256 userBalance = IAToken(reserve.aTokenAddress).balanceOf(user)
     *    - If amount == type(uint256).max: amount = userBalance (withdraw all)
     *    - require(amount <= userBalance, Errors.NOT_ENOUGH_AVAILABLE_USER_BALANCE)
     * 5. Check available liquidity:
     *    - require(amount <= reserve.availableLiquidity, "Insufficient liquidity")
     * 
     * @param reserve The reserve state
     * @param amount Amount to withdraw
     * @param userBalance User's aToken balance
     */
    function validateWithdraw(
        DataTypes.ReserveData storage reserve,
        uint256 amount,
        uint256 userBalance
    ) internal view {
        require(amount > 0, Errors.INVALID_AMOUNT);
        require(reserve.isActive, Errors.RESERVE_INACTIVE);
        require(!reserve.isPaused, Errors.RESERVE_PAUSED);
        
        // Handle withdraw all case
        uint256 amountToWithdraw = (amount == type(uint256).max) ? userBalance : amount;
        
        require(amountToWithdraw <= userBalance, Errors.NOT_ENOUGH_AVAILABLE_USER_BALANCE);
        require(amountToWithdraw <= reserve.availableLiquidity, '47'); // Insufficient liquidity
    }
    
    /**
     * Execute withdraw operation
     * 
     * TODO: Implement withdraw execution:
     * 1. Update reserve state:
     *    - Call updateState(reserve) to accrue interest
     * 
     * 2. Get actual withdraw amount:
     *    - uint256 userBalance = IAToken(reserve.aTokenAddress).balanceOf(user)
     *    - uint256 amountToWithdraw = (amount == type(uint256).max) ? userBalance : amount
     * 
     * 3. Burn aTokens from user:
     *    - IAToken(reserve.aTokenAddress).burn(user, amountToWithdraw)
     *    - This will:
     *      a) Convert amount to scaledAmount
     *      b) Update scaledBalances
     *      c) Emit Transfer event
     * 
     * 4. Transfer underlying asset to user:
     *    - IAToken(reserve.aTokenAddress).transferUnderlyingTo(to, amountToWithdraw)
     *    - Or: IERC20(asset).safeTransfer(to, amountToWithdraw)
     * 
     * 5. Update reserve liquidity:
     *    - reserve.availableLiquidity -= amountToWithdraw
     * 
     * 6. Check health factor (if user has debt):
     *    - Calculate new health factor
     *    - require(healthFactor >= 1e18, Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD)
     *    - User can't withdraw if it makes them liquidatable!
     * 
     * 7. Update user configuration:
     *    - If user's aToken balance is now 0:
     *      userConfig.setUsingAsCollateral(reserve.id, false)
     *      emit ReserveUsedAsCollateralDisabled(asset, user)
     * 
     * 8. Emit event:
     *    - emit Withdraw(user, asset, amountToWithdraw, to)
     * 
     * @param reserve The reserve state
     * @param params Withdraw parameters
     * @return uint256 Amount actually withdrawn
     */
    function executeWithdraw(
        DataTypes.ReserveData storage reserve,
        DataTypes.ExecuteWithdrawParams memory params
    ) internal returns (uint256) {
        // 1. Update state
        updateState(reserve);
        
        // 2. Get actual amount to withdraw
        uint256 userBalance = IAToken(reserve.aTokenAddress).balanceOf(params.user);
        uint256 amountToWithdraw = (params.amount == type(uint256).max) ? userBalance : params.amount;
        
        // 3. Burn aTokens
        IAToken(reserve.aTokenAddress).burn(
            params.user,
            params.to,
            amountToWithdraw,
            reserve.liquidityIndex
        );
        // 4. Transfer underlying to user 
        IAToken(reserve.aTokenAddress).transferUnderlyingTo(params.user, params.amount);
        
     
        // 5. Update reserve liquidity
        reserve.availableLiquidity -= amountToWithdraw;
        
        // 6. TODO: Check health factor if user has debt (need ValidationLogic)
        // 7. TODO: Update user configuration if balance is 0
        
        // 8. Update interest rates
        updateInterestRate(reserve, params.asset, 0, amountToWithdraw);
        
        // 9. Emit event
        emit Withdraw(params.asset, params.user, params.to, amountToWithdraw);
        
        return amountToWithdraw;
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
