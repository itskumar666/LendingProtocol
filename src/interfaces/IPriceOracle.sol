// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @notice Interface for the price oracle
 * @dev Provides asset prices in base currency (typically USD with 8 decimals)
 */
interface IPriceOracle {
    
    /**
     * @notice Returns the price of an asset in the base currency
     * @param asset The address of the asset
     * @return The price of the asset (scaled to base currency decimals, typically 8)
     */
    function getAssetPrice(address asset) external view returns (uint256);
    
    /**
     * @notice Returns prices of multiple assets
     * @param assets The addresses of the assets
     * @return Array of prices in base currency
     */
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);
    
    /**
     * @notice Returns the address of the source for an asset
     * @param asset The address of the asset
     * @return The address of the source (Chainlink aggregator, etc.)
     */
    function getSourceOfAsset(address asset) external view returns (address);
}
