// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @notice Interface for the price oracle
 * @dev Provides asset prices in base currency (typically USD with 8 decimals)
 */
interface IPriceOracle {
    
    // ============ Events ============
    
    event AssetSourceUpdated(address indexed asset, address[] sources);
    event FallbackOracleUpdated(address indexed fallbackOracle);
    event BaseCurrencySet(address indexed baseCurrency, uint256 baseCurrencyUnit);
    event PriceDeviationThresholdUpdated(uint256 newThreshold);
    event StalePriceThresholdUpdated(uint256 newThreshold);
    
    // ============ Errors ============
    
    error PriceNotAvailable(address asset);
    error StalePrice(address asset, uint256 timestamp);
    error PriceDeviationTooHigh(address asset, uint256 deviation);
    error NoSourcesConfigured(address asset);
    error InvalidPrice(address asset);
    
    // ============ View Functions ============
    
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
     * @notice Returns the addresses of all sources for an asset
     * @param asset The address of the asset
     * @return Array of source addresses (Chainlink aggregators, etc.)
     */
    function getSourcesOfAsset(address asset) external view returns (address[] memory);
    
    /**
     * @notice Returns the primary source for an asset
     * @param asset The address of the asset
     * @return The address of the primary source
     */
    function getSourceOfAsset(address asset) external view returns (address);
    
    /**
     * @notice Returns the fallback oracle address
     * @return The address of the fallback oracle
     */
    function getFallbackOracle() external view returns (address);
    
    /**
     * @notice Returns the base currency address (address(0) for USD)
     * @return The base currency address
     */
    function BASE_CURRENCY() external view returns (address);
    
    /**
     * @notice Returns the base currency unit (e.g., 1e8 for USD)
     * @return The base currency unit
     */
    function BASE_CURRENCY_UNIT() external view returns (uint256);
    
    /**
     * @notice Get detailed price info including timestamp and confidence
     * @param asset The address of the asset
     * @return price The price in base currency
     * @return timestamp The timestamp of the price
     * @return isValid Whether the price is considered valid
     */
    function getAssetPriceInfo(address asset) 
        external 
        view 
        returns (uint256 price, uint256 timestamp, bool isValid);
}
