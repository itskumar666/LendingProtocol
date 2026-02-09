// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title Errors
 * @notice Contains all protocol error messages
 * Centralized errors for better organization and lower bytecode size
 */
library Errors {
    
    // ==================== COMMON ERRORS ====================
    string public constant CALLER_NOT_POOL_ADMIN = '1'; // The caller must be the pool admin
    string public constant CALLER_NOT_EMERGENCY_ADMIN = '2'; // The caller must be the emergency admin
    string public constant CALLER_NOT_POOL_OR_EMERGENCY_ADMIN = '3'; // The caller must be pool or emergency admin
    string public constant CALLER_NOT_RISK_OR_POOL_ADMIN = '4'; // The caller must be risk or pool admin
    string public constant CALLER_NOT_ASSET_LISTING_OR_POOL_ADMIN = '5'; // The caller must be asset listing or pool admin
    string public constant CALLER_NOT_BRIDGE = '6'; // The caller must be bridge
    string public constant ADDRESSES_PROVIDER_NOT_REGISTERED = '7'; // Pool addresses provider is not registered
    
    // ==================== MATH ERRORS ====================
    string public constant MATH_MULTIPLICATION_OVERFLOW = '8';
    string public constant MATH_ADDITION_OVERFLOW = '9';
    string public constant MATH_DIVISION_BY_ZERO = '10';
    
    // ==================== VALIDATION ERRORS ====================
    string public constant INVALID_AMOUNT = '11'; // Amount must be greater than 0
    string public constant RESERVE_INACTIVE = '12'; // Action requires an active reserve
    string public constant RESERVE_FROZEN = '13'; // Action cannot be performed because reserve is frozen
    string public constant RESERVE_PAUSED = '14'; // Action cannot be performed because reserve is paused
    string public constant BORROWING_NOT_ENABLED = '15'; // Borrowing is not enabled on this reserve
    string public constant STABLE_BORROWING_NOT_ENABLED = '16'; // Stable borrowing is not enabled
    string public constant NOT_ENOUGH_AVAILABLE_USER_BALANCE = '17'; // User cannot withdraw more than available balance
    string public constant INVALID_INTEREST_RATE_MODE_SELECTED = '18'; // Invalid interest rate mode selected
    
    // ==================== COLLATERAL/BORROW ERRORS ====================
    string public constant COLLATERAL_BALANCE_IS_ZERO = '19'; // Collateral balance is 0
    string public constant HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD = '20'; // Health factor is below liquidation threshold
    string public constant COLLATERAL_CANNOT_COVER_NEW_BORROW = '21'; // Not enough collateral to cover new borrow
    string public constant COLLATERAL_SAME_AS_BORROWING_CURRENCY = '22'; // Collateral is same as borrow currency
    string public constant AMOUNT_BIGGER_THAN_MAX_LOAN_SIZE_STABLE = '23'; // Amount exceeds max loan size in stable rate mode
    string public constant NO_DEBT_OF_SELECTED_TYPE = '24'; // User does not have debt of selected type
    string public constant NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF = '25'; // Must specify repay amount when repaying on behalf
    string public constant NO_OUTSTANDING_STABLE_DEBT = '26'; // User has no outstanding stable rate debt
    string public constant NO_OUTSTANDING_VARIABLE_DEBT = '27'; // User has no outstanding variable rate debt
    
    // ==================== LIQUIDATION ERRORS ====================
    string public constant HEALTH_FACTOR_NOT_BELOW_THRESHOLD = '28'; // Health factor is not below threshold, cannot liquidate
    string public constant COLLATERAL_CANNOT_BE_LIQUIDATED = '29'; // Collateral cannot be liquidated
    string public constant SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER = '30'; // User did not borrow specified currency
    string public constant INCONSISTENT_FLASHLOAN_PARAMS = '31'; // Inconsistent flashloan parameters
    string public constant BORROW_CAP_EXCEEDED = '32'; // Borrow cap exceeded
    string public constant SUPPLY_CAP_EXCEEDED = '33'; // Supply cap exceeded
    string public constant UNBACKED_MINT_CAP_EXCEEDED = '34'; // Unbacked mint cap exceeded
    string public constant DEBT_CEILING_EXCEEDED = '35'; // Debt ceiling exceeded
    
    // ==================== RESERVE ERRORS ====================
    string public constant RESERVE_ALREADY_INITIALIZED = '36'; // Reserve already initialized
    string public constant LTV_VALIDATION_FAILED = '37'; // LTV validation failed
    string public constant INCONSISTENT_EMODE_CATEGORY = '38'; // Inconsistent eMode category
    string public constant PRICE_ORACLE_SENTINEL_CHECK_FAILED = '39'; // Price oracle sentinel validation failed
    string public constant ASSET_NOT_BORROWABLE_IN_ISOLATION = '40'; // Asset not borrowable in isolation mode
    string public constant RESERVE_ALREADY_ADDED = '41'; // Reserve already added to reserve list
    string public constant MAX_NUMBER_RESERVES_REACHED = '42'; // Maximum number of reserves reached
    
    // ==================== E-MODE ERRORS ====================
    string public constant EMODE_CATEGORY_RESERVED = '43'; // Zero eMode category reserved for non-eMode
    string public constant INVALID_EMODE_CATEGORY_ASSIGNMENT = '44'; // Invalid eMode category assignment
    string public constant INVALID_EMODE_CATEGORY_PARAMS = '45'; // Invalid eMode category parameters
    
    // ==================== FLASHLOAN ERRORS ====================
    string public constant INCONSISTENT_FLASHLOAN_AMOUNTS = '46'; // Flashloan amount not repaid
    string public constant INSUFFICIENT_LIQUIDITY_TO_FLASHLOAN = '47'; // Not enough liquidity for flashloan
    
    // ==================== INTEREST RATE ERRORS ====================
    string public constant INVALID_INTEREST_RATE_STRATEGY = '48'; // Invalid interest rate strategy
    string public constant INVALID_OPTIMAL_USAGE_RATIO = '49'; // Optimal usage ratio must be < 100%
    string public constant INVALID_OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO = '50'; // Invalid optimal stable to total debt ratio
    
    // ==================== CREDIT DELEGATION ERRORS ====================
    string public constant NOT_ENOUGH_AVAILABLE_USER_BALANCE_FOR_WITHDRAWAL = '51'; // User balance insufficient for withdrawal
    string public constant INVALID_BURN_AMOUNT = '52'; // Invalid burn amount
    string public constant BORROW_ALLOWANCE_NOT_ENOUGH = '53'; // User does not have enough borrow allowance
    
    // ==================== SILOED BORROWING ERRORS ====================
    string public constant SILOED_BORROWING_VIOLATION = '54'; // Siloed borrowing violation
    string public constant RESERVE_DEBT_NOT_ZERO = '55'; // Reserve debt not zero
    
    // ==================== ISOLATION MODE ERRORS ====================
    string public constant ISOLATION_MODE_DEBT_CEILING_EXCEEDED = '56'; // Isolation mode debt ceiling exceeded
    string public constant ASSET_NOT_LISTED = '57'; // Asset is not listed
    string public constant INVALID_LTV = '58'; // Invalid LTV parameter
    string public constant INVALID_LIQ_THRESHOLD = '59'; // Invalid liquidation threshold parameter
    string public constant INVALID_LIQ_BONUS = '60'; // Invalid liquidation bonus parameter
    string public constant INVALID_DECIMALS = '61'; // Invalid decimals parameter
    string public constant INVALID_RESERVE_FACTOR = '62'; // Invalid reserve factor parameter
    
    // ==================== ACCESS CONTROL ERRORS ====================
    string public constant CALLER_NOT_ATOKEN = '63'; // The caller must be an AToken
    string public constant CALLER_NOT_STABLE_DEBT_TOKEN = '64'; // The caller must be stable debt token
    string public constant CALLER_NOT_VARIABLE_DEBT_TOKEN = '65'; // The caller must be variable debt token
    string public constant OPERATION_NOT_SUPPORTED = '66'; // Operation not supported
    
    // ==================== ORACLE ERRORS ====================
    string public constant INVALID_PRICE_SOURCE = '67'; // Invalid price source
    string public constant PRICE_ORACLE_NOT_SET = '68'; // Price oracle not set
    string public constant ORACLE_ERROR = '70'; // Oracle returned invalid price
    
    // ==================== CONFIGURATION ERRORS ====================
    string public constant INVALID_RESERVE_INDEX = '69'; // Reserve index exceeds maximum
    string public constant ZERO_ADDRESS_NOT_VALID = '71'; // Address cannot be zero
    string public constant NOT_ENOUGH_LIQUIDITY = '72'; // Not enough liquidity in reserve
    string public constant FLASHLOAN_DISABLED = '73'; // Flash loans are disabled for this reserve
    string public constant HEALTH_FACTOR_NOT_IMPROVED = '74'; // Health factor did not improve after action
    string public constant UNDERLYING_BALANCE_ZERO = '75'; // Underlying balance is zero
    string public constant INVALID_FLASHLOAN_EXECUTOR_RETURN = '76'; // Flash loan executor returned invalid value
}
