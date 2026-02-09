// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {DataTypes} from '../types/DataTypes.sol';
import {Errors} from '../helpers/Errors.sol';
import {ReserveConfiguration} from '../configuration/ReserveConfiguration.sol';
import {PercentageMath} from '../math/PercentageMath.sol';
import {WadRayMath} from '../math/WadRayMath.sol';
import {ValidationLogic} from './ValidationLogic.sol';
import {IAToken} from '../../interfaces/IAToken.sol';
import {IFlashLoanReceiver, IFlashLoanSimpleReceiver} from '../../interfaces/IFlashLoanReceiver.sol';
import {IInterestRateStrategy} from '../../interfaces/IInterestRateStrategy.sol';
import {IStableDebtToken} from '../../interfaces/IStableDebtToken.sol';
import {IVariableDebtToken} from '../../interfaces/IVariableDebtToken.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title FlashLoanLogic
 * @notice Handles flash loan operations
 * @dev Flash loans allow borrowing assets without collateral, 
 * as long as they are repaid within the same transaction
 * 
 * Flash Loan Process:
 * 1. Transfer assets to receiver
 * 2. Call executeOperation() on receiver
 * 3. Verify repayment with premium (fee)
 * 4. Update interest rates
 * 
 * Use cases:
 * - Arbitrage between DEXs
 * - Collateral swaps
 * - Self-liquidation
 * - Leverage/deleverage positions
 */
library FlashLoanLogic {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using PercentageMath for uint256;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    
    // ============ Constants ============
    
    /// @notice Flash loan premium (fee) in basis points: 9 = 0.09%
    uint256 public constant FLASHLOAN_PREMIUM_TOTAL = 9;
    
    /// @notice Portion of premium going to protocol treasury
    uint256 public constant FLASHLOAN_PREMIUM_TO_PROTOCOL = 0;
    
    /// @notice Basis points denominator
    uint256 public constant PERCENTAGE_FACTOR = 10000;
    
    // ============ Events ============
    
    event FlashLoan(
        address indexed target,
        address indexed initiator,
        address indexed asset,
        uint256 amount,
        uint256 interestRateMode,
        uint256 premium,
        uint16 referralCode
    );
    
    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );
    
    // ============ Structs ============
    
    struct FlashLoanLocalVars {
        uint256 i;
        uint256 currentAmount;
        uint256 currentPremium;
        uint256 currentAmountPlusPremium;
        address currentAsset;
        address currentATokenAddress;
        uint256 flashloanPremiumTotal;
        uint256 flashloanPremiumToProtocol;
    }
    
    struct FlashLoanSimpleLocalVars {
        uint256 premium;
        uint256 amountPlusPremium;
        uint256 totalDebt;
        IAToken aToken;
    }
    
    // ============ Main Functions ============
    
    /**
     * @notice Execute flash loan for multiple assets
     * @param reservesData Mapping of all reserves
     * @param params Flash loan parameters
     * @param flashloanPremiumTotal Total premium in basis points
     * @param flashloanPremiumToProtocol Protocol's share of premium
     * @return True if flash loan was successful
     */
    function executeFlashLoan(
        mapping(address => DataTypes.ReserveData) storage reservesData,
        DataTypes.ExecuteFlashLoanParams memory params,
        uint256 flashloanPremiumTotal,
        uint256 flashloanPremiumToProtocol
    ) internal returns (bool) {
        FlashLoanLocalVars memory vars;
        vars.flashloanPremiumTotal = flashloanPremiumTotal;
        vars.flashloanPremiumToProtocol = flashloanPremiumToProtocol;
        
        uint256[] memory premiums = new uint256[](params.assets.length);
        uint256[] memory amountsToTransfer = new uint256[](params.assets.length);
        
        // Validate and transfer assets to receiver
        for (vars.i = 0; vars.i < params.assets.length; vars.i++) {
            vars.currentAsset = params.assets[vars.i];
            vars.currentAmount = params.amounts[vars.i];
            
            DataTypes.ReserveData storage reserve = reservesData[vars.currentAsset];
            vars.currentATokenAddress = reserve.aTokenAddress;
            
            // Validate flash loan for this asset
            ValidationLogic.validateFlashLoanSimple(reserve, vars.currentAmount);
            
            // Calculate premium
            premiums[vars.i] = vars.currentAmount.percentMul(vars.flashloanPremiumTotal);
            amountsToTransfer[vars.i] = vars.currentAmount;
            
            // Transfer asset from aToken to receiver
            IAToken(vars.currentATokenAddress).transferUnderlyingTo(
                params.receiverAddress,
                vars.currentAmount
            );
        }
        
        // Call receiver's executeOperation
        require(
            IFlashLoanReceiver(params.receiverAddress).executeOperation(
                params.assets,
                params.amounts,
                premiums,
                msg.sender,
                params.params
            ),
            Errors.INVALID_FLASHLOAN_EXECUTOR_RETURN
        );
        
        // Verify repayment and collect premiums
        for (vars.i = 0; vars.i < params.assets.length; vars.i++) {
            vars.currentAsset = params.assets[vars.i];
            vars.currentAmount = params.amounts[vars.i];
            vars.currentPremium = premiums[vars.i];
            vars.currentAmountPlusPremium = vars.currentAmount + vars.currentPremium;
            
            DataTypes.ReserveData storage reserve = reservesData[vars.currentAsset];
            vars.currentATokenAddress = reserve.aTokenAddress;
            
            // Check if borrowing instead of repaying
            if (params.interestRateModes[vars.i] != 0) {
                // Borrow mode - mint debt tokens instead of repaying
                _handleFlashLoanBorrow(
                    reserve,
                    vars.currentAsset,
                    vars.currentAmount,
                    params.interestRateModes[vars.i],
                    params.onBehalfOf
                );
            } else {
                // Repay mode - transfer back to aToken
                IERC20(vars.currentAsset).safeTransferFrom(
                    params.receiverAddress,
                    vars.currentATokenAddress,
                    vars.currentAmountPlusPremium
                );
                
                // Update reserve liquidity (premium added)
                reserve.availableLiquidity += vars.currentPremium;
            }
            
            // Update interest rates
            _updateInterestRates(reserve, vars.currentAsset);
            
            emit FlashLoan(
                params.receiverAddress,
                msg.sender,
                vars.currentAsset,
                vars.currentAmount,
                params.interestRateModes[vars.i],
                vars.currentPremium,
                params.referralCode
            );
        }
        
        return true;
    }
    
    /**
     * @notice Execute simple flash loan (single asset)
     * @param reserve The reserve data
     * @param params Flash loan simple parameters
     * @param flashloanPremiumTotal Total premium in basis points
     * @return True if flash loan was successful
     */
    function executeFlashLoanSimple(
        DataTypes.ReserveData storage reserve,
        DataTypes.ExecuteFlashLoanSimpleParams memory params,
        uint256 flashloanPremiumTotal
    ) internal returns (bool) {
        FlashLoanSimpleLocalVars memory vars;
        
        // Validate
        ValidationLogic.validateFlashLoanSimple(reserve, params.amount);
        
        vars.aToken = IAToken(reserve.aTokenAddress);
        
        // Calculate premium
        vars.premium = params.amount.percentMul(flashloanPremiumTotal);
        vars.amountPlusPremium = params.amount + vars.premium;
        
        // Transfer asset to receiver
        vars.aToken.transferUnderlyingTo(params.receiverAddress, params.amount);
        
        // Call receiver's executeOperation
        require(
            IFlashLoanSimpleReceiver(params.receiverAddress).executeOperation(
                params.asset,
                params.amount,
                vars.premium,
                msg.sender,
                params.params
            ),
            Errors.INVALID_FLASHLOAN_EXECUTOR_RETURN
        );
        
        // Transfer back amount + premium
        IERC20(params.asset).safeTransferFrom(
            params.receiverAddress,
            address(vars.aToken),
            vars.amountPlusPremium
        );
        
        // Update reserve liquidity
        reserve.availableLiquidity += vars.premium;
        
        // Update interest rates
        _updateInterestRates(reserve, params.asset);
        
        emit FlashLoan(
            params.receiverAddress,
            msg.sender,
            params.asset,
            params.amount,
            0, // No borrow mode for simple flash loan
            vars.premium,
            params.referralCode
        );
        
        return true;
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Handle flash loan borrow mode
     * @dev Instead of repaying, user takes on debt
     */
    function _handleFlashLoanBorrow(
        DataTypes.ReserveData storage reserve,
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) internal {
        // Mint debt tokens
        if (interestRateMode == DataTypes.INTEREST_RATE_MODE_STABLE) {
            IStableDebtToken(reserve.stableDebtTokenAddress).mint(
                onBehalfOf,
                onBehalfOf,
                amount,
                reserve.currentStableBorrowRate
            );
        } else {
            IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
                onBehalfOf,
                onBehalfOf,
                amount,
                reserve.variableBorrowIndex
            );
        }
        
        // Reduce available liquidity
        reserve.availableLiquidity -= amount;
    }
    
    /**
     * @notice Update interest rates after flash loan
     */
    function _updateInterestRates(
        DataTypes.ReserveData storage reserve,
        address asset
    ) internal {
        uint256 totalStableDebt = IStableDebtToken(reserve.stableDebtTokenAddress).totalSupply();
        uint256 totalVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).totalSupply();
        uint256 totalDebt = totalStableDebt + totalVariableDebt;
        
        (
            uint256 newLiquidityRate,
            uint256 newVariableRate,
            uint256 newStableRate
        ) = IInterestRateStrategy(reserve.interestRateStrategyAddress).calculateInterestRate(
            reserve.availableLiquidity,
            totalDebt
        );
        
        reserve.currentLiquidityRate = uint128(newLiquidityRate);
        reserve.currentVariableBorrowRate = uint128(newVariableRate);
        reserve.currentStableBorrowRate = uint128(newStableRate);
        
        emit ReserveDataUpdated(
            asset,
            newLiquidityRate,
            newStableRate,
            newVariableRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex
        );
    }
    
    /**
     * @notice Calculate flash loan premium
     * @param amount The flash loan amount
     * @param premiumBps Premium in basis points
     * @return The premium amount
     */
    function calculateFlashLoanPremium(
        uint256 amount,
        uint256 premiumBps
    ) internal pure returns (uint256) {
        return amount.percentMul(premiumBps);
    }
}
