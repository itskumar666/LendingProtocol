// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title WadRayMath
 * @notice Math library for WAD (18 decimals) and RAY (27 decimals) precision
 * 
 * WAD = 10^18 (used for token amounts with 18 decimals)
 * RAY = 10^27 (used for interest rates and indexes - higher precision)
 * 
 * WHEN TO USE:
 * - WAD: Token balances, prices (1 ETH = 1e18)
 * - RAY: Interest rates, indexes (5% = 0.05e27)
 * 
 * TODO: Implement all math operations with overflow protection
 */
library WadRayMath {
    
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 0.5e18;
    
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;
    
    uint256 internal constant WAD_RAY_RATIO = 1e9;
    
    /**
     * Multiply two WAD numbers
     * 
     * TODO: Implement WAD multiplication:
     * result = (a * b + HALF_WAD) / WAD
     * 
     * EXAMPLE:
     * 1.5 WAD * 2.0 WAD = 3.0 WAD
     * (1.5e18 * 2.0e18 + 0.5e18) / 1e18 = 3.0e18
     * 
     * Why add HALF_WAD? For rounding (0.5 rounds up)
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        // TODO: Implement
        return(a*b+HALF_WAD)/WAD;
    }
    
    /**
     * Divide two WAD numbers
     * 
     * TODO: Implement WAD division:
     * result = (a * WAD + halfB) / b
     * where halfB = b / 2 (for rounding)
     * 
     * EXAMPLE:
     * 3.0 WAD / 2.0 WAD = 1.5 WAD
     * (3.0e18 * 1e18 + 1.0e18) / 2.0e18 = 1.5e18
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // TODO: Implement
        // Check b != 0
        if(b==0) return 0;
        return (a*WAD + (b/2))/b;

        
    }
    
    /**
     * Multiply two RAY numbers
     * 
     * TODO: Implement RAY multiplication:
     * result = (a * b + HALF_RAY) / RAY
     * 
     * EXAMPLE:
     * liquidityIndex 1.05 RAY * amount 100 RAY = 105 RAY
     * (1.05e27 * 100e27 + 0.5e27) / 1e27 = 105e27
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        // TODO: Implement
            return (a * b + HALF_RAY) / RAY;
    
    }
    
    /**
     * Divide two RAY numbers
     * 
     * TODO: Implement RAY division:
     * result = (a * RAY + halfB) / b
     * 
     * EXAMPLE:
     * 105 RAY / 1.05 RAY = 100 RAY
     * (105e27 * 1e27 + 0.525e27) / 1.05e27 = 100e27
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // TODO: Implement
        // Check b != 0
        if(b==0) return 0;
        return (a * RAY + (b / 2)) / b;
    
    }
    
    /**
     * Convert RAY to WAD (lose precision)
     * 
     * TODO: Implement RAY to WAD conversion:
     * result = (a + HALF_WAD_RAY_RATIO) / WAD_RAY_RATIO
     * where HALF_WAD_RAY_RATIO = WAD_RAY_RATIO / 2 = 1e9 / 2
     * 
     * EXAMPLE:
     * 1.234567890123456789012345678 RAY (27 decimals)
     * → 1.234567890123456789 WAD (18 decimals)
     * Lost precision: 012345678
     */
    function rayToWad(uint256 a) internal pure returns (uint256) {
        // TODO: Implement
        uint256 halfRatio = WAD_RAY_RATIO / 2;
        return (a + halfRatio) / WAD_RAY_RATIO;
    }
    
    /**
     * Convert WAD to RAY (add zeros)
     * 
     * TODO: Implement WAD to RAY conversion:
     * result = a * WAD_RAY_RATIO
     * 
     * EXAMPLE:
     * 1.234567890123456789 WAD (18 decimals)
     * → 1.234567890123456789000000000 RAY (27 decimals)
     */
    function wadToRay(uint256 a) internal pure returns (uint256) {
        // TODO: Implement
        return a * WAD_RAY_RATIO;
    }
}
