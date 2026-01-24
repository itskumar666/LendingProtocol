// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title DataTypes
 * @notice Contains all protocol structs
 * Centralized data structure definitions - cleaner than having them in main contracts
 */
library DataTypes {
    
    /**
     * Reserve Configuration
     * Stores all data for each supported asset
     */
    struct ReserveData {
        // Token addresses
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        
        // Liquidity
        uint256 availableLiquidity;
        
        // Indexes
        uint128 liquidityIndex;
        uint128 variableBorrowIndex;
        uint128 currentLiquidityRate;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        
        // Configuration
        uint16 id; // Reserve ID for bitmap
        
        // Flags packed in single slot
        bool isActive;
        bool isFrozen;
        bool borrowingEnabled;
        bool stableBorrowRateEnabled;
        bool isPaused;
    }
    
    /**
     * Reserve Configuration Map
     * Packed configuration for gas optimization
     */
    struct ReserveConfigurationMap {
        uint256 data; // All config in one uint256
    }
    
    /**
     * User Configuration
     * Tracks user's positions across all reserves
     */
    struct UserConfigurationMap {
        uint256 data; // Bitmap of reserves user is using
    }
    
    /**
     * E-Mode Category
     * Higher LTV for correlated assets
     */
    struct EModeCategory {
        uint16 ltv;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        address priceSource;
        string label;
    }
      enum InterestRateMode {NONE, STABLE, VARIABLE}

    /**
     * User Account Data
     * Summary of user's financial position
     */
    struct UserAccountData {
        uint256 totalCollateralBase;
        uint256 totalDebtBase;
        uint256 availableBorrowsBase;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
    }
    
    /**
     * Execution parameters for deposit
     */
    struct ExecuteDepositParams {
        address asset;
        uint256 amount;
        address onBehalfOf;
        uint16 referralCode;
    }
    
    /**
     * Execution parameters for withdraw
     */
    struct ExecuteWithdrawParams {
        address asset;
        uint256 amount;
        address to;
    }
    
    /**
     * Execution parameters for borrow
     */
    struct ExecuteBorrowParams {
        address asset;
        address user;
        address onBehalfOf;
        uint256 amount;
        uint256 interestRateMode;
        uint16 referralCode;
        uint256 borrowCap;              // Max total borrows for this reserve
        uint256 totalStableDebt;        // Current stable debt
        uint256 totalVariableDebt;      // Current variable debt
        uint256 delegatedAllowance;     // Credit delegation allowance (if onBehalfOf != user)
        uint256 availableBorrows;       // User's available borrow capacity in base currency
        uint256 amountInBase;           // Borrow amount converted to base currency
    }
    
    /**
     * Execution parameters for repay
     */
    struct ExecuteRepayParams {
        address asset;
        uint256 amount;
        uint256 interestRateMode;
        address onBehalfOf;
    }
    
    /**
     * Execution parameters for liquidation
     */
    struct ExecuteLiquidationCallParams {
        uint256 reservesCount;
        uint256 debtToCover;
        address collateralAsset;
        address debtAsset;
        address user;
        bool receiveAToken;
    }
    
    /**
     * Calculate user account data parameters
     */
    struct CalculateUserAccountDataParams {
        UserConfigurationMap userConfig;
        uint256 reservesCount;
        address user;
        address oracle;
        uint8 userEModeCategory;
    }
    
    /**
     * Interest rate mode enum
     */
    uint256 internal constant INTEREST_RATE_MODE_NONE = 0;
    uint256 internal constant INTEREST_RATE_MODE_STABLE = 1;
    uint256 internal constant INTEREST_RATE_MODE_VARIABLE = 2;
}
