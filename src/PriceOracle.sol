// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IChainlinkAggregator} from "./interfaces/IChainlinkAggregator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PriceOracle
 * @notice Multi-source price oracle with aggregation, staleness checks, and fallback support
 * @dev Supports multiple price sources per asset with configurable aggregation strategies
 * 
 * Features:
 * - Multiple oracle sources per asset (Chainlink, custom feeds)
 * - Price aggregation strategies: median, average, weighted average
 * - Staleness detection with configurable thresholds
 * - Deviation detection between sources
 * - Fallback oracle support
 * - Price caching for gas optimization
 */
contract PriceOracle is IPriceOracle, Ownable {
    
    // ============ Enums ============
    
    enum AggregationStrategy {
        MEDIAN,          // Use median of all sources (most robust)
        AVERAGE,         // Simple average of all sources
        WEIGHTED,        // Weighted average based on source priority
        PRIMARY_ONLY     // Only use first source, others as fallback
    }
    
    // ============ Structs ============
    
    struct SourceConfig {
        address source;          // Oracle source address
        uint8 decimals;          // Price decimals
        uint96 weight;           // Weight for weighted average (basis points)
        bool isChainlink;        // True if Chainlink aggregator, false for custom
    }
    
    struct PriceData {
        uint216 price;           // The price (fits in 216 bits = ~1e65)
        uint40 timestamp;        // Last update timestamp
    }
    
    // ============ Constants ============
    
    /// @notice Base currency is USD (represented as address(0))
    address public constant override BASE_CURRENCY = address(0);
    
    /// @notice Base currency unit (8 decimals for USD)
    uint256 public constant override BASE_CURRENCY_UNIT = 1e8;
    
    /// @notice Maximum number of sources per asset
    uint256 public constant MAX_SOURCES = 5;
    
    /// @notice Maximum allowed deviation between sources (in basis points, 500 = 5%)
    uint256 public constant MAX_DEVIATION_THRESHOLD = 2000; // 20%
    
    // ============ State Variables ============
    
    /// @notice Mapping of asset => array of source configurations
    mapping(address => SourceConfig[]) private _assetSources;
    
    /// @notice Mapping of asset => aggregation strategy
    mapping(address => AggregationStrategy) public aggregationStrategy;
    
    /// @notice Fallback oracle address
    address private _fallbackOracle;
    
    /// @notice Stale price threshold in seconds (default: 1 hour)
    uint256 public stalePriceThreshold = 3600;
    
    /// @notice Price deviation threshold in basis points (default: 5%)
    uint256 public priceDeviationThreshold = 500;
    
    /// @notice Cached prices for gas optimization
    mapping(address => PriceData) private _cachedPrices;
    
    /// @notice Cache validity period in seconds
    uint256 public cacheValidityPeriod = 60; // 1 minute
    
    // ============ Constructor ============
    
    constructor(address initialOwner) Ownable(initialOwner) {}
    
    // ============ External View Functions ============
    
    /**
     * @inheritdoc IPriceOracle
     */
    function getAssetPrice(address asset) external view override returns (uint256) {
        return _getAssetPrice(asset);
    }
    
    /**
     * @inheritdoc IPriceOracle
     */
    function getAssetsPrices(address[] calldata assets) 
        external 
        view 
        override 
        returns (uint256[] memory) 
    {
        uint256[] memory prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = _getAssetPrice(assets[i]);
        }
        return prices;
    }
    
    /**
     * @inheritdoc IPriceOracle
     */
    function getAssetPriceInfo(address asset)
        external
        view
        override
        returns (uint256 price, uint256 timestamp, bool isValid)
    {
        SourceConfig[] storage sources = _assetSources[asset];
        
        if (sources.length == 0) {
            return (0, 0, false);
        }
        
        // Get price from primary source
        (price, timestamp) = _getPriceFromSource(sources[0]);
        isValid = price > 0 && (block.timestamp - timestamp) <= stalePriceThreshold;
        
        return (price, timestamp, isValid);
    }
    
    /**
     * @inheritdoc IPriceOracle
     */
    function getSourcesOfAsset(address asset) 
        external 
        view 
        override 
        returns (address[] memory) 
    {
        SourceConfig[] storage sources = _assetSources[asset];
        address[] memory sourceAddresses = new address[](sources.length);
        
        for (uint256 i = 0; i < sources.length; i++) {
            sourceAddresses[i] = sources[i].source;
        }
        
        return sourceAddresses;
    }
    
    /**
     * @inheritdoc IPriceOracle
     */
    function getSourceOfAsset(address asset) external view override returns (address) {
        SourceConfig[] storage sources = _assetSources[asset];
        if (sources.length == 0) return address(0);
        return sources[0].source;
    }
    
    /**
     * @inheritdoc IPriceOracle
     */
    function getFallbackOracle() external view override returns (address) {
        return _fallbackOracle;
    }
    
    /**
     * @notice Get number of sources for an asset
     */
    function getSourceCount(address asset) external view returns (uint256) {
        return _assetSources[asset].length;
    }
    
    /**
     * @notice Get detailed source configuration
     */
    function getSourceConfig(address asset, uint256 index) 
        external 
        view 
        returns (SourceConfig memory) 
    {
        return _assetSources[asset][index];
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Set price sources for an asset
     * @param asset The asset address
     * @param sources Array of source addresses
     * @param decimals Array of decimal values for each source
     * @param weights Array of weights for weighted averaging
     * @param isChainlink Array of booleans indicating if source is Chainlink
     */
    function setAssetSources(
        address asset,
        address[] calldata sources,
        uint8[] calldata decimals,
        uint96[] calldata weights,
        bool[] calldata isChainlink
    ) external onlyOwner {
        require(sources.length > 0, "At least one source required");
        require(sources.length <= MAX_SOURCES, "Too many sources");
        require(
            sources.length == decimals.length && 
            sources.length == weights.length &&
            sources.length == isChainlink.length,
            "Array length mismatch"
        );
        
        // Clear existing sources
        delete _assetSources[asset];
        
        uint256 totalWeight;
        for (uint256 i = 0; i < sources.length; i++) {
            require(sources[i] != address(0), "Invalid source address");
            
            _assetSources[asset].push(SourceConfig({
                source: sources[i],
                decimals: decimals[i],
                weight: weights[i],
                isChainlink: isChainlink[i]
            }));
            
            totalWeight += weights[i];
        }
        
        // For weighted strategy, weights must sum to 10000 (100%)
        if (aggregationStrategy[asset] == AggregationStrategy.WEIGHTED) {
            require(totalWeight == 10000, "Weights must sum to 10000");
        }
        
        emit AssetSourceUpdated(asset, sources);
    }
    
    /**
     * @notice Set aggregation strategy for an asset
     */
    function setAggregationStrategy(address asset, AggregationStrategy strategy) 
        external 
        onlyOwner 
    {
        aggregationStrategy[asset] = strategy;
    }
    
    /**
     * @notice Set the fallback oracle
     */
    function setFallbackOracle(address fallbackOracle) external onlyOwner {
        _fallbackOracle = fallbackOracle;
        emit FallbackOracleUpdated(fallbackOracle);
    }
    
    /**
     * @notice Set stale price threshold
     */
    function setStalePriceThreshold(uint256 threshold) external onlyOwner {
        require(threshold >= 60, "Threshold too low"); // Minimum 1 minute
        require(threshold <= 86400, "Threshold too high"); // Maximum 1 day
        stalePriceThreshold = threshold;
        emit StalePriceThresholdUpdated(threshold);
    }
    
    /**
     * @notice Set price deviation threshold
     */
    function setPriceDeviationThreshold(uint256 threshold) external onlyOwner {
        require(threshold <= MAX_DEVIATION_THRESHOLD, "Threshold too high");
        priceDeviationThreshold = threshold;
        emit PriceDeviationThresholdUpdated(threshold);
    }
    
    /**
     * @notice Set cache validity period
     */
    function setCacheValidityPeriod(uint256 period) external onlyOwner {
        require(period <= 300, "Cache period too long"); // Max 5 minutes
        cacheValidityPeriod = period;
    }
    
    /**
     * @notice Batch set sources for multiple assets
     */
    function batchSetAssetSources(
        address[] calldata assets,
        address[][] calldata sources,
        uint8[][] calldata decimals,
        uint96[][] calldata weights,
        bool[][] calldata isChainlink
    ) external onlyOwner {
        require(
            assets.length == sources.length &&
            assets.length == decimals.length &&
            assets.length == weights.length &&
            assets.length == isChainlink.length,
            "Array length mismatch"
        );
        
        for (uint256 i = 0; i < assets.length; i++) {
            _setAssetSourcesInternal(
                assets[i],
                sources[i],
                decimals[i],
                weights[i],
                isChainlink[i]
            );
        }
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Get asset price with aggregation logic
     */
    function _getAssetPrice(address asset) internal view returns (uint256) {
        // Check cache first
        PriceData storage cached = _cachedPrices[asset];
        if (cached.price > 0 && block.timestamp - cached.timestamp <= cacheValidityPeriod) {
            return cached.price;
        }
        
        SourceConfig[] storage sources = _assetSources[asset];
        
        // No sources configured, try fallback
        if (sources.length == 0) {
            return _getFallbackPrice(asset);
        }
        
        AggregationStrategy strategy = aggregationStrategy[asset];
        
        // Get prices from all sources
        uint256[] memory prices = new uint256[](sources.length);
        uint256[] memory timestamps = new uint256[](sources.length);
        uint256 validCount;
        
        for (uint256 i = 0; i < sources.length; i++) {
            (uint256 price, uint256 timestamp) = _getPriceFromSource(sources[i]);
            
            // Check for staleness
            if (price > 0 && (block.timestamp - timestamp) <= stalePriceThreshold) {
                prices[validCount] = price;
                timestamps[validCount] = timestamp;
                validCount++;
            }
        }
        
        // No valid prices, try fallback
        if (validCount == 0) {
            return _getFallbackPrice(asset);
        }
        
        // Apply aggregation strategy
        uint256 aggregatedPrice;
        
        if (strategy == AggregationStrategy.PRIMARY_ONLY || validCount == 1) {
            aggregatedPrice = prices[0];
        } else if (strategy == AggregationStrategy.AVERAGE) {
            aggregatedPrice = _calculateAverage(prices, validCount);
        } else if (strategy == AggregationStrategy.WEIGHTED) {
            aggregatedPrice = _calculateWeightedAverage(prices, sources, validCount);
        } else {
            // MEDIAN (default)
            aggregatedPrice = _calculateMedian(prices, validCount);
        }
        
        // Check deviation if multiple sources
        if (validCount > 1) {
            _checkDeviation(prices, validCount, aggregatedPrice, asset);
        }
        
        return aggregatedPrice;
    }
    
    /**
     * @notice Get price from a single source
     */
    function _getPriceFromSource(SourceConfig storage source) 
        internal 
        view 
        returns (uint256 price, uint256 timestamp) 
    {
        if (source.isChainlink) {
            return _getChainlinkPrice(source.source, source.decimals);
        } else {
            return _getCustomOraclePrice(source.source, source.decimals);
        }
    }
    
    /**
     * @notice Get price from Chainlink aggregator
     */
    function _getChainlinkPrice(address aggregator, uint8 sourceDecimals) 
        internal 
        view 
        returns (uint256 price, uint256 timestamp) 
    {
        try IChainlinkAggregator(aggregator).latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (answer <= 0) {
                return (0, 0);
            }
            
            // Normalize to BASE_CURRENCY_UNIT (8 decimals)
            if (sourceDecimals < 8) {
                price = uint256(answer) * (10 ** (8 - sourceDecimals));
            } else if (sourceDecimals > 8) {
                price = uint256(answer) / (10 ** (sourceDecimals - 8));
            } else {
                price = uint256(answer);
            }
            
            timestamp = updatedAt;
        } catch {
            return (0, 0);
        }
    }
    
    /**
     * @notice Get price from custom oracle (implements IPriceOracle interface)
     */
    function _getCustomOraclePrice(address oracle, uint8 sourceDecimals) 
        internal 
        view 
        returns (uint256 price, uint256 timestamp) 
    {
        try IPriceOracle(oracle).getAssetPrice(address(this)) returns (uint256 _price) {
            // Normalize decimals
            if (sourceDecimals < 8) {
                price = _price * (10 ** (8 - sourceDecimals));
            } else if (sourceDecimals > 8) {
                price = _price / (10 ** (sourceDecimals - 8));
            } else {
                price = _price;
            }
            
            timestamp = block.timestamp; // Custom oracles don't provide timestamp
        } catch {
            return (0, 0);
        }
    }
    
    /**
     * @notice Get price from fallback oracle
     */
    function _getFallbackPrice(address asset) internal view returns (uint256) {
        if (_fallbackOracle == address(0)) {
            revert PriceNotAvailable(asset);
        }
        
        try IPriceOracle(_fallbackOracle).getAssetPrice(asset) returns (uint256 price) {
            if (price == 0) {
                revert PriceNotAvailable(asset);
            }
            return price;
        } catch {
            revert PriceNotAvailable(asset);
        }
    }
    
    /**
     * @notice Calculate simple average of prices
     */
    function _calculateAverage(uint256[] memory prices, uint256 count) 
        internal 
        pure 
        returns (uint256) 
    {
        uint256 sum;
        for (uint256 i = 0; i < count; i++) {
            sum += prices[i];
        }
        return sum / count;
    }
    
    /**
     * @notice Calculate weighted average of prices
     */
    function _calculateWeightedAverage(
        uint256[] memory prices, 
        SourceConfig[] storage sources,
        uint256 count
    ) internal view returns (uint256) {
        uint256 weightedSum;
        uint256 totalWeight;
        
        for (uint256 i = 0; i < count; i++) {
            weightedSum += prices[i] * sources[i].weight;
            totalWeight += sources[i].weight;
        }
        
        if (totalWeight == 0) return prices[0];
        return weightedSum / totalWeight;
    }
    
    /**
     * @notice Calculate median of prices
     * @dev Uses insertion sort for small arrays (efficient for <= 5 elements)
     */
    function _calculateMedian(uint256[] memory prices, uint256 count) 
        internal 
        pure 
        returns (uint256) 
    {
        // Copy to avoid modifying original
        uint256[] memory sorted = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            sorted[i] = prices[i];
        }
        
        // Insertion sort (efficient for small arrays)
        for (uint256 i = 1; i < count; i++) {
            uint256 key = sorted[i];
            uint256 j = i;
            while (j > 0 && sorted[j - 1] > key) {
                sorted[j] = sorted[j - 1];
                j--;
            }
            sorted[j] = key;
        }
        
        // Return median
        if (count % 2 == 0) {
            // Even count: average of two middle values
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2;
        } else {
            // Odd count: middle value
            return sorted[count / 2];
        }
    }
    
    /**
     * @notice Check if price deviation between sources is acceptable
     */
    function _checkDeviation(
        uint256[] memory prices, 
        uint256 count, 
        uint256 aggregatedPrice,
        address asset
    ) internal view {
        for (uint256 i = 0; i < count; i++) {
            uint256 deviation;
            if (prices[i] > aggregatedPrice) {
                deviation = ((prices[i] - aggregatedPrice) * 10000) / aggregatedPrice;
            } else {
                deviation = ((aggregatedPrice - prices[i]) * 10000) / aggregatedPrice;
            }
            
            if (deviation > priceDeviationThreshold) {
                revert PriceDeviationTooHigh(asset, deviation);
            }
        }
    }
    
    /**
     * @notice Internal function to set asset sources
     */
    function _setAssetSourcesInternal(
        address asset,
        address[] calldata sources,
        uint8[] calldata decimals,
        uint96[] calldata weights,
        bool[] calldata isChainlink
    ) internal {
        require(sources.length > 0, "At least one source required");
        require(sources.length <= MAX_SOURCES, "Too many sources");
        
        delete _assetSources[asset];
        
        for (uint256 i = 0; i < sources.length; i++) {
            require(sources[i] != address(0), "Invalid source address");
            
            _assetSources[asset].push(SourceConfig({
                source: sources[i],
                decimals: decimals[i],
                weight: weights[i],
                isChainlink: isChainlink[i]
            }));
        }
        
        emit AssetSourceUpdated(asset, sources);
    }
    
    // ============ Cache Functions (for gas optimization) ============
    
    /**
     * @notice Update cached price (can be called by keepers)
     */
    function updatePriceCache(address asset) external {
        uint256 price = _getAssetPrice(asset);
        _cachedPrices[asset] = PriceData({
            price: uint216(price),
            timestamp: uint40(block.timestamp)
        });
    }
    
    /**
     * @notice Batch update cached prices
     */
    function batchUpdatePriceCache(address[] calldata assets) external {
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 price = _getAssetPrice(assets[i]);
            _cachedPrices[assets[i]] = PriceData({
                price: uint216(price),
                timestamp: uint40(block.timestamp)
            });
        }
    }
}
