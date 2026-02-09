// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title ReserveConfiguration
 * @notice Library for encoding/decoding reserve configuration data
 * @dev All configuration is packed into a single uint256 for gas efficiency
 * 
 * Bit layout (256 bits total):
 * | Bit  0-15  | LTV (loan-to-value)                | Max 65535 = 655.35%
 * | Bit 16-31  | Liquidation threshold              | Max 65535 = 655.35%
 * | Bit 32-47  | Liquidation bonus                  | Max 65535 = 655.35%
 * | Bit 48-55  | Decimals                           | Max 255
 * | Bit 56     | Reserve is active                  | bool
 * | Bit 57     | Reserve is frozen                  | bool
 * | Bit 58     | Borrowing is enabled               | bool
 * | Bit 59     | Stable rate borrowing enabled      | bool
 * | Bit 60     | Asset is paused                    | bool
 * | Bit 61     | Borrowing in isolation mode        | bool
 * | Bit 62     | Siloed borrowing                   | bool
 * | Bit 63     | Flashloan enabled                  | bool
 * | Bit 64-79  | Reserve factor                     | Max 65535 = 655.35%
 * | Bit 80-115 | Borrow cap (in whole tokens)       | Max ~68 billion
 * | Bit 116-151| Supply cap (in whole tokens)       | Max ~68 billion
 * | Bit 152-167| Liquidation protocol fee           | Max 65535 = 655.35%
 * | Bit 168-175| eMode category                     | Max 255 categories
 * | Bit 176-211| Unbacked mint cap                  | Max ~68 billion
 * | Bit 212-223| Debt ceiling (in isolation mode)   | Max 4095
 * | Bit 224-255| Reserved for future use            |
 */
library ReserveConfiguration {
    
    // ============ Bit Masks ============
    
    uint256 internal constant LTV_MASK =                         0xFFFF; // 16 bits
    uint256 internal constant LIQUIDATION_THRESHOLD_MASK =       0xFFFF; // 16 bits
    uint256 internal constant LIQUIDATION_BONUS_MASK =           0xFFFF; // 16 bits
    uint256 internal constant DECIMALS_MASK =                    0xFF;   // 8 bits
    uint256 internal constant ACTIVE_MASK =                      0x01;   // 1 bit
    uint256 internal constant FROZEN_MASK =                      0x01;   // 1 bit
    uint256 internal constant BORROWING_MASK =                   0x01;   // 1 bit
    uint256 internal constant STABLE_BORROWING_MASK =            0x01;   // 1 bit
    uint256 internal constant PAUSED_MASK =                      0x01;   // 1 bit
    uint256 internal constant BORROWABLE_IN_ISOLATION_MASK =     0x01;   // 1 bit
    uint256 internal constant SILOED_BORROWING_MASK =            0x01;   // 1 bit
    uint256 internal constant FLASHLOAN_ENABLED_MASK =           0x01;   // 1 bit
    uint256 internal constant RESERVE_FACTOR_MASK =              0xFFFF; // 16 bits
    uint256 internal constant BORROW_CAP_MASK =                  0xFFFFFFFFF; // 36 bits
    uint256 internal constant SUPPLY_CAP_MASK =                  0xFFFFFFFFF; // 36 bits
    uint256 internal constant LIQUIDATION_PROTOCOL_FEE_MASK =    0xFFFF; // 16 bits
    uint256 internal constant EMODE_CATEGORY_MASK =              0xFF;   // 8 bits
    uint256 internal constant UNBACKED_MINT_CAP_MASK =           0xFFFFFFFFF; // 36 bits
    uint256 internal constant DEBT_CEILING_MASK =                0xFFF;  // 12 bits
    
    // ============ Bit Positions ============
    
    uint256 internal constant LTV_START_BIT_POSITION =                      0;
    uint256 internal constant LIQUIDATION_THRESHOLD_START_BIT_POSITION =    16;
    uint256 internal constant LIQUIDATION_BONUS_START_BIT_POSITION =        32;
    uint256 internal constant DECIMALS_START_BIT_POSITION =                 48;
    uint256 internal constant IS_ACTIVE_START_BIT_POSITION =                56;
    uint256 internal constant IS_FROZEN_START_BIT_POSITION =                57;
    uint256 internal constant BORROWING_ENABLED_START_BIT_POSITION =        58;
    uint256 internal constant STABLE_BORROWING_ENABLED_START_BIT_POSITION = 59;
    uint256 internal constant IS_PAUSED_START_BIT_POSITION =                60;
    uint256 internal constant BORROWABLE_IN_ISOLATION_START_BIT_POSITION =  61;
    uint256 internal constant SILOED_BORROWING_START_BIT_POSITION =         62;
    uint256 internal constant FLASHLOAN_ENABLED_START_BIT_POSITION =        63;
    uint256 internal constant RESERVE_FACTOR_START_BIT_POSITION =           64;
    uint256 internal constant BORROW_CAP_START_BIT_POSITION =               80;
    uint256 internal constant SUPPLY_CAP_START_BIT_POSITION =               116;
    uint256 internal constant LIQUIDATION_PROTOCOL_FEE_START_BIT_POSITION = 152;
    uint256 internal constant EMODE_CATEGORY_START_BIT_POSITION =           168;
    uint256 internal constant UNBACKED_MINT_CAP_START_BIT_POSITION =        176;
    uint256 internal constant DEBT_CEILING_START_BIT_POSITION =             212;
    
    // ============ Constants ============
    
    /// @notice Maximum valid LTV (90% = 9000)
    uint256 internal constant MAX_VALID_LTV = 9500;
    
    /// @notice Maximum valid liquidation threshold (95% = 9500)
    uint256 internal constant MAX_VALID_LIQUIDATION_THRESHOLD = 9900;
    
    /// @notice Maximum valid liquidation bonus (15% = 11500 means 100% + 15%)
    uint256 internal constant MAX_VALID_LIQUIDATION_BONUS = 11500;
    
    /// @notice Maximum valid reserve factor (100% = 10000)
    uint256 internal constant MAX_VALID_RESERVE_FACTOR = 10000;
    
    /// @notice Maximum number of reserves (limited by bitmap)
    uint256 internal constant MAX_RESERVES_COUNT = 128;
    
    // ============ Getter Functions ============
    
    /**
     * @notice Get the loan-to-value ratio
     * @param self The reserve configuration
     * @return The LTV in basis points (e.g., 7500 = 75%)
     */
    function getLtv(DataTypes.ReserveConfigurationMap storage self) 
        internal 
        view 
        returns (uint256) 
    {
        return self.data & LTV_MASK;
    }
    
    /**
     * @notice Get the liquidation threshold
     * @param self The reserve configuration
     * @return The liquidation threshold in basis points (e.g., 8000 = 80%)
     */
    function getLiquidationThreshold(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data >> LIQUIDATION_THRESHOLD_START_BIT_POSITION) & LIQUIDATION_THRESHOLD_MASK;
    }
    
    /**
     * @notice Get the liquidation bonus
     * @param self The reserve configuration
     * @return The liquidation bonus (e.g., 10500 = 5% bonus, base is 10000)
     */
    function getLiquidationBonus(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data >> LIQUIDATION_BONUS_START_BIT_POSITION) & LIQUIDATION_BONUS_MASK;
    }
    
    /**
     * @notice Get the decimals of the underlying asset
     * @param self The reserve configuration
     * @return The decimals
     */
    function getDecimals(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data >> DECIMALS_START_BIT_POSITION) & DECIMALS_MASK;
    }
    
    /**
     * @notice Get the active status
     * @param self The reserve configuration
     * @return True if the reserve is active
     */
    function getActive(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (bool)
    {
        return (self.data >> IS_ACTIVE_START_BIT_POSITION) & ACTIVE_MASK != 0;
    }
    
    /**
     * @notice Get the frozen status
     * @param self The reserve configuration
     * @return True if the reserve is frozen
     */
    function getFrozen(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (bool)
    {
        return (self.data >> IS_FROZEN_START_BIT_POSITION) & FROZEN_MASK != 0;
    }
    
    /**
     * @notice Get the paused status
     * @param self The reserve configuration
     * @return True if the reserve is paused
     */
    function getPaused(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (bool)
    {
        return (self.data >> IS_PAUSED_START_BIT_POSITION) & PAUSED_MASK != 0;
    }
    
    /**
     * @notice Get the borrowing enabled status
     * @param self The reserve configuration
     * @return True if borrowing is enabled
     */
    function getBorrowingEnabled(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (bool)
    {
        return (self.data >> BORROWING_ENABLED_START_BIT_POSITION) & BORROWING_MASK != 0;
    }
    
    /**
     * @notice Get the stable borrowing enabled status
     * @param self The reserve configuration
     * @return True if stable rate borrowing is enabled
     */
    function getStableRateBorrowingEnabled(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (bool)
    {
        return (self.data >> STABLE_BORROWING_ENABLED_START_BIT_POSITION) & STABLE_BORROWING_MASK != 0;
    }
    
    /**
     * @notice Get the reserve factor
     * @param self The reserve configuration
     * @return The reserve factor in basis points (e.g., 1000 = 10%)
     */
    function getReserveFactor(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data >> RESERVE_FACTOR_START_BIT_POSITION) & RESERVE_FACTOR_MASK;
    }
    
    /**
     * @notice Get the borrow cap
     * @param self The reserve configuration
     * @return The borrow cap in whole tokens
     */
    function getBorrowCap(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data >> BORROW_CAP_START_BIT_POSITION) & BORROW_CAP_MASK;
    }
    
    /**
     * @notice Get the supply cap
     * @param self The reserve configuration
     * @return The supply cap in whole tokens
     */
    function getSupplyCap(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data >> SUPPLY_CAP_START_BIT_POSITION) & SUPPLY_CAP_MASK;
    }
    
    /**
     * @notice Get the liquidation protocol fee
     * @param self The reserve configuration
     * @return The liquidation protocol fee in basis points
     */
    function getLiquidationProtocolFee(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data >> LIQUIDATION_PROTOCOL_FEE_START_BIT_POSITION) & LIQUIDATION_PROTOCOL_FEE_MASK;
    }
    
    /**
     * @notice Get the eMode category
     * @param self The reserve configuration
     * @return The eMode category ID
     */
    function getEModeCategory(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256)
    {
        return (self.data >> EMODE_CATEGORY_START_BIT_POSITION) & EMODE_CATEGORY_MASK;
    }
    
    /**
     * @notice Get flashloan enabled status
     * @param self The reserve configuration
     * @return True if flashloans are enabled
     */
    function getFlashLoanEnabled(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (bool)
    {
        return (self.data >> FLASHLOAN_ENABLED_START_BIT_POSITION) & FLASHLOAN_ENABLED_MASK != 0;
    }
    
    /**
     * @notice Get multiple parameters at once (gas efficient)
     * @param self The reserve configuration
     * @return ltv The LTV
     * @return liquidationThreshold The liquidation threshold
     * @return liquidationBonus The liquidation bonus
     * @return decimals The decimals
     * @return reserveFactor The reserve factor
     */
    function getParams(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 decimals,
            uint256 reserveFactor
        )
    {
        uint256 data = self.data;
        
        ltv = data & LTV_MASK;
        liquidationThreshold = (data >> LIQUIDATION_THRESHOLD_START_BIT_POSITION) & LIQUIDATION_THRESHOLD_MASK;
        liquidationBonus = (data >> LIQUIDATION_BONUS_START_BIT_POSITION) & LIQUIDATION_BONUS_MASK;
        decimals = (data >> DECIMALS_START_BIT_POSITION) & DECIMALS_MASK;
        reserveFactor = (data >> RESERVE_FACTOR_START_BIT_POSITION) & RESERVE_FACTOR_MASK;
    }
    
    /**
     * @notice Get flags at once (gas efficient)
     * @param self The reserve configuration
     * @return isActive Reserve is active
     * @return isFrozen Reserve is frozen
     * @return borrowingEnabled Borrowing is enabled
     * @return stableBorrowRateEnabled Stable rate is enabled
     * @return isPaused Reserve is paused
     */
    function getFlags(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (
            bool isActive,
            bool isFrozen,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isPaused
        )
    {
        uint256 data = self.data;
        
        isActive = (data >> IS_ACTIVE_START_BIT_POSITION) & ACTIVE_MASK != 0;
        isFrozen = (data >> IS_FROZEN_START_BIT_POSITION) & FROZEN_MASK != 0;
        borrowingEnabled = (data >> BORROWING_ENABLED_START_BIT_POSITION) & BORROWING_MASK != 0;
        stableBorrowRateEnabled = (data >> STABLE_BORROWING_ENABLED_START_BIT_POSITION) & STABLE_BORROWING_MASK != 0;
        isPaused = (data >> IS_PAUSED_START_BIT_POSITION) & PAUSED_MASK != 0;
    }
    
    /**
     * @notice Get caps at once (gas efficient)
     * @param self The reserve configuration
     * @return borrowCap The borrow cap
     * @return supplyCap The supply cap
     */
    function getCaps(DataTypes.ReserveConfigurationMap storage self)
        internal
        view
        returns (uint256 borrowCap, uint256 supplyCap)
    {
        uint256 data = self.data;
        borrowCap = (data >> BORROW_CAP_START_BIT_POSITION) & BORROW_CAP_MASK;
        supplyCap = (data >> SUPPLY_CAP_START_BIT_POSITION) & SUPPLY_CAP_MASK;
    }
    
    // ============ Setter Functions ============
    
    /**
     * @notice Set the LTV
     * @param self The reserve configuration
     * @param ltv The new LTV value
     */
    function setLtv(DataTypes.ReserveConfigurationMap storage self, uint256 ltv) internal {
        require(ltv <= MAX_VALID_LTV, "Invalid LTV");
        self.data = (self.data & ~LTV_MASK) | ltv;
    }
    
    /**
     * @notice Set the liquidation threshold
     * @param self The reserve configuration
     * @param threshold The new liquidation threshold
     */
    function setLiquidationThreshold(
        DataTypes.ReserveConfigurationMap storage self, 
        uint256 threshold
    ) internal {
        require(threshold <= MAX_VALID_LIQUIDATION_THRESHOLD, "Invalid liquidation threshold");
        self.data = (self.data & ~(LIQUIDATION_THRESHOLD_MASK << LIQUIDATION_THRESHOLD_START_BIT_POSITION)) 
            | (threshold << LIQUIDATION_THRESHOLD_START_BIT_POSITION);
    }
    
    /**
     * @notice Set the liquidation bonus
     * @param self The reserve configuration
     * @param bonus The new liquidation bonus
     */
    function setLiquidationBonus(
        DataTypes.ReserveConfigurationMap storage self, 
        uint256 bonus
    ) internal {
        require(bonus <= MAX_VALID_LIQUIDATION_BONUS, "Invalid liquidation bonus");
        self.data = (self.data & ~(LIQUIDATION_BONUS_MASK << LIQUIDATION_BONUS_START_BIT_POSITION)) 
            | (bonus << LIQUIDATION_BONUS_START_BIT_POSITION);
    }
    
    /**
     * @notice Set the decimals
     * @param self The reserve configuration
     * @param decimals The decimals of the underlying asset
     */
    function setDecimals(
        DataTypes.ReserveConfigurationMap storage self, 
        uint256 decimals
    ) internal {
        require(decimals <= 255, "Invalid decimals");
        self.data = (self.data & ~(DECIMALS_MASK << DECIMALS_START_BIT_POSITION)) 
            | (decimals << DECIMALS_START_BIT_POSITION);
    }
    
    /**
     * @notice Set the active status
     * @param self The reserve configuration
     * @param active The new active status
     */
    function setActive(DataTypes.ReserveConfigurationMap storage self, bool active) internal {
        self.data = (self.data & ~(ACTIVE_MASK << IS_ACTIVE_START_BIT_POSITION)) 
            | (uint256(active ? 1 : 0) << IS_ACTIVE_START_BIT_POSITION);
    }
    
    /**
     * @notice Set the frozen status
     * @param self The reserve configuration
     * @param frozen The new frozen status
     */
    function setFrozen(DataTypes.ReserveConfigurationMap storage self, bool frozen) internal {
        self.data = (self.data & ~(FROZEN_MASK << IS_FROZEN_START_BIT_POSITION)) 
            | (uint256(frozen ? 1 : 0) << IS_FROZEN_START_BIT_POSITION);
    }
    
    /**
     * @notice Set the paused status
     * @param self The reserve configuration
     * @param paused The new paused status
     */
    function setPaused(DataTypes.ReserveConfigurationMap storage self, bool paused) internal {
        self.data = (self.data & ~(PAUSED_MASK << IS_PAUSED_START_BIT_POSITION)) 
            | (uint256(paused ? 1 : 0) << IS_PAUSED_START_BIT_POSITION);
    }
    
    /**
     * @notice Set borrowing enabled status
     * @param self The reserve configuration
     * @param enabled The new borrowing enabled status
     */
    function setBorrowingEnabled(
        DataTypes.ReserveConfigurationMap storage self, 
        bool enabled
    ) internal {
        self.data = (self.data & ~(BORROWING_MASK << BORROWING_ENABLED_START_BIT_POSITION)) 
            | (uint256(enabled ? 1 : 0) << BORROWING_ENABLED_START_BIT_POSITION);
    }
    
    /**
     * @notice Set stable rate borrowing enabled status
     * @param self The reserve configuration
     * @param enabled The new stable rate borrowing enabled status
     */
    function setStableRateBorrowingEnabled(
        DataTypes.ReserveConfigurationMap storage self, 
        bool enabled
    ) internal {
        self.data = (self.data & ~(STABLE_BORROWING_MASK << STABLE_BORROWING_ENABLED_START_BIT_POSITION)) 
            | (uint256(enabled ? 1 : 0) << STABLE_BORROWING_ENABLED_START_BIT_POSITION);
    }
    
    /**
     * @notice Set the reserve factor
     * @param self The reserve configuration
     * @param reserveFactor The new reserve factor
     */
    function setReserveFactor(
        DataTypes.ReserveConfigurationMap storage self, 
        uint256 reserveFactor
    ) internal {
        require(reserveFactor <= MAX_VALID_RESERVE_FACTOR, "Invalid reserve factor");
        self.data = (self.data & ~(RESERVE_FACTOR_MASK << RESERVE_FACTOR_START_BIT_POSITION)) 
            | (reserveFactor << RESERVE_FACTOR_START_BIT_POSITION);
    }
    
    /**
     * @notice Set the borrow cap
     * @param self The reserve configuration
     * @param borrowCap The new borrow cap (in whole tokens)
     */
    function setBorrowCap(
        DataTypes.ReserveConfigurationMap storage self, 
        uint256 borrowCap
    ) internal {
        require(borrowCap <= BORROW_CAP_MASK, "Invalid borrow cap");
        self.data = (self.data & ~(BORROW_CAP_MASK << BORROW_CAP_START_BIT_POSITION)) 
            | (borrowCap << BORROW_CAP_START_BIT_POSITION);
    }
    
    /**
     * @notice Set the supply cap
     * @param self The reserve configuration
     * @param supplyCap The new supply cap (in whole tokens)
     */
    function setSupplyCap(
        DataTypes.ReserveConfigurationMap storage self, 
        uint256 supplyCap
    ) internal {
        require(supplyCap <= SUPPLY_CAP_MASK, "Invalid supply cap");
        self.data = (self.data & ~(SUPPLY_CAP_MASK << SUPPLY_CAP_START_BIT_POSITION)) 
            | (supplyCap << SUPPLY_CAP_START_BIT_POSITION);
    }
    
    /**
     * @notice Set the liquidation protocol fee
     * @param self The reserve configuration
     * @param fee The new liquidation protocol fee
     */
    function setLiquidationProtocolFee(
        DataTypes.ReserveConfigurationMap storage self, 
        uint256 fee
    ) internal {
        require(fee <= 10000, "Invalid protocol fee");
        self.data = (self.data & ~(LIQUIDATION_PROTOCOL_FEE_MASK << LIQUIDATION_PROTOCOL_FEE_START_BIT_POSITION)) 
            | (fee << LIQUIDATION_PROTOCOL_FEE_START_BIT_POSITION);
    }
    
    /**
     * @notice Set the eMode category
     * @param self The reserve configuration
     * @param category The new eMode category
     */
    function setEModeCategory(
        DataTypes.ReserveConfigurationMap storage self, 
        uint256 category
    ) internal {
        require(category <= 255, "Invalid eMode category");
        self.data = (self.data & ~(EMODE_CATEGORY_MASK << EMODE_CATEGORY_START_BIT_POSITION)) 
            | (category << EMODE_CATEGORY_START_BIT_POSITION);
    }
    
    /**
     * @notice Set flashloan enabled status
     * @param self The reserve configuration
     * @param enabled The new flashloan enabled status
     */
    function setFlashLoanEnabled(
        DataTypes.ReserveConfigurationMap storage self, 
        bool enabled
    ) internal {
        self.data = (self.data & ~(FLASHLOAN_ENABLED_MASK << FLASHLOAN_ENABLED_START_BIT_POSITION)) 
            | (uint256(enabled ? 1 : 0) << FLASHLOAN_ENABLED_START_BIT_POSITION);
    }
}
