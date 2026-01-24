// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title VariableDebtToken
 * @notice Represents variable-rate debt
 * 
 * QUICK POINTERS:
 * - Interest rate changes with utilization (supply/demand)
 * - User borrows 100 USDC at 5% APY
 * - 1 month later: owes 100.42 USDC (interest accrued)
 * - If utilization goes up → interest rate goes up → owes more
 * - Non-transferable (represents debt, not an asset)
 */

contract VariableDebtToken is ERC20, AccessControl {

    error VariableDebtToken_AmountLessThanZero();
    error VariableDebtToken_TransferNotAllowed();
    
    bytes32 public constant LENDER_ROLE = keccak256("LENDER_ROLE");
    
    address public lendingPool;
    uint256 public borrowIndex = 1e27; // Tracks accumulated interest
    
    mapping(address => uint256) private scaledBalances;
    uint256 private scaledTotalSupply;
    
    constructor(
        address _lendingPool,
        address _borrowLogic,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        lendingPool = _lendingPool;
        _grantRole(LENDER_ROLE, _lendingPool);
        _grantRole(LENDER_ROLE,_borrowLogic);
    }
    
    /**
     * Mint debt token (user borrows)
     * 
     * Converts actual amount to scaled amount for storage.
     * As borrowIndex grows, user's debt grows automatically.
     * 
     * @param user The address performing the borrow (receives borrowed asset)
     * @param onBehalfOf The address that will get the debt
     * @param amount The amount being borrowed
     * @param index The current variable borrow index
     * @return True if this is the user's first borrow
     * 
     * Example:
     * - borrowIndex = 1e27 (1.0), amount = 100
     * - scaledAmount = (100 * 1e27) / 1e27 = 100
     * - Later, borrowIndex = 1.05e27 (5% interest accrued)
     * - User's balance = (100 * 1.05e27) / 1e27 = 105 (owes more!)
     */
    function mint(
        address user,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) external onlyRole(LENDER_ROLE) returns (bool) {
        require(amount > 0, "Amount must be > 0");
        
        // Update borrow index if provided
        if (index != borrowIndex) {
            borrowIndex = index;
        }
        
        // Check if this is first borrow for onBehalfOf
        bool isFirstBorrow = scaledBalances[onBehalfOf] == 0;
        
        // Convert actual amount to scaled amount
        uint256 scaledAmount = (amount * 1e27) / borrowIndex;
        
        // Update our internal tracking for onBehalfOf (debt goes to them)
        scaledBalances[onBehalfOf] += scaledAmount;
        scaledTotalSupply += scaledAmount;
        
        // Emit Transfer event - debt is assigned to onBehalfOf
        emit Transfer(address(0), onBehalfOf, amount);
        
        return isFirstBorrow;
    }
    
    /**
     * Burn debt token (user repays)
     * 
     * Converts actual repay amount to scaled amount.
     * User repays actual debt (e.g., 105 USDC) but we track scaled internally.
     * 
     * @param from The address whose debt is being repaid
     * @param amount The amount being repaid
     * @param index The current variable borrow index
     * @return The new total supply after burn
     */
    function burn(
        address from,
        uint256 amount,
        uint256 index
    ) external onlyRole(LENDER_ROLE) returns (uint256) {
        require(amount > 0, "Amount must be > 0");
        
        // Update borrow index if provided
        if (index != borrowIndex) {
            borrowIndex = index;
        }
        
        // Convert actual amount to scaled amount
        uint256 scaledAmount = (amount * 1e27) / borrowIndex;
        
        // Validate user has enough debt
        require(scaledBalances[from] >= scaledAmount, "Insufficient debt balance");
        
        // Update our internal tracking
        scaledBalances[from] -= scaledAmount;
        scaledTotalSupply -= scaledAmount;
        
        // Emit Transfer event (NOT calling _burn!)
        // Emit ACTUAL amount repaid
        emit Transfer(from, address(0), amount);
        
        return totalSupply();
    }
    
    /**
     * Update borrow index with accrued interest
     * 
     * Called by LendingPool after calculating interest accrual.
     * All user balances automatically reflect the new debt amount.
     * 
     * Example: borrowIndex 1e27 → 1.05e27 = 5% interest accrued for all borrowers
     */
    function updateBorrowIndex(uint256 newIndex) external onlyRole(LENDER_ROLE) {
        require(newIndex >= borrowIndex, "Index cannot decrease");
        borrowIndex = newIndex;
    }
    
    /**
     * Get user's current debt with accrued interest
     * 
     * Automatic interest accrual - no state updates needed!
     * 
     * Example:
     * - User has scaledBalance = 95
     * - borrowIndex = 1.05e27 (5% interest)
     * - balanceOf = (95 * 1.05e27) / 1e27 = 99.75
     */
    function balanceOf(address account) public view override returns (uint256) {
        return (scaledBalances[account] * borrowIndex) / 1e27;
    }
    
    /**
     * Get total debt across all borrowers with accrued interest
     * 
     * Shows protocol's total outstanding debt automatically.
     */
    function totalSupply() public view override returns (uint256) {
        return (scaledTotalSupply * borrowIndex) / 1e27;
    }
    
    // Non-transferable debt tokens
    /**
     * Prevent debt token transfers
     * Debt is a liability, not an asset - cannot be traded
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert VariableDebtToken_TransferNotAllowed();
    }
    
    /**
     * Prevent debt token transfers from others
     * Same as transfer() - debt is non-transferable
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert VariableDebtToken_TransferNotAllowed();
    }    
    /**
     * Reject ETH sent to this contract
     * Debt tokens should not hold ETH
     */
    receive() external payable {
        revert("VariableDebtToken: cannot receive ETH");
    }
    
    /**
     * Reject any other calls
     */
    fallback() external payable {
        revert("VariableDebtToken: fallback not allowed");
    }}
