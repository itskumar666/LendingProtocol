// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from '../types/DataTypes.sol';
import {Errors} from '../helpers/Errors.sol';

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
        // TODO: Implement validation checks
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
        // TODO: Implement execution
        return 0;
    }
}
