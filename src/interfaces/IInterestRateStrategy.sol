// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IInterestRateStrategy
 * @notice Interface for the calculation of the interest rates
 * @dev Implements the interest rate model (usually based on utilization)
 */
interface IInterestRateStrategy {
    
    /**
     * @notice Calculates the interest rates
     * @param params The parameters needed to calculate rates
     * @return liquidityRate The liquidity rate (APY for depositors)
     * @return stableBorrowRate The stable borrow rate
     * @return variableBorrowRate The variable borrow rate
     */
    function calculateInterestRates(
        CalculateInterestRatesParams memory params
    ) external view returns (
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate
    );
    
    /**
     * @dev Parameters for interest rate calculation
     */
    struct CalculateInterestRatesParams {
        uint256 unbacked;                   // Unbacked amount
        uint256 liquidityAdded;             // Amount of liquidity added
        uint256 liquidityTaken;             // Amount of liquidity taken
        uint256 totalStableDebt;            // Total stable debt
        uint256 totalVariableDebt;          // Total variable debt
        uint256 averageStableBorrowRate;    // Average stable borrow rate
        uint256 reserveFactor;              // Reserve factor
        address reserve;                    // Reserve asset address
        address aToken;                     // aToken address
    }
}
