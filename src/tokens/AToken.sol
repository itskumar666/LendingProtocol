// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AToken
 * @notice Interest-bearing token representing deposits
 * 
 * QUICK POINTERS:
 * - 1 aToken grows in value as interest accrues
 * - User deposits 100 USDC → gets 100 aUSDC
 * - After time, 100 aUSDC = 105 USDC (with 5% interest)
 * - Interest is earned automatically, balance doesn't increase
 * - This is called "rebasing" in simple terms (but we use scaledBalance)
 */

contract AToken is ERC20, AccessControl {
    using SafeERC20 for IERC20;

    error AToken_ZeroMintingAmount();
    error AToken_InvalidUserAddress();
    error AToken_LessTokenAmount();
    error AToken_NewIndexShouldBeGreater();
    error AToken_InsufficientUnderlyingBalance();
    
    
    bytes32 public constant LENDER_ROLE = keccak256("LENDER_ROLE");
    
    address public underlyingAsset;
    address public lendingPool;
    
    // Scale factor: tracks accumulated interest
    // liquidityIndex grows with interest, so: balanceOf = scaledBalance * liquidityIndex / 1e27
    uint256 public liquidityIndex = 1e27;
    uint256 private scaledTotalSupply;
    uint256 private lastTimestamp;
    
    mapping(address => uint256) private scaledBalances;

     event ATokenMinted(address indexed user,uint256 indexed amount);
     event tokenBurned(address indexed user,uint256 indexed scaledAmount);

    
    constructor(
        address _lendingPool,
        address _underlyingAsset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        lendingPool = _lendingPool;
        underlyingAsset = _underlyingAsset;
        _grantRole(LENDER_ROLE, _lendingPool);
    }
    
    /**
     * Mint aTokens to user (called by LendingPool on deposit)
     * POINTER: scaledAmount = amount / liquidityIndex
     * - This way, as liquidityIndex grows, user's actual balance grows too
     * 
     * @param caller The address performing the deposit
     * @param onBehalfOf The address that will receive the aTokens
     * @param amount The amount being deposited
     * @param index The new liquidity index of the reserve
     * 
     * FLOW:
     * 1. Convert actual amount to scaled amount
     * 2. Store scaled amount in our mapping
     * 3. Emit Transfer event for wallet visibility
     * 
     * WHY SCALED?
     * - scaledBalances: for interest calculation (grows with index)
     * - As liquidityIndex grows, balanceOf() automatically returns more
     * 
     * Example:
     * - liquidityIndex = 1e27 (1.0), amount = 100
     * - scaledAmount = (100 * 1e27) / 1e27 = 100
     * - Later, liquidityIndex = 1.05e27 (5% growth)
     * - balanceOf() returns: (100 * 1.05e27) / 1e27 = 105
     */
    function mint(
        address caller,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) external onlyRole(LENDER_ROLE) {
        // Validate inputs FIRST
        if(amount == 0){
            revert AToken_ZeroMintingAmount();
        }
        if(onBehalfOf == address(0)){
            revert AToken_InvalidUserAddress();
        }
        
        // Update liquidity index if provided
        if (index != liquidityIndex) {
            liquidityIndex = index;
        }
        
        // Convert actual amount to scaled amount
        // scaledAmount = (amount * 1e27) / liquidityIndex
        // As liquidityIndex grows, same scaledAmount = more actual tokens
        uint256 scaledAmount = (amount * 1e27) / liquidityIndex;
        
        // Update internal tracking for onBehalfOf
        scaledBalances[onBehalfOf] += scaledAmount;
        scaledTotalSupply += scaledAmount;
        
        // Emit Transfer event - aTokens go to onBehalfOf
        // We manage balances ourselves via scaledBalances
        // But emit Transfer so wallets/explorers see the tokens
        // Note: We emit the ACTUAL amount (not scaled) so users see correct balance
        emit Transfer(address(0), onBehalfOf, amount);
        
        // Emit our custom event for indexing
        emit ATokenMinted(onBehalfOf, amount);
    }
    
    /**
     * Burn aTokens from user (called by LendingPool on withdrawal)
     * 
     * FLOW:
     * 1. Convert amount to scaledAmount using current liquidityIndex
     * 2. Subtract scaledAmount from user's scaledBalances
     * 3. Subtract scaledAmount from scaledTotalSupply
     * 4. BURN actual ERC20 tokens
     * 
     * IMPORTANT: Check user has enough balance before burning
     */
    function burn(address user, uint256 amount) external onlyRole(LENDER_ROLE) {
        // Validate inputs FIRST
        if(amount == 0){
            revert AToken_ZeroMintingAmount();
        }
        if(user == address(0)){
            revert AToken_InvalidUserAddress();
        }
        
        // Convert actual amount to scaled amount for burning
        // When burning, convert actual amount → scaled amount
        // scaledAmount = (amount * 1e27) / liquidityIndex
        uint256 scaledAmount = (amount * 1e27) / liquidityIndex;
        
        // Check user has enough scaled tokens
        if(scaledBalances[user] < scaledAmount){
            revert AToken_LessTokenAmount();
        }
        
        // Update internal tracking
        scaledBalances[user] -= scaledAmount;
        scaledTotalSupply -= scaledAmount;
        
        
        // Emit Transfer event (NOT calling _burn!)
        // We manage balances ourselves via scaledBalances
        // Emit the ACTUAL amount so users see correct balance change
        emit Transfer(user, address(0), amount);
        
        // Emit our custom event for indexing
        emit tokenBurned(user, amount);
    }
    
    /**
     * Update accumulated interest
     * POINTER: Called periodically to update liquidityIndex
     * - Interest = (totalBorrow * interestRate * timePassed) / totalDeposits
     * - liquidityIndex increases, so balances grow automatically
     * 
     * TODO: Implement index update:
     * 1. Validate newIndex > current liquidityIndex (should always grow or stay same)
     * 2. Update liquidityIndex = newIndex
     * 3. Now all balanceOf() calls will return higher amounts automatically
     * 
     * When is this called?
     * - By LendingPool after calculating interest accrual
     * - Typically happens once per interaction (deposit/borrow/repay/withdraw)
     */
    function updateLiquidityIndex(uint256 newIndex) external onlyRole(LENDER_ROLE) {
        // Validate: index should only increase or stay same (never decrease)
        if(newIndex < liquidityIndex){
            revert AToken_NewIndexShouldBeGreater();
        }
        
        // Update the index
        // This makes all balanceOf() calls return higher amounts automatically
        liquidityIndex = newIndex;
    }
    
    // Override ERC20 to work with scaled balances
    /**
     * TODO: Implement balanceOf view function:
     * - Return: (scaledBalances[account] * liquidityIndex) / 1e27
     * - This makes the balance grow as liquidityIndex grows (automatic interest accrual)
     * - No state change needed
     */
    function balanceOf(address account) public view override returns (uint256) {
        // TODO: Implement

        return (scaledBalances[account]*liquidityIndex)/1e27;
    }
    
    /**
     * TODO: Implement totalSupply view function:
     * - Return: (scaledTotalSupply * liquidityIndex) / 1e27
     * - This shows total value of all deposits with accrued interest
     */
    function totalSupply() public view override returns (uint256) {
        // TODO: Implement
        return (scaledTotalSupply * liquidityIndex) / 1e27;
    }
    
    /**
     * Get user's scaled balance (without interest applied)
     * Useful for internal calculations
     */
    function scaledBalanceOf(address user) external view returns (uint256) {
        return scaledBalances[user];
    }
    
    /**
     * Get total scaled supply (without interest applied)
     */
    function getScaledTotalSupply() external view returns (uint256) {
        return scaledTotalSupply;
    }
    
    /**
     * Transfer underlying asset to target address
     * Called by LendingPool when user borrows or withdraws
     * 
     * @param target The address receiving the underlying asset
     * @param amount The amount of underlying asset to transfer
     * 
     * IMPORTANT: This transfers the ACTUAL underlying ERC20 token (USDC, WETH, etc.)
     * NOT the aToken! The aToken contract acts as a vault holding depositor funds.
     * 
     * Example:
     * - User deposits 100 USDC → aToken contract receives 100 USDC
     * - Borrower wants to borrow 50 USDC
     * - LendingPool calls: aToken.transferUnderlyingTo(borrower, 50)
     * - aToken contract transfers 50 USDC to borrower
     * - aToken contract now holds 50 USDC
     */
    function transferUnderlyingTo(address target, uint256 amount) external onlyRole(LENDER_ROLE) {
        require(target != address(0), "Invalid target address");
        require(amount > 0, "Amount must be > 0");
        
        // Check that we have enough underlying tokens
        uint256 underlyingBalance = IERC20(underlyingAsset).balanceOf(address(this));
        if (underlyingBalance < amount) {
            revert AToken_InsufficientUnderlyingBalance();
        }
        
        // Transfer the underlying ERC20 tokens to target
        IERC20(underlyingAsset).safeTransfer(target, amount);
    }
    
    /**
     * Receive function to handle ETH sent to contract
     * This allows the contract to receive ETH (for WETH scenarios)
     */
    receive() external payable {
        // Accept ETH (needed for WETH unwrapping scenarios)
        // In production, you might want to restrict this or handle WETH conversion
    }
    
    /**
     * Fallback function to handle calls with data
     * Reverts to prevent accidental ETH loss
     */
    fallback() external payable {
        revert("AToken: fallback not allowed");
    }
    
    /**
     * Override transfer to also update our scaledBalances mapping
     * aTokens ARE transferable (unlike debt tokens)
     * When you transfer aTokens, you're transferring your deposit claim
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        if(to == address(0)){
            revert AToken_InvalidUserAddress();
        }
        
        // Convert actual amount to scaled amount
        uint256 scaledAmount = (amount * 1e27) / liquidityIndex;
        
        // Check sender has enough
        if(scaledBalances[msg.sender] < scaledAmount){
            revert AToken_LessTokenAmount();
        }
        
        // Update our tracking
        scaledBalances[msg.sender] -= scaledAmount;
        scaledBalances[to] += scaledAmount;
        
        // Emit Transfer event with ACTUAL amount
        // Don't call super.transfer - we manage state ourselves
        emit Transfer(msg.sender, to, amount);
        
        return true;
    }
    
    /**
     * Override transferFrom to also update our scaledBalances mapping
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if(to == address(0)){
            revert AToken_InvalidUserAddress();
        }
        
        // Convert actual amount to scaled amount
        uint256 scaledAmount = (amount * 1e27) / liquidityIndex;
        
        // Check sender has enough
        if(scaledBalances[from] < scaledAmount){
            revert AToken_LessTokenAmount();
        }
        
        // Update our tracking
        scaledBalances[from] -= scaledAmount;
        scaledBalances[to] += scaledAmount;
        
        // Handle allowance (from ERC20)
        _spendAllowance(from, msg.sender, amount);
        
        // Emit Transfer event with ACTUAL amount
        emit Transfer(from, to, amount);
        
        return true;
    }
}
