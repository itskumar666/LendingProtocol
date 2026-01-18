// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title StableDebtToken
 * @notice Represents stable-rate debt
 * 
 * QUICK POINTERS:
 * - Interest rate is FIXED at borrow time
 * - User locks in rate (e.g., 5% APY)
 * - Rate never changes, regardless of market conditions
 * - Good for planning (predictable costs)
 * - Bad if rates drop (you pay more than market)
 * - Also non-transferable like variable debt
 */

contract StableDebtToken is ERC20, AccessControl {
    
    error StableDebtToken_RateTooHigh();
    error StableDebtToken_MintingAmountTooLow();
    error StableDebtToken_RepayAmountTooHigh();
    error StableDebtToken_NoDebtFound();
    error StableDebtToken_TransferNotAllowed();
    
    bytes32 public constant LENDER_ROLE = keccak256("LENDER_ROLE");
    
    address public lendingPool;
    
    struct Debt {
        uint128 amount;           // Principal borrowed
        uint128 rate;             // APY at borrowing (5e2 = 5%)
        uint256 timestamp;        // When borrowed
    }
    
    // ARRAY BASED: Each user can have MULTIPLE debts at different rates
    // Example: User borrows 100 USDC at 5%, then 50 USDC at 6%
    // userDebts[user][0] = Debt(100, 5e2, timestamp1)
    // userDebts[user][1] = Debt(50, 6e2, timestamp2)
    mapping(address => Debt[]) public userDebts;
    
    event DebtMinted(address indexed user, uint256 indexed amount, uint256 indexed rate);
    event DebtBurned(address indexed user, uint256 indexed amount);
    
    constructor(
        address _lendingPool,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        lendingPool = _lendingPool;
        _grantRole(LENDER_ROLE, _lendingPool);
    }
    
    /**
     * Mint stable debt token with fixed rate
     * 
     * ARRAY-BASED approach:
     * 1. Validate inputs
     * 2. Create Debt struct
     * 3. Append to array (NOT overwrite!)
     * 4. Emit event
     * 
     * EXAMPLE (Real Protocol Behavior):
     * Time 1: Borrow 100 USDC at 5%
     *   → userDebts[user] = [Debt(100, 5e2, now)]
     * Time 2: Borrow 50 USDC at 6%
     *   → userDebts[user] = [Debt(100, 5e2, time1), Debt(50, 6e2, now)]
     */
    function mint(
        address user,
        uint256 amount,
        uint256 rate
    ) external onlyRole(LENDER_ROLE) {
        // Validate inputs
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Amount must be > 0");
        require(rate >= 1000e2, "Rate too high (max 1000%)");
        
        // Create Debt struct and append to array
        Debt memory newDebt = Debt({
            amount: uint128(amount),
            rate: uint128(rate),
            timestamp: block.timestamp
        });
        
        userDebts[user].push(newDebt);
        
        // Emit Transfer event (NOT calling _mint!)
        // We track debt in our array, just emit event for visibility
        emit Transfer(address(0), user, amount);
        
        // Emit custom event
        emit DebtMinted(user, amount, rate);
    }
    
    /**
     * Get user's total debt with accrued interest
     * 
     * Uses SIMPLE INTEREST formula (not compound):
     * interest = (principal × rate × timeElapsed) / (seconds_per_year × 100e2)
     * 
     * REAL EXAMPLE:
     * - Debt 1: amount=100, rate=5e2, borrowed 365 days ago → 100 + 5 = 105
     * - Debt 2: amount=50, rate=6e2, borrowed 180 days ago → 50 + 1.5 = 51.5
     * - Total returned: 156.5
     */
    function getDebtWithInterest(address user) public view returns (uint256) {
        Debt[] storage userDebtArray = userDebts[user];
        uint256 totalDebt = 0;
        
        // Iterate through all debts and sum with interest
        for (uint256 i = 0; i < userDebtArray.length; i++) {
            Debt storage debt = userDebtArray[i];
            
            // Skip zero amounts
            if (debt.amount == 0) continue;
            
            // Calculate time elapsed in seconds
            uint256 timeElapsed = block.timestamp - debt.timestamp;
            
            // Simple interest formula: (principal × rate × time) / (seconds_per_year × 100e2)
            // seconds_per_year = 365 × 86400 = 31,536,000
            uint256 interest = (uint256(debt.amount) * uint256(debt.rate) * timeElapsed) / (31536000 * 100e2);
            
            // Add principal + interest to total
            totalDebt += uint256(debt.amount) + interest;
        }
        
        return totalDebt;
    }
    
    /**
     * Burn (repay) stable debt from ARRAY
     * 
     * FIFO approach (First-In-First-Out):
     * Oldest debts repay first
     * 
     * REAL SCENARIO:
     * - Debt[0]: 100 at 5%
     * - Debt[1]: 50 at 6%
     * - User repays 120:
     *   → Debt[0] becomes 0 (fully paid 100)
     *   → Debt[1] becomes 30 (20 paid from this one)
     *   → Both rates locked in for remaining balance
     */
    function burn(address user, uint256 amount) external onlyRole(LENDER_ROLE) {
        require(amount > 0, "Repay amount must be > 0");
        
        Debt[] storage debts = userDebts[user];
        uint256 remainingAmount = amount;
        
        // FIFO: Iterate through debts, oldest first
        for (uint256 i = 0; i < debts.length && remainingAmount > 0; i++) {
            // Skip already paid-off debts
            if (debts[i].amount == 0) {
                continue;
            }
            
            if (debts[i].amount >= remainingAmount) {
                // Partial repay of this debt
                debts[i].amount -= uint128(remainingAmount);
                remainingAmount = 0;
            } else {
                // Fully repay this debt
                remainingAmount -= debts[i].amount;
                debts[i].amount = 0;
            }
        }
        
        // Revert if tried to repay more than owed
        require(remainingAmount == 0, "Repay amount exceeds debt");
        
        // Emit Transfer event (NOT calling _burn!)
        // We track debt in our array, just emit event for visibility
        emit Transfer(user, address(0), amount);
        
        // Emit custom event
        emit DebtBurned(user, amount);
    }
    
    /**
     * Get total balance (debt with interest) for an account
     * 
     * Simple delegation to getDebtWithInterest
     */
    function balanceOf(address account) public view override returns (uint256) {
        return getDebtWithInterest(account);
    }
    
    // Non-transferable debt tokens
    /**
     * Prevent stable debt token transfers
     * Debt cannot be traded or transferred like regular tokens
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert StableDebtToken_TransferNotAllowed();
    }
    
    /**
     * Prevent stable debt token transfers from others
     * Same as transfer() - debt is non-transferable
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert StableDebtToken_TransferNotAllowed();
    }
}
