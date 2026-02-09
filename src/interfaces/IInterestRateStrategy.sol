// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IInterestRateStrategy
 * @notice Interface for the calculation of the interest rates
 * @dev Implements the interest rate model (usually based on utilization)
 */
interface IInterestRateStrategy {
    function calculateInterestRate(
        uint256 totalLiquidity,
        uint256 totalBorrow
    ) external view returns (
        uint256 liquidityRate,    
        uint256 variableRate,
        uint256 stableRate
    );
}