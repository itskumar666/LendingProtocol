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
 * @title DepositLogic
 * @notice Handles ALL deposit-related operations
 * - Validation
 * - Execution
 * - State updates
 * 
 * TODO: Implement deposit validation and execution
 */
library DepositLogic {
    using SafeERC20 for IERC20;
    
    // Events
    event Deposit(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
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
     * Validate deposit operation
     * 
     * TODO: Implement validation checks:
     * 1. require(amount > 0, Errors.INVALID_AMOUNT)
     * 2. require(reserve.isActive, Errors.RESERVE_INACTIVE)
     * 3. require(!reserve.isPaused, Errors.RESERVE_PAUSED)
     * 4. require(!reserve.isFrozen, Errors.RESERVE_FROZEN)
     * 5. Check supply cap:
     *    - Get supplyCap from reserve configuration
     *    - if (supplyCap > 0):
     *        uint256 totalSupply = IAToken(reserve.aTokenAddress).totalSupply()
     *        require(totalSupply + amount <= supplyCap, Errors.SUPPLY_CAP_EXCEEDED)
     * 
     * @param reserve The reserve state
     * @param params.amount Amount to deposit
     */

    function validateDeposit(
        DataTypes.ReserveData storage reserve,
        DataTypes.ExecuteDepositParams memory params
    ) internal view {
        require(reserve.aTokenAddress != address(0), '57');
        require(params.amount>0,'11');
        require(reserve.isActive,'12');
        require(!reserve.isPaused,'14');
        require(!reserve.isFrozen,'13');
        if(params.supplyCap>0){
            uint256 totalSupply=IAToken(reserve.aTokenAddress).scaledTotalSupply();
            require(params.supplyCap>=totalSupply+params.amount,'33');
        }
        

        // TODO: Implement all validation checks listed above
    }
    
    /**
     * Execute deposit operation
     * 
     * TODO: Implement deposit execution:
     * 1. Update reserve state:
     *    - Call updateState(reserve) to accrue interest first
     *    - Update lastUpdateTimestamp
     * 
     * 2. Transfer underlying asset from user:
     *    - IERC20(asset).safeTransferFrom(msg.sender, aTokenAddress, amount)
     *    - Assets go directly to aToken contract
     * 
     * 3. Mint aTokens to user:
     *    - IAToken(reserve.aTokenAddress).mint(onBehalfOf, amount)
     *    - This will:
     *      a) Convert amount to scaledAmount
     *      b) Update scaledBalances
     *      c) Emit Transfer event
     * 
     * 4. Update reserve liquidity tracking:
     *    - reserve.availableLiquidity += amount
     * 
     * 5. Update user configuration:
     *    - Set user's collateral bitmap for this reserve
     *    - userConfig.setUsingAsCollateral(reserve.id, true)
     * 
     * 6. Emit events:
     *    - emit Deposit(msg.sender, asset, amount, onBehalfOf)
     *    - emit ReserveUsedAsCollateralEnabled(asset, onBehalfOf) if first deposit
     * 
     * @param reserve The reserve state
     * @param params Deposit parameters (asset, amount, onBehalfOf, referralCode)
     * @return bool Success
     */
    function executeDeposit(
        DataTypes.ReserveData storage reserve,
        DataTypes.ExecuteDepositParams memory params
    ) internal returns (bool) {
        // 1. Update reserve state (accrue interest)
        updateState(reserve);
        
        // 2. Transfer underlying asset from user to aToken contract
        IERC20(params.asset).safeTransferFrom(
            msg.sender,
            reserve.aTokenAddress,
            params.amount
        );
        
        // 3. Mint aTokens to user
        IAToken(reserve.aTokenAddress).mint(
            msg.sender,
            params.onBehalfOf,
            params.amount,
            reserve.liquidityIndex
        );
        
        // 4. Update reserve liquidity tracking
        reserve.availableLiquidity += params.amount;
        
        // 5. Update interest rates based on new liquidity
        updateInterestRate(reserve, params.asset, params.amount, 0);
        
        // 6. TODO: Update user configuration bitmap (will add in helper library phase)
        // UserConfiguration.setUsingAsCollateral(userConfig, reserve.id, true);
        
        // 7. Emit deposit event
        emit Deposit(
            params.asset,
            msg.sender,
            params.onBehalfOf,
            params.amount,
            params.referralCode
        );
        
        return true;
    }
    function updateState(DataTypes.ReserveData storage reserve) internal {
      uint256 currentTimestamp=block.timestamp;
      uint256 lastTimestamp=reserve.lastUpdateTimestamp;
      if(lastTimestamp==currentTimestamp){
        return;
      }
      uint256 timeDelta=currentTimestamp-lastTimestamp;
      uint256 liquidityRate=reserve.currentLiquidityRate;
      uint256 variableBorrowRate=reserve.currentVariableBorrowRate;

      if(liquidityRate>0){
        uint256 linearInterest=WadRayMath.calculateLinearInterest(liquidityRate, timeDelta);
        reserve.liquidityIndex=uint128((uint256(reserve.liquidityIndex)*linearInterest)/1e27);
      }
      if(variableBorrowRate>0){
        uint256 compoundInterest=WadRayMath.calculateCompoundedInterest(variableBorrowRate, timeDelta);
        reserve.variableBorrowIndex=uint128((uint256(reserve.variableBorrowIndex)*compoundInterest)/1e27);
      }
      reserve.lastUpdateTimestamp=uint40(currentTimestamp);

    }
    function updateInterestRate(
        DataTypes.ReserveData storage reserve,
        address asset,
        uint256 addedLiquidity,
        uint256 removedLiquidity
    ) internal {
        // 1. Get total debts
        uint256 totalStableDebt = IStableDebtToken(reserve.stableDebtTokenAddress).totalSupply();
        uint256 totalVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).totalSupply();
        
        // 2. Calculate total debt
        uint256 totalDebt = totalStableDebt + totalVariableDebt;
        
        // 3. Calculate adjusted available liquidity for rate calculation
        uint256 availableLiquidity = reserve.availableLiquidity + addedLiquidity - removedLiquidity;
        
        // 4. Call interest rate strategy to get new rates
        (uint256 newLiquidityRate, uint256 newVariableRate, uint256 newStableRate) = 
            IInterestRateStrategy(reserve.interestRateStrategyAddress)
                .calculateInterestRate(availableLiquidity, totalDebt);
        
        // 5. Update reserve rates
        reserve.currentLiquidityRate = uint128(newLiquidityRate);
        reserve.currentVariableBorrowRate = uint128(newVariableRate);
        reserve.currentStableBorrowRate = uint128(newStableRate);
        
        // 6. Emit event
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
