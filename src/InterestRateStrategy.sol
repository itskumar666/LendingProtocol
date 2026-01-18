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

interface IInterestRateStrategy {
    function calculateInterestRate(
        uint256 totalLiquidity,
        uint256 totalBorrow,
        uint256 totalReserves
    ) external view returns (uint256 variableRate, uint256 stableRate);
}

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
        uint256 totalBorrow,
        uint256 totalReserves
    ) external pure override returns (uint256 variableRate, uint256 stableRate) {
        
        if (totalLiquidity == 0) {
            return (0, 0);
        }
        
        uint256 utilizationRate = (totalBorrow * 100e2) / (totalLiquidity + totalBorrow);
        
        if (utilizationRate <= OPTIMAL_UTILIZATION) {
            // Below optimal: gradual increase
            variableRate = BASE_RATE + (utilizationRate * SLOPE1) / 100e2;
        } else {
            // Above optimal: steep increase
            uint256 excessUtilization = utilizationRate - OPTIMAL_UTILIZATION;
            variableRate = BASE_RATE + 
                          (OPTIMAL_UTILIZATION * SLOPE1) / 100e2 + 
                          (excessUtilization * SLOPE2) / 100e2;
        }
        
        // Stable rate slightly higher than variable
        stableRate = (variableRate * 125) / 100; // +25% buffer
    }
}
