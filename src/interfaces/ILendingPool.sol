// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/types/DataTypes.sol";

/**
 * @title ILendingPool
 * @notice Interface for the LendingPool contract
 * @dev Main entry point for protocol interactions
 */
interface ILendingPool {
    
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
        uint256 interestRateMode,
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
        uint256 interestRateMode,
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

    /**
     * @notice Allows anyone to flash borrow assets from the pool
     * @param receiverAddress The address of the contract receiving the funds
     * @param assets The addresses of the assets being flash-borrowed
     * @param amounts The amounts of the assets being flash-borrowed
     * @param interestRateModes The interest rate modes for incurring debt (0 = no debt, 1 = stable, 2 = variable)
     * @param onBehalfOf The address that will receive the debt if mode != 0
     * @param params Variadic packed params to pass to the receiver
     * @param referralCode Code for potential rewards
     */
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

    /**
     * @notice Allows depositors to enable/disable a specific deposited asset as collateral
     * @param asset The address of the underlying asset
     * @param useAsCollateral True if the user wants to use the asset as collateral
     */
    function setUserUseReserveAsCollateral(
        address asset,
        bool useAsCollateral
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

    /**
     * @notice Returns the state and configuration of a reserve
     * @param asset The address of the underlying asset
     * @return The reserve data
     */
    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory);

    /**
     * @notice Returns the configuration of a user's collateral and borrowing
     * @param user The address of the user
     * @return The user configuration bitmap
     */
    function getUserConfiguration(address user) external view returns (DataTypes.UserConfigurationMap memory);

    /**
     * @notice Returns the configuration of a reserve
     * @param asset The address of the underlying asset
     * @return The reserve configuration
     */
    function getConfiguration(address asset) external view returns (DataTypes.ReserveConfigurationMap memory);

    /**
     * @notice Returns the normalized income for a reserve
     * @param asset The address of the underlying asset
     * @return The reserve normalized income
     */
    function getReserveNormalizedIncome(address asset) external view returns (uint256);

    /**
     * @notice Returns the normalized debt for a reserve
     * @param asset The address of the underlying asset
     * @return The reserve normalized debt
     */
    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256);

    /**
     * @notice Returns the list of all reserve addresses
     * @return The list of reserves
     */
    function getReservesList() external view returns (address[] memory);
}
