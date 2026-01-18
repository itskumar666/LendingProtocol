// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// Interface for our tokens
interface IAToken {
    function mint(address user, uint256 amount) external;
    function burn(address user, uint256 amount) external;
    function balanceOf(address user) external view returns (uint256);
    function updateLiquidityIndex(uint256 newIndex) external;
}

interface IVariableDebtToken {
    function mint(address user, uint256 amount) external;
    function burn(address user, uint256 amount) external;
    function balanceOf(address user) external view returns (uint256);
    function updateBorrowIndex(uint256 newIndex) external;
}

interface IStableDebtToken {
    function mint(address user, uint256 amount, uint256 rate) external;
    function burn(address user, uint256 amount) external;
    function balanceOf(address user) external view returns (uint256);
    function getDebtWithInterest(address user) external view returns (uint256);
}

interface IPriceOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IInterestRateStrategy {
    function calculateInterestRates(
        uint256 totalLiquidity,
        uint256 totalDebt,
        uint256 utilizationRate
    ) external view returns (uint256 liquidityRate, uint256 variableBorrowRate, uint256 stableBorrowRate);
}

interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

/**
 * @title LendingPool
 * @notice Core contract managing ALL lending protocol operations
 * 
 * FEATURES:
 * - Deposit/Withdraw liquidity
 * - Borrow/Repay with variable or stable rates
 * - Liquidation of unhealthy positions
 * - Flash Loans (borrow without collateral, repay in same tx)
 * - E-Mode (higher LTV for correlated assets)
 * - Supply/Borrow Caps (risk management)
 * - Credit Delegation (let others borrow using your collateral)
 */
contract LendingPool is ReentrancyGuard, AccessControl, Pausable {
    
    // ==================== ERRORS ====================
    
    error LendingPool_ReserveNotActive();
    error LendingPool_ReservePaused();
    error LendingPool_AmountZero();
    error LendingPool_InsufficientBalance();
    error LendingPool_HealthFactorTooLow();
    error LendingPool_ExceedsBorrowLimit();
    error LendingPool_InvalidRateMode();
    error LendingPool_NoDebtToRepay();
    error LendingPool_HealthFactorOk(); // For liquidation - can't liquidate healthy position
    error LendingPool_SupplyCapExceeded();
    error LendingPool_BorrowCapExceeded();
    error LendingPool_FlashLoanFailed();
    error LendingPool_NotInEMode();
    error LendingPool_EModeNotAllowed();
    error LendingPool_InsufficientCreditDelegation();
    
    // ==================== ROLES ====================
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");
    
    // ==================== CONSTANTS ====================
    
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18; // 1.0 in 1e18 scale
    uint256 public constant MAX_STABLE_RATE = 1000e2; // 1000% max stable rate
    uint256 public constant FLASH_LOAN_FEE = 9; // 0.09% (9 basis points)
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // ==================== STATE STRUCTURES ====================
    
    /**
     * Reserve Token Addresses
     * Split out to avoid stack too deep
     */
    struct ReserveTokens {
        address underlying;           // The ERC20 token (USDC, WETH, etc.)
        address aToken;               // Interest-bearing deposit token
        address stableDebtToken;      // Stable rate debt token
        address variableDebtToken;    // Variable rate debt token
        address interestRateStrategy; // Contract that calculates interest rates
    }
    
    /**
     * Reserve Interest Data
     */
    struct ReserveInterest {
        uint256 liquidityIndex;           // For deposits (aToken)
        uint256 variableBorrowIndex;      // For variable debt
        uint40 lastUpdateTimestamp;       // When indexes were last updated
        uint256 currentLiquidityRate;     // APY for depositors
        uint256 currentVariableBorrowRate; // APY for variable borrowers
        uint256 currentStableBorrowRate;   // APY for stable borrowers
    }
    
    /**
     * Reserve Risk Parameters
     */
    struct ReserveRisk {
        uint16 ltv;                   // Loan-to-Value ratio (8000 = 80%)
        uint16 liquidationThreshold;  // When liquidation can happen (8500 = 85%)
        uint16 liquidationBonus;      // Bonus for liquidators (10500 = 105% = 5% bonus)
        uint16 reserveFactor;         // Protocol fee (1000 = 10%)
        uint256 supplyCap;            // Max total supply (0 = no cap)
        uint256 borrowCap;            // Max total borrow (0 = no cap)
        uint8 eModeCategoryId;        // E-Mode category (0 = no E-Mode)
    }
    
    /**
     * Reserve Flags
     */
    struct ReserveFlags {
        bool isActive;                // Can be used
        bool isPaused;                // Temporarily disabled
        bool isFrozen;                // No new deposits/borrows
        bool borrowingEnabled;        // Can this asset be borrowed
        bool stableBorrowEnabled;     // Is stable rate available
    }
    
    /**
     * E-Mode Category
     * Higher LTV for correlated assets (stablecoins, ETH derivatives)
     */
    struct EModeCategory {
        uint16 ltv;                   // Higher LTV (9700 = 97%)
        uint16 liquidationThreshold;  // Higher threshold (9800 = 98%)
        uint16 liquidationBonus;      // Lower bonus (10100 = 101%)
        address priceSource;          // Optional custom oracle
        string label;                 // "Stablecoins", "ETH correlated"
    }
    
    /**
     * User Configuration
     * Tracks user's positions across all reserves
     */
    struct UserConfiguration {
        uint8 eModeCategoryId;        // User's active E-Mode (0 = none)
        // Bitmap for which reserves user is using (gas optimization)
        uint256 borrowingBitmap;      // Which reserves user is borrowing from
        uint256 collateralBitmap;     // Which reserves user is using as collateral
    }
    
    // ==================== STATE VARIABLES ====================
    
    // Price oracle (Chainlink or custom)
    IPriceOracle public priceOracle;
    
    // All reserves
    mapping(address => ReserveData) public reserves;
    address[] public reservesList;
    uint256 public reservesCount;
    
    // E-Mode categories
    mapping(uint8 => EModeCategory) public eModeCategories;
    
    // User data
    mapping(address => UserConfiguration) public userConfiguration;
    
    // Credit delegation: delegator => delegatee => asset => amount
    mapping(address => mapping(address => mapping(address => uint256))) public borrowAllowance;
    
    // Flash loan premium to protocol treasury
    uint256 public flashLoanPremiumTotal;
    uint256 public flashLoanPremiumToProtocol;
    address public treasury;
    
    // ==================== EVENTS ====================
    
    event Deposit(address indexed user, address indexed reserve, uint256 amount, address indexed onBehalfOf);
    event Withdraw(address indexed user, address indexed reserve, uint256 amount, address indexed to);
    event Borrow(address indexed user, address indexed reserve, uint256 amount, uint8 rateMode, uint256 borrowRate);
    event Repay(address indexed user, address indexed reserve, uint256 amount, address indexed repayer);
    event LiquidationCall(address indexed collateral, address indexed debt, address indexed user, uint256 debtToCover, uint256 liquidatedCollateral, address liquidator);
    event FlashLoan(address indexed target, address indexed initiator, address indexed asset, uint256 amount, uint256 premium);
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);
    event EModeSet(address indexed user, uint8 categoryId);
    event BorrowAllowanceDelegated(address indexed fromUser, address indexed toUser, address indexed asset, uint256 amount);
    event ReserveDataUpdated(address indexed reserve, uint256 liquidityRate, uint256 stableBorrowRate, uint256 variableBorrowRate, uint256 liquidityIndex, uint256 variableBorrowIndex);
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(address _priceOracle, address _treasury) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(RISK_MANAGER_ROLE, msg.sender);
        _grantRole(EMERGENCY_ADMIN_ROLE, msg.sender);
        
        priceOracle = IPriceOracle(_priceOracle);
        treasury = _treasury;
        
        flashLoanPremiumTotal = 9; // 0.09%
        flashLoanPremiumToProtocol = 0; // Can be set later
    }
    
    // ============================================================
    // ==================== CORE FUNCTIONS ========================
    // ============================================================
    
    /**
     * ╔═══════════════════════════════════════════════════════════╗
     * ║                      DEPOSIT                               ║
     * ╠═══════════════════════════════════════════════════════════╣
     * ║ User deposits ERC20 → receives aToken → earns interest     ║
     * ╚═══════════════════════════════════════════════════════════╝
     * 
     * TODO: Implement deposit logic:
     * 
     * 1. VALIDATE INPUTS:
     *    - if (amount == 0) revert LendingPool_AmountZero()
     *    - if (!reserves[asset].isActive) revert LendingPool_ReserveNotActive()
     *    - if (reserves[asset].isPaused) revert LendingPool_ReservePaused()
     *    - if (reserves[asset].isFrozen) revert - no new deposits when frozen
     * 
     * 2. CHECK SUPPLY CAP:
     *    - uint256 supplyCap = reserves[asset].supplyCap
     *    - if (supplyCap > 0) {
     *        uint256 newTotal = reserves[asset].totalLiquidity + amount
     *        if (newTotal > supplyCap) revert LendingPool_SupplyCapExceeded()
     *      }
     * 
     * 3. UPDATE INTEREST INDEXES (before any state change):
     *    - Call _updateState(asset) to accrue interest since last update
     *    - This ensures interest is calculated correctly
     * 
     * 4. TRANSFER TOKENS FROM USER:
     *    - IERC20(asset).transferFrom(msg.sender, address(this), amount)
     *    - User must have approved LendingPool first
     * 
     * 5. MINT aTokens TO USER:
     *    - IAToken(reserves[asset].aToken).mint(onBehalfOf, amount)
     *    - aToken internally converts to scaled amount
     * 
     * 6. UPDATE RESERVE STATE:
     *    - reserves[asset].totalLiquidity += amount
     *    - reserves[asset].availableLiquidity += amount
     * 
     * 7. MARK AS COLLATERAL (if first deposit):
     *    - If user's collateral bitmap doesn't include this asset, add it
     *    - emit ReserveUsedAsCollateralEnabled(asset, onBehalfOf)
     * 
     * 8. EMIT EVENT:
     *    - emit Deposit(msg.sender, asset, amount, onBehalfOf)
     * 
     * EXAMPLE FLOW:
     * - User has 1000 USDC, approves LendingPool
     * - Calls deposit(USDC, 1000, userAddress)
     * - LendingPool takes 1000 USDC
     * - User receives 1000 aUSDC (interest-bearing)
     * - Over time, aUSDC balance grows as borrowers pay interest
     */
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external nonReentrant whenNotPaused {
        // TODO: Implement
    }
    
    /**
     * ╔═══════════════════════════════════════════════════════════╗
     * ║                      WITHDRAW                              ║
     * ╠═══════════════════════════════════════════════════════════╣
     * ║ User burns aToken → receives ERC20 back + earned interest  ║
     * ╚═══════════════════════════════════════════════════════════╝
     * 
     * TODO: Implement withdraw logic:
     * 
     * 1. VALIDATE INPUTS:
     *    - if (amount == 0) revert LendingPool_AmountZero()
     *    - if (!reserves[asset].isActive) revert LendingPool_ReserveNotActive()
     * 
     * 2. UPDATE INTEREST INDEXES:
     *    - Call _updateState(asset) to accrue interest first
     * 
     * 3. GET USER'S aToken BALANCE:
     *    - uint256 userBalance = IAToken(reserves[asset].aToken).balanceOf(msg.sender)
     *    - uint256 amountToWithdraw = (amount == type(uint256).max) ? userBalance : amount
     *    - if (amountToWithdraw > userBalance) revert LendingPool_InsufficientBalance()
     * 
     * 4. CHECK AVAILABLE LIQUIDITY:
     *    - if (amountToWithdraw > reserves[asset].availableLiquidity)
     *        revert - not enough liquidity in pool (all lent out)
     * 
     * 5. BURN aTokens:
     *    - IAToken(reserves[asset].aToken).burn(msg.sender, amountToWithdraw)
     * 
     * 6. UPDATE RESERVE STATE:
     *    - reserves[asset].totalLiquidity -= amountToWithdraw
     *    - reserves[asset].availableLiquidity -= amountToWithdraw
     * 
     * 7. CHECK HEALTH FACTOR (if user has debt):
     *    - uint256 healthFactor = _calculateHealthFactor(msg.sender)
     *    - if (healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD)
     *        revert LendingPool_HealthFactorTooLow()
     *    - Withdrawal might make user undercollateralized!
     * 
     * 8. TRANSFER TOKENS TO USER:
     *    - IERC20(asset).transfer(to, amountToWithdraw)
     * 
     * 9. UPDATE COLLATERAL BITMAP (if withdrew all):
     *    - If user's aToken balance is now 0, remove from collateral bitmap
     *    - emit ReserveUsedAsCollateralDisabled(asset, msg.sender)
     * 
     * 10. EMIT EVENT:
     *     - emit Withdraw(msg.sender, asset, amountToWithdraw, to)
     * 
     * IMPORTANT: Health factor check prevents withdrawal that would
     * make user's position liquidatable!
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external nonReentrant returns (uint256) {
        // TODO: Implement
        return 0;
    }
    
    /**
     * ╔═══════════════════════════════════════════════════════════╗
     * ║                       BORROW                               ║
     * ╠═══════════════════════════════════════════════════════════╣
     * ║ User borrows against collateral → receives debt tokens     ║
     * ╚═══════════════════════════════════════════════════════════╝
     * 
     * TODO: Implement borrow logic:
     * 
     * 1. VALIDATE INPUTS:
     *    - if (amount == 0) revert LendingPool_AmountZero()
     *    - if (!reserves[asset].isActive) revert LendingPool_ReserveNotActive()
     *    - if (!reserves[asset].borrowingEnabled) revert
     *    - if (interestRateMode == 1 && !reserves[asset].stableBorrowEnabled) revert
     *    - if (interestRateMode != 1 && interestRateMode != 2) revert LendingPool_InvalidRateMode()
     * 
     * 2. CHECK BORROW CAP:
     *    - uint256 borrowCap = reserves[asset].borrowCap
     *    - if (borrowCap > 0) {
     *        uint256 totalDebt = reserves[asset].totalStableDebt + reserves[asset].totalVariableDebt
     *        if (totalDebt + amount > borrowCap) revert LendingPool_BorrowCapExceeded()
     *      }
     * 
     * 3. CHECK CREDIT DELEGATION (if borrowing for someone else):
     *    - if (onBehalfOf != msg.sender) {
     *        uint256 allowance = borrowAllowance[onBehalfOf][msg.sender][asset]
     *        if (allowance < amount) revert LendingPool_InsufficientCreditDelegation()
     *        borrowAllowance[onBehalfOf][msg.sender][asset] -= amount
     *      }
     * 
     * 4. UPDATE INTEREST INDEXES:
     *    - Call _updateState(asset)
     * 
     * 5. CHECK BORROWING POWER:
     *    - (uint256 totalCollateralUSD, uint256 totalDebtUSD, uint256 availableBorrowUSD, 
     *       uint256 currentLtv, uint256 healthFactor) = _getUserAccountData(onBehalfOf)
     *    - uint256 amountUSD = _getAssetPrice(asset) * amount / 1e18
     *    - if (amountUSD > availableBorrowUSD) revert LendingPool_ExceedsBorrowLimit()
     * 
     * 6. CHECK AVAILABLE LIQUIDITY:
     *    - if (amount > reserves[asset].availableLiquidity) revert
     * 
     * 7. MINT DEBT TOKENS:
     *    - if (interestRateMode == 1) {
     *        // Stable rate - pass current stable rate
     *        uint256 stableRate = reserves[asset].currentStableBorrowRate
     *        IStableDebtToken(reserves[asset].stableDebtToken).mint(onBehalfOf, amount, stableRate)
     *      } else {
     *        // Variable rate
     *        IVariableDebtToken(reserves[asset].variableDebtToken).mint(onBehalfOf, amount)
     *      }
     * 
     * 8. UPDATE RESERVE STATE:
     *    - reserves[asset].availableLiquidity -= amount
     *    - if (interestRateMode == 1) {
     *        reserves[asset].totalStableDebt += amount
     *      } else {
     *        reserves[asset].totalVariableDebt += amount
     *      }
     * 
     * 9. TRANSFER TOKENS TO BORROWER:
     *    - IERC20(asset).transfer(msg.sender, amount)
     *    - Note: tokens go to msg.sender, debt goes to onBehalfOf
     * 
     * 10. FINAL HEALTH FACTOR CHECK:
     *     - if (_calculateHealthFactor(onBehalfOf) < HEALTH_FACTOR_LIQUIDATION_THRESHOLD)
     *         revert LendingPool_HealthFactorTooLow()
     * 
     * 11. UPDATE INTEREST RATES:
     *     - _updateInterestRates(asset)
     *     - Utilization changed, so rates change
     * 
     * 12. EMIT EVENT:
     *     - emit Borrow(msg.sender, asset, amount, interestRateMode, borrowRate)
     */
    function borrow(
        address asset,
        uint256 amount,
        uint8 interestRateMode, // 1 = stable, 2 = variable
        address onBehalfOf
    ) external nonReentrant whenNotPaused {
        // TODO: Implement
    }
    
    /**
     * ╔═══════════════════════════════════════════════════════════╗
     * ║                        REPAY                               ║
     * ╠═══════════════════════════════════════════════════════════╣
     * ║ User repays debt → burns debt tokens → reduces liability   ║
     * ╚═══════════════════════════════════════════════════════════╝
     * 
     * TODO: Implement repay logic:
     * 
     * 1. VALIDATE INPUTS:
     *    - if (amount == 0) revert LendingPool_AmountZero()
     *    - if (!reserves[asset].isActive) revert LendingPool_ReserveNotActive()
     *    - if (interestRateMode != 1 && interestRateMode != 2) revert LendingPool_InvalidRateMode()
     * 
     * 2. UPDATE INTEREST INDEXES:
     *    - Call _updateState(asset)
     * 
     * 3. GET USER'S DEBT:
     *    - uint256 currentDebt
     *    - if (interestRateMode == 1) {
     *        currentDebt = IStableDebtToken(reserves[asset].stableDebtToken).balanceOf(onBehalfOf)
     *      } else {
     *        currentDebt = IVariableDebtToken(reserves[asset].variableDebtToken).balanceOf(onBehalfOf)
     *      }
     *    - if (currentDebt == 0) revert LendingPool_NoDebtToRepay()
     * 
     * 4. CALCULATE REPAY AMOUNT:
     *    - uint256 paybackAmount = (amount == type(uint256).max) ? currentDebt : amount
     *    - if (paybackAmount > currentDebt) paybackAmount = currentDebt
     *    - Can repay full debt by passing type(uint256).max
     * 
     * 5. TRANSFER TOKENS FROM REPAYER:
     *    - IERC20(asset).transferFrom(msg.sender, address(this), paybackAmount)
     *    - Anyone can repay anyone's debt (useful for liquidations)
     * 
     * 6. BURN DEBT TOKENS:
     *    - if (interestRateMode == 1) {
     *        IStableDebtToken(reserves[asset].stableDebtToken).burn(onBehalfOf, paybackAmount)
     *      } else {
     *        IVariableDebtToken(reserves[asset].variableDebtToken).burn(onBehalfOf, paybackAmount)
     *      }
     * 
     * 7. UPDATE RESERVE STATE:
     *    - reserves[asset].availableLiquidity += paybackAmount
     *    - if (interestRateMode == 1) {
     *        reserves[asset].totalStableDebt -= paybackAmount
     *      } else {
     *        reserves[asset].totalVariableDebt -= paybackAmount
     *      }
     * 
     * 8. UPDATE INTEREST RATES:
     *    - _updateInterestRates(asset)
     * 
     * 9. EMIT EVENT:
     *    - emit Repay(onBehalfOf, asset, paybackAmount, msg.sender)
     * 
     * 10. RETURN ACTUAL AMOUNT REPAID:
     *     - return paybackAmount
     */
    function repay(
        address asset,
        uint256 amount,
        uint8 interestRateMode,
        address onBehalfOf
    ) external nonReentrant returns (uint256) {
        // TODO: Implement
        return 0;
    }
    
    // ============================================================
    // ==================== LIQUIDATION ===========================
    // ============================================================
    
    /**
     * ╔═══════════════════════════════════════════════════════════╗
     * ║                   LIQUIDATION CALL                         ║
     * ╠═══════════════════════════════════════════════════════════╣
     * ║ Liquidator repays debt → receives collateral at discount   ║
     * ╚═══════════════════════════════════════════════════════════╝
     * 
     * TODO: Implement liquidation logic:
     * 
     * 1. VALIDATE HEALTH FACTOR:
     *    - uint256 healthFactor = _calculateHealthFactor(user)
     *    - if (healthFactor >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD)
     *        revert LendingPool_HealthFactorOk()
     *    - Can only liquidate unhealthy positions!
     * 
     * 2. VALIDATE INPUTS:
     *    - if (debtToCover == 0) revert LendingPool_AmountZero()
     *    - if (!reserves[collateralAsset].isActive) revert
     *    - if (!reserves[debtAsset].isActive) revert
     * 
     * 3. GET USER'S DEBT:
     *    - uint256 userDebt = IVariableDebtToken(...).balanceOf(user) 
     *                       + IStableDebtToken(...).balanceOf(user)
     *    - Can liquidate up to 50% of debt (close factor)
     *    - uint256 maxLiquidatable = userDebt / 2
     *    - uint256 actualDebtToCover = min(debtToCover, maxLiquidatable)
     * 
     * 4. CALCULATE COLLATERAL TO SEIZE:
     *    - Get prices from oracle:
     *      uint256 debtPrice = priceOracle.getAssetPrice(debtAsset)
     *      uint256 collateralPrice = priceOracle.getAssetPrice(collateralAsset)
     *    - Calculate collateral value:
     *      uint256 debtValueUSD = actualDebtToCover * debtPrice / 1e18
     *    - Apply liquidation bonus:
     *      uint256 bonus = reserves[collateralAsset].liquidationBonus // e.g., 10500 = 105%
     *      uint256 collateralToSeize = (debtValueUSD * bonus) / (collateralPrice * 10000)
     * 
     * 5. CHECK USER HAS ENOUGH COLLATERAL:
     *    - uint256 userCollateral = IAToken(reserves[collateralAsset].aToken).balanceOf(user)
     *    - if (collateralToSeize > userCollateral) {
     *        // Partial liquidation - seize all available
     *        collateralToSeize = userCollateral
     *        // Recalculate debt to cover
     *        actualDebtToCover = (collateralToSeize * collateralPrice * 10000) / (debtPrice * bonus)
     *      }
     * 
     * 6. REPAY DEBT ON BEHALF OF USER:
     *    - Transfer debt asset from liquidator:
     *      IERC20(debtAsset).transferFrom(msg.sender, address(this), actualDebtToCover)
     *    - Burn user's debt tokens (try variable first, then stable)
     * 
     * 7. TRANSFER COLLATERAL TO LIQUIDATOR:
     *    - if (receiveAToken) {
     *        // Liquidator receives aTokens (still earns interest)
     *        // Transfer aToken from user to liquidator
     *      } else {
     *        // Liquidator receives underlying asset
     *        IAToken(reserves[collateralAsset].aToken).burn(user, collateralToSeize)
     *        IERC20(collateralAsset).transfer(msg.sender, collateralToSeize)
     *      }
     * 
     * 8. UPDATE RESERVE STATES:
     *    - Update liquidity, debt tracking for both assets
     * 
     * 9. UPDATE INTEREST RATES:
     *    - _updateInterestRates(collateralAsset)
     *    - _updateInterestRates(debtAsset)
     * 
     * 10. EMIT EVENT:
     *     - emit LiquidationCall(collateralAsset, debtAsset, user, actualDebtToCover, collateralToSeize, msg.sender)
     * 
     * LIQUIDATION EXAMPLE:
     * - User has $1000 ETH collateral, $900 USDC debt
     * - Health factor = ($1000 * 0.85) / $900 = 0.94 (< 1.0, liquidatable!)
     * - Liquidator covers $450 debt (50%)
     * - Receives: ($450 * 1.05) = $472.50 worth of ETH
     * - Liquidator profit: $22.50
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external nonReentrant {
        // TODO: Implement
    }
    
    // ============================================================
    // ==================== FLASH LOANS ===========================
    // ============================================================
    
    /**
     * ╔═══════════════════════════════════════════════════════════╗
     * ║                      FLASH LOAN                            ║
     * ╠═══════════════════════════════════════════════════════════╣
     * ║ Borrow without collateral - MUST repay in same transaction ║
     * ╚═══════════════════════════════════════════════════════════╝
     * 
     * TODO: Implement flash loan logic:
     * 
     * 1. VALIDATE INPUTS:
     *    - assets.length == amounts.length
     *    - All assets are active and not paused
     *    - amounts > 0
     * 
     * 2. CALCULATE PREMIUMS:
     *    - for each asset:
     *      premiums[i] = (amounts[i] * flashLoanPremiumTotal) / FEE_DENOMINATOR
     *    - Example: 10000 USDC * 9 / 10000 = 9 USDC fee
     * 
     * 3. CHECK AVAILABLE LIQUIDITY:
     *    - for each asset:
     *      if (amounts[i] > reserves[assets[i]].availableLiquidity) revert
     * 
     * 4. TRANSFER ASSETS TO RECEIVER:
     *    - for each asset:
     *      IERC20(assets[i]).transfer(receiverAddress, amounts[i])
     * 
     * 5. EXECUTE RECEIVER'S LOGIC:
     *    - bool success = IFlashLoanReceiver(receiverAddress).executeOperation(
     *        assets, amounts, premiums, msg.sender, params
     *      )
     *    - if (!success) revert LendingPool_FlashLoanFailed()
     *    - Receiver does arbitrage, liquidation, etc.
     * 
     * 6. VERIFY REPAYMENT (in same tx!):
     *    - for each asset:
     *      uint256 amountOwed = amounts[i] + premiums[i]
     *      uint256 balanceAfter = IERC20(assets[i]).balanceOf(address(this))
     *      uint256 balanceBefore = reserves[assets[i]].availableLiquidity
     *      if (balanceAfter < balanceBefore + amountOwed) revert
     *    - Receiver must have transferred back amount + premium
     * 
     * 7. UPDATE RESERVE STATE:
     *    - for each asset:
     *      reserves[assets[i]].availableLiquidity += premiums[i]
     *      reserves[assets[i]].totalLiquidity += premiums[i]
     *    - Premiums go to liquidity providers
     * 
     * 8. PROTOCOL FEE (optional):
     *    - uint256 protocolFee = (premiums[i] * flashLoanPremiumToProtocol) / flashLoanPremiumTotal
     *    - Transfer protocolFee to treasury
     * 
     * 9. EMIT EVENTS:
     *    - for each asset:
     *      emit FlashLoan(receiverAddress, msg.sender, assets[i], amounts[i], premiums[i])
     * 
     * FLASH LOAN EXAMPLE:
     * 1. Arbitrageur sees price difference between Uniswap and Sushiswap
     * 2. Calls flashLoan(USDC, 1000000) - borrows 1M USDC
     * 3. Buys ETH cheap on Uniswap, sells expensive on Sushiswap
     * 4. Repays 1000000 + 900 USDC (0.09% fee)
     * 5. Keeps profit (maybe $500 after gas)
     * All in ONE transaction! If any step fails, entire tx reverts.
     */
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        bytes calldata params
    ) external nonReentrant {
        // TODO: Implement
    }
    
    /**
     * Simple flash loan for single asset
     * Same as flashLoan but simpler interface
     */
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        // TODO: Implement - just call flashLoan with single-element arrays
    }
    
    // ============================================================
    // ==================== E-MODE ================================
    // ============================================================
    
    /**
     * ╔═══════════════════════════════════════════════════════════╗
     * ║                  SET USER E-MODE                           ║
     * ╠═══════════════════════════════════════════════════════════╣
     * ║ Enable efficiency mode for higher LTV on correlated assets ║
     * ╚═══════════════════════════════════════════════════════════╝
     * 
     * TODO: Implement E-Mode setting:
     * 
     * 1. VALIDATE CATEGORY EXISTS:
     *    - if (categoryId != 0 && bytes(eModeCategories[categoryId].label).length == 0)
     *        revert - category doesn't exist
     * 
     * 2. CHECK USER CAN SWITCH:
     *    - If user has debt, all debt must be in E-Mode compatible assets
     *    - If user has collateral being used, all must be E-Mode compatible
     *    - Check each asset user is using matches the category's eModeCategoryId
     * 
     * 3. UPDATE USER CONFIGURATION:
     *    - userConfiguration[msg.sender].eModeCategoryId = categoryId
     * 
     * 4. CHECK HEALTH FACTOR (mode change might affect it):
     *    - if (_calculateHealthFactor(msg.sender) < HEALTH_FACTOR_LIQUIDATION_THRESHOLD)
     *        revert LendingPool_HealthFactorTooLow()
     * 
     * 5. EMIT EVENT:
     *    - emit EModeSet(msg.sender, categoryId)
     * 
     * E-MODE EXAMPLE:
     * - Normal: ETH LTV = 80%, can borrow $800 per $1000 ETH
     * - E-Mode "ETH Correlated" (stETH, rETH, cbETH): LTV = 97%
     * - Same $1000 stETH → can borrow $970!
     * - Higher capital efficiency for correlated assets
     */
    function setUserEMode(uint8 categoryId) external nonReentrant {
        // TODO: Implement
    }
    
    // ============================================================
    // ==================== CREDIT DELEGATION =====================
    // ============================================================
    
    /**
     * ╔═══════════════════════════════════════════════════════════╗
     * ║              APPROVE BORROW ALLOWANCE                      ║
     * ╠═══════════════════════════════════════════════════════════╣
     * ║ Allow another address to borrow using your collateral      ║
     * ╚═══════════════════════════════════════════════════════════╝
     * 
     * TODO: Implement credit delegation:
     * 
     * 1. SET ALLOWANCE:
     *    - borrowAllowance[msg.sender][delegatee][asset] = amount
     *    - msg.sender = the one with collateral (delegator)
     *    - delegatee = the one who can borrow
     *    - asset = which asset they can borrow
     *    - amount = max they can borrow
     * 
     * 2. EMIT EVENT:
     *    - emit BorrowAllowanceDelegated(msg.sender, delegatee, asset, amount)
     * 
     * CREDIT DELEGATION EXAMPLE:
     * - Alice has $10000 USDC deposited
     * - Alice trusts Bob, calls approveDelegation(Bob, USDC, 5000)
     * - Bob can now borrow up to 5000 USDC using Alice's collateral
     * - Bob pays interest, Alice earns deposit interest
     * - If Bob doesn't repay, Alice's collateral gets liquidated!
     * - Use case: Uncollateralized loans based on trust/reputation
     */
    function approveDelegation(
        address delegatee,
        address asset,
        uint256 amount
    ) external {
        // TODO: Implement
    }
    
    /**
     * Get current delegation allowance
     */
    function borrowAllowanceOf(
        address fromUser,
        address toUser,
        address asset
    ) external view returns (uint256) {
        return borrowAllowance[fromUser][toUser][asset];
    }
    
    // ============================================================
    // ==================== COLLATERAL MANAGEMENT =================
    // ============================================================
    
    /**
     * ╔═══════════════════════════════════════════════════════════╗
     * ║          SET USER USE RESERVE AS COLLATERAL                ║
     * ╠═══════════════════════════════════════════════════════════╣
     * ║ Toggle whether a deposited asset is used as collateral     ║
     * ╚═══════════════════════════════════════════════════════════╝
     * 
     * TODO: Implement collateral toggle:
     * 
     * 1. VALIDATE:
     *    - User must have non-zero balance in this asset
     *    - Reserve must be active
     * 
     * 2. IF DISABLING COLLATERAL:
     *    - Check health factor stays above threshold
     *    - User might not be able to disable if they have debt!
     * 
     * 3. UPDATE USER CONFIGURATION:
     *    - Update userConfiguration[msg.sender].collateralBitmap
     *    - Add or remove the reserve's bit
     * 
     * 4. EMIT EVENT:
     *    - if (useAsCollateral) emit ReserveUsedAsCollateralEnabled
     *    - else emit ReserveUsedAsCollateralDisabled
     * 
     * WHY TOGGLE OFF?
     * - Some assets can't be liquidated (e.g., governance tokens)
     * - User might want to hold an asset without using as collateral
     * - Reduces exposure in case of oracle manipulation
     */
    function setUserUseReserveAsCollateral(
        address asset,
        bool useAsCollateral
    ) external nonReentrant {
        // TODO: Implement
    }
    
    // ============================================================
    // ==================== SWAP RATE MODE ========================
    // ============================================================
    
    /**
     * ╔═══════════════════════════════════════════════════════════╗
     * ║                   SWAP BORROW RATE MODE                    ║
     * ╠═══════════════════════════════════════════════════════════╣
     * ║ Switch between stable and variable rate on existing debt   ║
     * ╚═══════════════════════════════════════════════════════════╝
     * 
     * TODO: Implement rate swap:
     * 
     * 1. GET CURRENT DEBT IN CURRENT MODE:
     *    - Get user's debt in the mode they want to switch FROM
     *    - Must have non-zero debt
     * 
     * 2. BURN OLD DEBT TOKENS:
     *    - Burn from old rate mode's debt token
     * 
     * 3. MINT NEW DEBT TOKENS:
     *    - Mint to new rate mode's debt token
     *    - If switching to stable, use current stable rate
     * 
     * 4. UPDATE RESERVE STATE:
     *    - Move amount from one debt tracker to other
     * 
     * 5. CHECK HEALTH FACTOR:
     *    - Rate change might affect health calculation
     * 
     * 6. EMIT EVENT
     * 
     * EXAMPLE:
     * - User has $1000 variable debt at 5%
     * - Expects rates to rise, calls swapBorrowRateMode(USDC, 2)
     * - Now has $1000 stable debt at 6% (locked in!)
     * - Even if variable goes to 10%, user still pays 6%
     */
    function swapBorrowRateMode(
        address asset,
        uint8 currentRateMode
    ) external nonReentrant {
        // TODO: Implement
    }
    
    // ============================================================
    // ==================== VIEW FUNCTIONS ========================
    // ============================================================
    
    /**
     * Get all user account data in one call
     * 
     * TODO: Implement comprehensive user data aggregation:
     * 
     * 1. ITERATE THROUGH ALL RESERVES:
     *    - for each reserve in reservesList:
     *      - Get user's aToken balance (collateral)
     *      - Get user's variable debt token balance
     *      - Get user's stable debt token balance
     *      - Get asset price from oracle
     *      - Apply LTV weights for collateral power
     * 
     * 2. CALCULATE TOTALS:
     *    - totalCollateralUSD = sum of (balance * price * LTV / 10000)
     *    - totalDebtUSD = sum of (debt * price)
     * 
     * 3. APPLY E-MODE (if active):
     *    - If user in E-Mode, use E-Mode LTV/thresholds
     * 
     * 4. CALCULATE DERIVED VALUES:
     *    - availableBorrowsUSD = totalCollateralUSD - totalDebtUSD
     *    - currentLTV = (totalDebtUSD * 10000) / totalCollateralUSD
     *    - healthFactor = (totalCollateralUSD * avgLiquidationThreshold) / totalDebtUSD
     * 
     * RETURN: (totalCollateral, totalDebt, availableBorrows, currentLTV, healthFactor)
     */
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralUSD,
            uint256 totalDebtUSD,
            uint256 availableBorrowsUSD,
            uint256 currentLTV,
            uint256 healthFactor
        )
    {
        // TODO: Implement
        return (0, 0, 0, 0, 0);
    }
    
    /**
     * Get reserve data
     */
    function getReserveData(address asset) 
        external 
        view 
        returns (ReserveData memory) 
    {
        return reserves[asset];
    }
    
    /**
     * Get all reserves list
     */
    function getReservesList() external view returns (address[] memory) {
        return reservesList;
    }
    
    /**
     * Get user's E-Mode category
     */
    function getUserEMode(address user) external view returns (uint8) {
        return userConfiguration[user].eModeCategoryId;
    }
    
    // ============================================================
    // ==================== INTERNAL FUNCTIONS ====================
    // ============================================================
    
    /**
     * Update reserve state (accrue interest)
     * 
     * TODO: Implement interest accrual:
     * 
     * 1. CALCULATE TIME ELAPSED:
     *    - uint256 timeElapsed = block.timestamp - reserves[asset].lastUpdateTimestamp
     *    - if (timeElapsed == 0) return - already up to date
     * 
     * 2. GET CURRENT RATES FROM STRATEGY:
     *    - Calculate utilization: totalDebt / totalLiquidity
     *    - Call interestRateStrategy.calculateInterestRates()
     * 
     * 3. UPDATE INDEXES:
     *    - Compound interest since last update
     *    - liquidityIndex *= (1 + liquidityRate * timeElapsed / SECONDS_PER_YEAR)
     *    - variableBorrowIndex *= (1 + variableBorrowRate * timeElapsed / SECONDS_PER_YEAR)
     * 
     * 4. UPDATE TIMESTAMPS:
     *    - reserves[asset].lastUpdateTimestamp = block.timestamp
     * 
     * 5. UPDATE TOKEN INDEXES:
     *    - IAToken(aToken).updateLiquidityIndex(newLiquidityIndex)
     *    - IVariableDebtToken(variableDebtToken).updateBorrowIndex(newVariableBorrowIndex)
     */
    function _updateState(address asset) internal {
        // TODO: Implement
    }
    
    /**
     * Update interest rates based on current utilization
     * 
     * TODO: Implement rate update:
     * 
     * 1. CALCULATE UTILIZATION:
     *    - totalDebt = reserves[asset].totalStableDebt + reserves[asset].totalVariableDebt
     *    - utilization = totalDebt / reserves[asset].totalLiquidity
     * 
     * 2. GET NEW RATES FROM STRATEGY:
     *    - (liquidityRate, variableRate, stableRate) = 
     *        IInterestRateStrategy(...).calculateInterestRates(...)
     * 
     * 3. UPDATE RESERVE:
     *    - reserves[asset].currentLiquidityRate = liquidityRate
     *    - reserves[asset].currentVariableBorrowRate = variableRate
     *    - reserves[asset].currentStableBorrowRate = stableRate
     * 
     * 4. EMIT EVENT:
     *    - emit ReserveDataUpdated(...)
     */
    function _updateInterestRates(address asset) internal {
        // TODO: Implement
    }
    
    /**
     * Calculate user's health factor
     * 
     * TODO: Implement health factor calculation:
     * 
     * FORMULA:
     * healthFactor = (totalCollateralUSD * avgLiquidationThreshold) / totalDebtUSD
     * 
     * - If > 1.0: healthy
     * - If < 1.0: liquidatable
     * - If debt = 0: return max uint256 (infinitely healthy)
     * 
     * STEPS:
     * 1. Get all user's collateral positions (aToken balances)
     * 2. Get all user's debt positions (debt token balances)
     * 3. Convert to USD using oracle
     * 4. Weight collateral by liquidation threshold (not LTV!)
     * 5. Apply E-Mode if active
     */
    function _calculateHealthFactor(address user) internal view returns (uint256) {
        // TODO: Implement
        return type(uint256).max;
    }
    
    /**
     * Get asset price from oracle
     */
    function _getAssetPrice(address asset) internal view returns (uint256) {
        return priceOracle.getAssetPrice(asset);
    }
    
    // ============================================================
    // ==================== ADMIN FUNCTIONS =======================
    // ============================================================
    
    /**
     * Initialize a new reserve (add new asset to protocol)
     */
    function initReserve(
        address asset,
        address aToken,
        address stableDebtToken,
        address variableDebtToken,
        address interestRateStrategy
    ) external onlyRole(ADMIN_ROLE) {
        // TODO: Implement - create ReserveData struct
    }
    
    /**
     * Set reserve configuration parameters
     */
    function setReserveConfiguration(
        address asset,
        uint16 ltv,
        uint16 liquidationThreshold,
        uint16 liquidationBonus,
        uint16 reserveFactor,
        uint256 supplyCap,
        uint256 borrowCap,
        bool borrowingEnabled,
        bool stableBorrowEnabled
    ) external onlyRole(RISK_MANAGER_ROLE) {
        // TODO: Implement
    }
    
    /**
     * Configure E-Mode category
     */
    function configureEModeCategory(
        uint8 categoryId,
        uint16 ltv,
        uint16 liquidationThreshold,
        uint16 liquidationBonus,
        address priceSource,
        string calldata label
    ) external onlyRole(RISK_MANAGER_ROLE) {
        // TODO: Implement
    }
    
    /**
     * Set asset E-Mode category
     */
    function setAssetEModeCategory(
        address asset,
        uint8 categoryId
    ) external onlyRole(RISK_MANAGER_ROLE) {
        // TODO: Implement
    }
    
    /**
     * Pause/unpause a specific reserve
     */
    function setReservePause(address asset, bool paused) external onlyRole(EMERGENCY_ADMIN_ROLE) {
        reserves[asset].isPaused = paused;
    }
    
    /**
     * Freeze/unfreeze a reserve (no new deposits/borrows)
     */
    function setReserveFreeze(address asset, bool frozen) external onlyRole(RISK_MANAGER_ROLE) {
        reserves[asset].isFrozen = frozen;
    }
    
    /**
     * Set flash loan premium
     */
    function setFlashLoanPremium(uint256 premium, uint256 protocolPremium) external onlyRole(ADMIN_ROLE) {
        flashLoanPremiumTotal = premium;
        flashLoanPremiumToProtocol = protocolPremium;
    }
    
    /**
     * Set price oracle
     */
    function setPriceOracle(address oracle) external onlyRole(ADMIN_ROLE) {
        priceOracle = IPriceOracle(oracle);
    }
    
    /**
     * Global pause (emergency)
     */
    function pause() external onlyRole(EMERGENCY_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(EMERGENCY_ADMIN_ROLE) {
        _unpause();
    }
}
