// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title InterestRateStrategy
 * @notice Calculates interest rates based on utilization
 * 
 * QUICK POINTERS:
 * - Utilization Rate = Total Borrows / Total Liquidity
 * - Low utilization (e.g., 20%) → Low rates (e.g., 2% APY)
 * - High utilization (e.g., 95%) → High rates (e.g., 40% APY)
 * - This incentivizes lending when needed, discourages over-borrowing
 * - Can have different curves for different assets
 * 
 * Formula example (Linear):
 * Rate = baseRate + (utilizationRate * slope / 100)
 * If utilization > optimalRate: Rate = baseRate + slope + (utilizationRate - optimal) * slopeHigh
 */

import {IInterestRateStrategy} from './interfaces/IInterestRateStrategy.sol';  

contract DefaultInterestRateStrategy is IInterestRateStrategy {  
    
    uint256 public constant OPTIMAL_UTILIZATION = 80e2; // 80%
    uint256 public constant BASE_RATE = 0;              // 0%
    uint256 public constant SLOPE1 = 4e2;               // 4% (below optimal)
    uint256 public constant SLOPE2 = 100e2;             // 100% (above optimal)
    
    /**
     * Calculate variable rate based on utilization
     * POINTER: Below optimal utilization, rate increases slowly
     *          Above optimal, rate increases steeply to discourage over-borrowing
     */

    function calculateInterestRate(
    uint256 totalLiquidity,
    uint256 totalBorrow
) external override pure returns (
    uint256 liquidityRate,
    uint256 variableRate, 
    uint256 stableRate
) {
    if (totalLiquidity == 0) {
        return (0, 0, 0);
    }
    
    uint256 utilizationRate = (totalBorrow * 100e2) / (totalLiquidity + totalBorrow);
    
    // Calculate borrow rates
    if (utilizationRate <= OPTIMAL_UTILIZATION) {
        variableRate = BASE_RATE + (utilizationRate * SLOPE1) / 100e2;
    } else {
        uint256 excessUtilization = utilizationRate - OPTIMAL_UTILIZATION;
        variableRate = BASE_RATE + 
                      (OPTIMAL_UTILIZATION * SLOPE1) / 100e2 + 
                      (excessUtilization * SLOPE2) / 100e2;
    }
    
    stableRate = (variableRate * 125) / 100;
    
    // Calculate liquidity rate (what depositors earn)
    // Assume 50/50 stable/variable split for simplicity, no reserve factor
    uint256 avgBorrowRate = (variableRate + stableRate) / 2;
    liquidityRate = (avgBorrowRate * utilizationRate) / 100e2;
}
}
