// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from '../types/DataTypes.sol';
import {Errors} from '../helpers/Errors.sol';
import {}

/**
 * @title BorrowLogic
 * @notice Handles ALL borrow-related operations
 * - Validation
 * - Execution
 * - Debt token minting
 * 
 * TODO: Implement borrow validation and execution
 */
library BorrowLogic {
    
    /**
     * Validate borrow operation
     * 
     * TODO: Implement validation checks:
     * 1. require(amount > 0, Errors.INVALID_AMOUNT)
     * 2. require(reserve.isActive, Errors.RESERVE_INACTIVE)
     * 3. require(!reserve.isPaused, Errors.RESERVE_PAUSED)
     * 4. require(reserve.borrowingEnabled, Errors.BORROWING_NOT_ENABLED)
     * 5. Check interest rate mode:
     *    - require(interestRateMode == 1 || interestRateMode == 2, Errors.INVALID_INTEREST_RATE_MODE_SELECTED)
     *    - If mode == 1 (stable): require(reserve.stableBorrowRateEnabled, Errors.STABLE_BORROWING_NOT_ENABLED)
     * 6. Check available liquidity:
     *    - require(amount <= reserve.availableLiquidity, "Insufficient liquidity")
     * 7. Check borrow cap:
     *    - Get borrowCap from reserve configuration
     *    - if (borrowCap > 0):
     *        uint256 totalDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).totalSupply()
     *                          + IStableDebtToken(reserve.stableDebtTokenAddress).totalSupply()
     *        require(totalDebt + amount <= borrowCap, Errors.BORROW_CAP_EXCEEDED)
     * 8. Check user has enough collateral:
     *    - Calculate user's available borrows in base currency
     *    - Convert amount to base currency using oracle
     *    - require(amountInBase <= availableBorrows, Errors.COLLATERAL_CANNOT_COVER_NEW_BORROW)
     * 9. Check credit delegation (if onBehalfOf != msg.sender):
     *    - Check borrowAllowance[onBehalfOf][msg.sender][asset] >= amount
     *    - Deduct from allowance
     * 
     * @param reserve The reserve state
     * @param params Borrow parameters
     */
    function validateBorrow(
        DataTypes.ReserveData storage reserve,
        DataTypes.ExecuteBorrowParams memory params
    ) internal view {
        // TODO: Implement validation
        require(params.amount>0,'11');
        require(reserve.isActive,'12');
        require(!reserve.isPaused,'14');
        require(reserve.borrowingEnabled,'15');
        require(params.interestRateMode==1 || params.interestRateMode==2,'18');
        if(params.interestRateMode==1){
            require(reserve.stableBorrowRateEnabled,'16');

        }
        require(reserve.availableLiquidity>params.amount,'Insufficient Liquidity');
        if(params.borrowCap>0){ //*************************** please fix reserve.borrowCap in future */
            uint256 val=IVariableDebtToken(reserve.variableDebtTokenAddress).totalSupply()+IStableDebtToken(reserve.stableDebtToken).totalSupply();
            require(val+params.amount<borrowCap,'32');
        }
        require(params.borrowCap>0,'35');
        require(params.amountInBase<= availableBorrows,'21');
        // require()
        // will 
        


    }
    
    /**
     * Execute borrow operation
     * 
     * TODO: Implement borrow execution:
     * 1. Update reserve state:
     *    - Call updateState(reserve) to accrue interest
     * 
     * 2. Mint debt tokens:
     *    - If interestRateMode == 1 (stable):
     *        uint256 currentStableRate = reserve.currentStableBorrowRate
     *        IStableDebtToken(reserve.stableDebtTokenAddress).mint(onBehalfOf, amount, currentStableRate)
     *    - If interestRateMode == 2 (variable):
     *        IVariableDebtToken(reserve.variableDebtTokenAddress).mint(onBehalfOf, amount)
     * 
     * 3. Update reserve liquidity:
     *    - reserve.availableLiquidity -= amount
     * 
     * 4. Transfer tokens to borrower:
     *    - IAToken(reserve.aTokenAddress).transferUnderlyingTo(user, amount)
     *    - Or: IERC20(asset).safeTransfer(user, amount)
     * 
     * 5. Update user configuration:
     *    - Set user's borrowing bitmap for this reserve
     *    - userConfig.setBorrowing(reserve.id, true)
     * 
     * 6. Check final health factor:
     *    - Calculate health factor after borrow
     *    - require(healthFactor >= 1e18, Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD)
     * 
     * 7. Update interest rates:
     *    - Calculate new rates based on utilization
     *    - Update reserve.currentLiquidityRate, currentVariableBorrowRate, currentStableBorrowRate
     * 
     * 8. Emit event:
     *    - emit Borrow(user, asset, amount, interestRateMode, borrowRate, referralCode)
     * 
     * @param reserve The reserve state
     * @param params Borrow parameters
     * @return bool Success
     */
    function executeBorrow(
        DataTypes.ReserveData storage reserve,
        DataTypes.ExecuteBorrowParams memory params
    ) internal returns (bool) {
        // TODO: Implement execution
        return true;
    }
}
