// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title ILendingPool
 * @notice Interface for the LendingPool contract
 * @dev Main entry point for protocol interactions
 */
interface ILendingPool {
    
    // ==================== EVENTS ====================
    
    event Deposit(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint16 indexed referralCode
    );
    
    event Withdraw(
        address indexed reserve,
        address indexed user,
        address indexed to,
        uint256 amount
    );
    
    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint8 interestRateMode,
        uint256 borrowRate,
        uint16 indexed referralCode
    );
    
    event Repay(
        address indexed reserve,
        address indexed user,
        address indexed repayer,
        uint256 amount,
        bool useATokens
    );
    
    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken
    );
    
    event ReserveUsedAsCollateralEnabled(
        address indexed reserve,
        address indexed user
    );
    
    event ReserveUsedAsCollateralDisabled(
        address indexed reserve,
        address indexed user
    );
    
    // ==================== CORE FUNCTIONS ====================
    
    /**
     * @notice Deposits an `amount` of underlying asset into the reserve
     * @param asset The address of the underlying asset to deposit
     * @param amount The amount to be deposited
     * @param onBehalfOf The address that will receive the aTokens
     * @param referralCode Code used to register the integrator
     */
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;
    
    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn (use type(uint256).max to withdraw all)
     * @param to The address that will receive the underlying
     * @return The final amount withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
    
    /**
     * @notice Allows users to borrow a specific amount of the reserve underlying asset
     * @param asset The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param interestRateMode The interest rate mode (1 = Stable, 2 = Variable)
     * @param referralCode Code used to register the integrator
     * @param onBehalfOf The address that will receive the debt
     */
    function borrow(
        address asset,
        uint256 amount,
        uint8 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;
    
    /**
     * @notice Repays a borrowed amount on a specific reserve
     * @param asset The address of the borrowed underlying asset
     * @param amount The amount to repay (use type(uint256).max to repay all)
     * @param interestRateMode The interest rate mode (1 = Stable, 2 = Variable)
     * @param onBehalfOf The address of the user who will get his debt reduced
     * @return The final amount repaid
     */
    function repay(
        address asset,
        uint256 amount,
        uint8 interestRateMode,
        address onBehalfOf
    ) external returns (uint256);
    
    /**
     * @notice Liquidate a position when healthFactor < 1
     * @param collateralAsset The address of the collateral to liquidate
     * @param debtAsset The address of the debt asset
     * @param user The address of the borrower
     * @param debtToCover The amount of debt to cover
     * @param receiveAToken True if liquidator wants to receive aTokens, false for underlying
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @notice Returns the user account data across all reserves
     * @param user The address of the user
     * @return totalCollateralBase The total collateral in base currency
     * @return totalDebtBase The total debt in base currency
     * @return availableBorrowsBase The available borrow capacity in base currency
     * @return currentLiquidationThreshold The liquidation threshold
     * @return ltv The loan to value
     * @return healthFactor The current health factor
     */
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}
