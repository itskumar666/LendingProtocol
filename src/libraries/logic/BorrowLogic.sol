// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from '../types/DataTypes.sol';
import {Errors} from '../helpers/Errors.sol';
import {IAToken} from '../../interfaces/IAToken.sol';
import {IVariableDebtToken} from '../../interfaces/IVariableDebtToken.sol';
import {IStableDebtToken} from '../../interfaces/IStableDebtToken.sol';
import {IInterestRateStrategy} from '../../interfaces/IInterestRateStrategy.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


/**
 * @title BorrowLogic
 * @notice Handles ALL borrow-related operations
 * - Validation
 * - Execution
 * - Debt token minting
 */
library BorrowLogic {
    using SafeERC20 for IERC20;
    
    // ==================== EVENTS ====================
    
    event Borrow(`
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint8 interestRateMode,
        uint256 borrowRate,
        uint16 indexed referralCode
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
        // 1. Amount validation
        require(params.amount > 0, Errors.INVALID_AMOUNT);
        
        // 2. Reserve status checks
        require(reserve.isActive, Errors.RESERVE_INACTIVE);
        require(!reserve.isPaused, Errors.RESERVE_PAUSED);
        require(reserve.borrowingEnabled, Errors.BORROWING_NOT_ENABLED);
        
        // 3. Interest rate mode validation
        require(
            params.interestRateMode == 1 || params.interestRateMode == 2,
            Errors.INVALID_INTEREST_RATE_MODE_SELECTED
        );
        if (params.interestRateMode == 1) {
            require(reserve.stableBorrowRateEnabled, Errors.STABLE_BORROWING_NOT_ENABLED);
        }
        
        // 4. Liquidity check
        require(reserve.availableLiquidity >= params.amount, 'Insufficient liquidity');
        
        // 5. Borrow cap check (if set)
        if (params.borrowCap > 0) {
            uint256 totalDebt = params.totalStableDebt + params.totalVariableDebt;
            require(totalDebt + params.amount <= params.borrowCap, Errors.BORROW_CAP_EXCEEDED);
        }
        
        // 6. Collateral check - ensure user can borrow this amount
        require(
            params.amountInBase <= params.availableBorrows,
            Errors.COLLATERAL_CANNOT_COVER_NEW_BORROW
        );
        
        // 7. Credit delegation check (if borrowing on behalf of someone else)
        if (params.onBehalfOf != params.user) {
            require(
                params.delegatedAllowance >= params.amount,
                Errors.BORROW_ALLOWANCE_NOT_ENOUGH
            );
        }
    }
    
    /**
     * @notice Executes a borrow operation
     * @dev This is where the actual state changes happen
     * @param reserve The reserve state
     * @param params Borrow parameters
     */
    function executeBorrow(
        DataTypes.ReserveData storage reserve,
        DataTypes.ExecuteBorrowParams memory params
    ) internal {
        // 1. Update indexes (accrue interest) before any state changes
        updateState(reserve);
        
        // 2. Mint debt tokens to the borrower
        uint256 currentBorrowRate;
        
        if (params.interestRateMode == 1) {
            // Stable rate borrowing
            currentBorrowRate = reserve.currentStableBorrowRate;
            
            IStableDebtToken(reserve.stableDebtTokenAddress).mint(
                params.user,
                params.onBehalfOf,
                params.amount,
                currentBorrowRate
            );
        } else {
            // Variable rate borrowing (mode == 2)
            currentBorrowRate = reserve.currentVariableBorrowRate;
            
            IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
                params.user,
                params.onBehalfOf,
                params.amount,
                currentBorrowRate
            );
        }
        
        // 3. Update reserve available liquidity (decrease)
        reserve.availableLiquidity -= params.amount;
        
        // 4. Transfer UNDERLYING asset (e.g., USDC, WETH) to the borrower
        // NOT aTokens! The aToken contract holds the underlying assets from depositors
        // This function transfers the actual underlying ERC20 tokens to the user
        IAToken(reserve.aTokenAddress).transferUnderlyingTo(params.user, params.amount);
        
        // 5. Update interest rates based on new utilization
        updateInterestRates(reserve, params.asset, 0, params.amount);
        
        // 6. Emit borrow event
        emit Borrow(
            params.asset,
            params.user,
            params.onBehalfOf,
            params.amount,
            uint8(params.interestRateMode),
            currentBorrowRate,
            params.referralCode
        );
    }
    
    /**
     * @notice Updates the reserve state by accruing interest
     * @dev Called before any operation that changes reserve state
     * @param reserve The reserve to update
     */
    function updateState(DataTypes.ReserveData storage reserve) internal {
        uint256 currentTimestamp = block.timestamp;
        uint40 lastUpdateTimestamp = reserve.lastUpdateTimestamp;
        
        // If no time has passed, no need to update
        if (currentTimestamp == lastUpdateTimestamp) {
            return;
        }
        
        // Calculate time delta
        uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;
        
        // Get current rates
        uint256 liquidityRate = reserve.currentLiquidityRate;
        uint256 variableBorrowRate = reserve.currentVariableBorrowRate;
        
        // Update liquidity index (for aToken balance growth)
        if (liquidityRate > 0) {
            uint256 linearInterest = calculateLinearInterest(liquidityRate, timeDelta);
            reserve.liquidityIndex = uint128(
                (uint256(reserve.liquidityIndex) * linearInterest) / 1e27
            );
        }
        
        // Update variable borrow index (for debt growth)
        if (variableBorrowRate > 0) {
            uint256 compoundedInterest = calculateCompoundedInterest(variableBorrowRate, timeDelta);
            reserve.variableBorrowIndex = uint128(
                (uint256(reserve.variableBorrowIndex) * compoundedInterest) / 1e27
            );
        }
        
        // Update timestamp
        reserve.lastUpdateTimestamp = uint40(currentTimestamp);
    }
    
    /**
     * @notice Updates interest rates after a borrow/repay operation
     * @param reserve The reserve to update
     * @param asset The asset address
     * @param liquidityAdded Amount of liquidity added (from repay)
     * @param liquidityTaken Amount of liquidity taken (from borrow)
     */
    function updateInterestRates(
        DataTypes.ReserveData storage reserve,
        address asset,
        uint256 liquidityAdded,
        uint256 liquidityTaken
    ) internal {
        // Get total debts
        uint256 totalStableDebt = IStableDebtToken(reserve.stableDebtTokenAddress).totalSupply();
        uint256 totalVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).totalSupply();
        
        // Get average stable rate
        (uint256 avgStableRate, ) = IStableDebtToken(reserve.stableDebtTokenAddress).getTotalSupplyAndAvgRate();
        
        // Call interest rate strategy
        IInterestRateStrategy.CalculateInterestRatesParams memory rateParams = 
            IInterestRateStrategy.CalculateInterestRatesParams({
                unbacked: 0,
                liquidityAdded: liquidityAdded,
                liquidityTaken: liquidityTaken,
                totalStableDebt: totalStableDebt,
                totalVariableDebt: totalVariableDebt,
                averageStableBorrowRate: avgStableRate,
                reserveFactor: 0, // Should come from reserve config
                reserve: asset,
                aToken: reserve.aTokenAddress
            });
        
        (
            uint256 newLiquidityRate,
            uint256 newStableBorrowRate,
            uint256 newVariableBorrowRate
        ) = IInterestRateStrategy(reserve.interestRateStrategyAddress).calculateInterestRates(rateParams);
        
        // Update reserve rates
        reserve.currentLiquidityRate = uint128(newLiquidityRate);
        reserve.currentStableBorrowRate = uint128(newStableBorrowRate);
        reserve.currentVariableBorrowRate = uint128(newVariableBorrowRate);
        
        // Emit event
        emit ReserveDataUpdated(
            asset,
            newLiquidityRate,
            newStableBorrowRate,
            newVariableBorrowRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex
        );
    }
    
    /**
     * @notice Calculates linear interest (for liquidity index)
     * @param rate The interest rate (in ray units, 1e27)
     * @param timeDelta Time elapsed since last update
     * @return The linear interest multiplier
     */
    function calculateLinearInterest(uint256 rate, uint256 timeDelta) internal pure returns (uint256) {
        // linearInterest = 1 + (rate * timeDelta / secondsPerYear)
        // In ray: 1e27 + (rate * timeDelta / 31536000)
        return 1e27 + ((rate * timeDelta) / 365 days);
    }
    
    /**
     * @notice Calculates compound interest (for variable borrow index)
     * @param rate The interest rate (in ray units, 1e27)
     * @param timeDelta Time elapsed since last update
     * @return The compound interest multiplier
     */
    function calculateCompoundedInterest(uint256 rate, uint256 timeDelta) internal pure returns (uint256) {
        // For simplicity, using linear for now
        // Production would use actual compound calculation
        return calculateLinearInterest(rate, timeDelta);
    }
}
