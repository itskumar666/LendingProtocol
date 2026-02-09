// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from '../types/DataTypes.sol';
import {Errors} from '../helpers/Errors.sol';

/**
 * @title UserConfiguration
 * @notice Library for managing user configuration bitmaps
 * @dev Uses a bitmap to track which reserves a user is using
 * 
 * Bitmap Layout (256 bits, supports 128 reserves):
 * - Even bits (0, 2, 4...): Is the user borrowing from this reserve?
 * - Odd bits (1, 3, 5...): Is the user using this reserve as collateral?
 * 
 * Example for reserve ID 5:
 * - Bit 10 (5*2): borrowing flag
 * - Bit 11 (5*2+1): collateral flag
 * 
 * Benefits:
 * - Gas efficient (single SSTORE to update)
 * - Quick iteration to find active positions
 * - O(1) lookup for any reserve
 */
library UserConfiguration {
    
    uint256 internal constant BORROWING_MASK = 0x5555555555555555555555555555555555555555555555555555555555555555;
    uint256 internal constant COLLATERAL_MASK = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
    
    /**
     * @notice Set user as borrowing from a reserve
     * @param self The user configuration
     * @param reserveIndex The reserve index
     * @param borrowing True if borrowing, false otherwise
     */
    function setBorrowing(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex,
        bool borrowing
    ) internal {
        require(reserveIndex < 128, Errors.INVALID_RESERVE_INDEX);
        uint256 bit = 1 << (reserveIndex * 2);
        if (borrowing) {
            self.data |= bit;
        } else {
            self.data &= ~bit;
        }
    }
    
    /**
     * @notice Set user as using reserve as collateral
     * @param self The user configuration
     * @param reserveIndex The reserve index
     * @param usingAsCollateral True if using as collateral
     */
    function setUsingAsCollateral(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex,
        bool usingAsCollateral
    ) internal {
        require(reserveIndex < 128, Errors.INVALID_RESERVE_INDEX);
        uint256 bit = 1 << (reserveIndex * 2 + 1);
        if (usingAsCollateral) {
            self.data |= bit;
        } else {
            self.data &= ~bit;
        }
    }
    
    /**
     * @notice Check if user is borrowing from any reserve
     * @param self The user configuration
     * @return True if user is borrowing from any reserve
     */
    function isBorrowingAny(DataTypes.UserConfigurationMap storage self) internal view returns (bool) {
        return (self.data & BORROWING_MASK) != 0;
    }
    
    /**
     * @notice Check if user is using any reserve as collateral
     * @param self The user configuration
     * @return True if user is using any reserve as collateral
     */
    function isUsingAsCollateralAny(DataTypes.UserConfigurationMap storage self) internal view returns (bool) {
        return (self.data & COLLATERAL_MASK) != 0;
    }
    
    /**
     * @notice Check if user is borrowing from a specific reserve
     * @param self The user configuration
     * @param reserveIndex The reserve index
     * @return True if user is borrowing from this reserve
     */
    function isBorrowing(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex
    ) internal view returns (bool) {
        require(reserveIndex < 128, Errors.INVALID_RESERVE_INDEX);
        return (self.data >> (reserveIndex * 2)) & 1 != 0;
    }
    
    /**
     * @notice Check if user is using a specific reserve as collateral
     * @param self The user configuration
     * @param reserveIndex The reserve index
     * @return True if user is using this reserve as collateral
     */
    function isUsingAsCollateral(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex
    ) internal view returns (bool) {
        require(reserveIndex < 128, Errors.INVALID_RESERVE_INDEX);
        return (self.data >> (reserveIndex * 2 + 1)) & 1 != 0;
    }
    
    /**
     * @notice Check if user is borrowing or using reserve as collateral
     * @param self The user configuration
     * @param reserveIndex The reserve index
     * @return True if user has any position in this reserve
     */
    function isUsingAsCollateralOrBorrowing(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex
    ) internal view returns (bool) {
        require(reserveIndex < 128, Errors.INVALID_RESERVE_INDEX);
        return (self.data >> (reserveIndex * 2)) & 3 != 0;
    }
    
    /**
     * @notice Check if user has empty configuration (no positions)
     * @param self The user configuration
     * @return True if user has no positions
     */
    function isEmpty(DataTypes.UserConfigurationMap storage self) internal view returns (bool) {
        return self.data == 0;
    }
    
    /**
     * @notice Get both borrowing and collateral status at once
     * @param self The user configuration
     * @param reserveIndex The reserve index
     * @return isBorrowingFlag True if borrowing
     * @return isUsingAsCollateralFlag True if using as collateral
     */
    function getFlags(
        DataTypes.UserConfigurationMap storage self,
        uint256 reserveIndex
    ) internal view returns (bool isBorrowingFlag, bool isUsingAsCollateralFlag) {
        require(reserveIndex < 128, Errors.INVALID_RESERVE_INDEX);
        uint256 bits = (self.data >> (reserveIndex * 2)) & 3;
        isBorrowingFlag = bits & 1 != 0;
        isUsingAsCollateralFlag = bits & 2 != 0;
    }
    
    /**
     * @notice Count number of reserves user is borrowing from
     * @param self The user configuration
     * @return count The number of reserves
     */
    function getBorrowingCount(DataTypes.UserConfigurationMap storage self) internal view returns (uint256 count) {
        uint256 data = self.data & BORROWING_MASK;
        while (data != 0) {
            count += data & 1;
            data >>= 2;
        }
    }
    
    /**
     * @notice Count number of reserves user is using as collateral
     * @param self The user configuration
     * @return count The number of reserves
     */
    function getCollateralCount(DataTypes.UserConfigurationMap storage self) internal view returns (uint256 count) {
        uint256 data = (self.data & COLLATERAL_MASK) >> 1;
        while (data != 0) {
            count += data & 1;
            data >>= 2;
        }
    }
    
    /**
     * @notice Get first collateral reserve index
     * @dev Useful for isolation mode (user can only use one collateral)
     * @param self The user configuration
     * @return The reserve index of first collateral, or 256 if none
     */
    function getFirstCollateralIndex(DataTypes.UserConfigurationMap storage self) internal view returns (uint256) {
        uint256 data = self.data;
        uint256 index;
        
        while (data != 0 && index < 128) {
            // Check collateral bit (odd position)
            if ((data >> 1) & 1 != 0) {
                return index;
            }
            data >>= 2;
            index++;
        }
        
        return 256; // No collateral found
    }
    
    /**
     * @notice Check if user is in isolation mode (using isolated asset as sole collateral)
     * @param self The user configuration
     * @return True if exactly one collateral and it's isolated
     */
    function isIsolated(DataTypes.UserConfigurationMap storage self) internal view returns (bool) {
        return getCollateralCount(self) == 1;
    }
    
    /**
     * @notice Check if user has only one type of borrow (for siloed borrowing check)
     * @param self The user configuration
     * @return True if user is borrowing from only one reserve
     */
    function isSiloed(DataTypes.UserConfigurationMap storage self) internal view returns (bool) {
        return getBorrowingCount(self) <= 1;
    }
}
