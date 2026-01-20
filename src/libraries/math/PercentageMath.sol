// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title PercentageMath
 * @notice Math library for percentage calculations
 * 
 * PRECISION: 
 * - PERCENTAGE_FACTOR = 10000 (100.00%)
 * - 1 = 0.01% (1 basis point)
 * - 10000 = 100%
 * - 8000 = 80%
 * 
 * EXAMPLES:
 * - LTV 80% → 8000
 * - Liquidation bonus 5% → 500
 * - Flash loan fee 0.09% → 9
 * 
 * TODO: Implement percentage operations
 */
library PercentageMath {
    
    uint256 internal constant PERCENTAGE_FACTOR = 1e4; // 100.00%
    uint256 internal constant HALF_PERCENTAGE_FACTOR = 0.5e4; // 50.00%
    
    /**
     * Calculate percentage of value
     * 
     * TODO: Implement percentage multiplication:
     * result = (value * percentage + HALF_PERCENTAGE_FACTOR) / PERCENTAGE_FACTOR
     * 
     * EXAMPLE:
     * 1000 * 80% = 800
     * (1000 * 8000 + 5000) / 10000 = 800
     * 
     * Why add HALF_PERCENTAGE_FACTOR? Rounding to nearest integer
     */
    function percentMul(uint256 value, uint256 percentage) internal pure returns (uint256) {
        // TODO: Implement
        // Handle overflow
        if (value == 0 || percentage == 0) return 0;
        return (value * percentage + HALF_PERCENTAGE_FACTOR) / PERCENTAGE_FACTOR;

        
    }
    
    /**
     * Divide value by percentage
     * 
     * TODO: Implement percentage division:
     * result = (value * PERCENTAGE_FACTOR + halfPercentage) / percentage
     * 
     * EXAMPLE:
     * 800 / 80% = 1000
     * (800 * 10000 + 4000) / 8000 = 1000
     */
    function percentDiv(uint256 value, uint256 percentage) internal pure returns (uint256) {
        // TODO: Implement
        // Check percentage != 0
        if(percentage == 0) {
            revert("Percentage cannot be zero");
        }
        uint256 halfPercentage = percentage / 2;
        return (value * PERCENTAGE_FACTOR + halfPercentage) / percentage;
    }
}
