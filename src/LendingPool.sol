// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./libraries/types/DataTypes.sol";
import "./libraries/math/WadRayMath.sol";
import "./libraries/math/PercentageMath.sol";
import "./libraries/math/HealthFactor.sol";
import "./libraries/configuration/ReserveConfiguration.sol";
import "./libraries/configuration/UserConfiguration.sol";
import "./libraries/logic/DepositLogic.sol";
import "./libraries/logic/WithdrawLogic.sol";
import "./libraries/logic/BorrowLogic.sol";
import "./libraries/logic/RepayLogic.sol";
import "./libraries/logic/LiquidationLogic.sol";
import "./libraries/logic/FlashLoanLogic.sol";
import "./libraries/logic/ValidationLogic.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IAToken.sol";
import "./interfaces/IStableDebtToken.sol";
import "./interfaces/IVariableDebtToken.sol";

/**
 * @title LendingPool
 * @author LendingProtocol
 * @notice Main contract for the lending protocol
 * @dev Integrates all logic libraries and manages reserve state
 */
contract LendingPool is ILendingPool, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    // ============ Constants ============

    bytes32 public constant POOL_ADMIN_ROLE = keccak256("POOL_ADMIN_ROLE");
    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");
    bytes32 public constant RISK_ADMIN_ROLE = keccak256("RISK_ADMIN_ROLE");

    uint256 public constant FLASHLOAN_PREMIUM_TOTAL = 9; // 0.09%
    uint256 public constant FLASHLOAN_PREMIUM_TO_PROTOCOL = 0;
    uint256 public constant MAX_NUMBER_RESERVES = 128;
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;

    // ============ State Variables ============

    mapping(address => DataTypes.ReserveData) internal _reserves;
    mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;
    address[] internal _reservesList;
    mapping(address => uint256) internal _reservesListIndex;

    IPriceOracle public oracle;
    address public treasury;
    uint256 public maxStableRateBorrowSizePercent;
    bool public flashLoansEnabled;

    // ============ Events ============

    event Deposit(address indexed asset, address indexed user, address indexed onBehalfOf, uint256 amount, uint16 referralCode);
    event Withdraw(address indexed asset, address indexed user, address indexed to, uint256 amount);
    event Borrow(address indexed asset, address indexed user, address indexed onBehalfOf, uint256 amount, uint256 interestRateMode, uint256 borrowRate, uint16 referralCode);
    event Repay(address indexed asset, address indexed user, address indexed repayer, uint256 amount, bool useATokens);
    event LiquidationCall(address indexed collateralAsset, address indexed debtAsset, address indexed user, uint256 debtToCover, uint256 liquidatedCollateralAmount, address liquidator, bool receiveAToken);
    event FlashLoan(address indexed target, address indexed initiator, address indexed asset, uint256 amount, uint256 interestRateMode, uint256 premium, uint16 referralCode);
    event ReserveUsedAsCollateralEnabled(address indexed asset, address indexed user);
    event ReserveUsedAsCollateralDisabled(address indexed asset, address indexed user);
    event ReserveInitialized(address indexed asset, address indexed aToken, address stableDebtToken, address variableDebtToken, address interestRateStrategy);
    event OracleUpdated(address indexed newOracle);
    event TreasuryUpdated(address indexed newTreasury);

    // ============ Errors ============

    error InvalidAddress();
    error ReserveAlreadyInitialized();
    error ReserveNotActive();
    error MaxReservesExceeded();
    error HealthFactorBelowThreshold();
    error NotEnoughCollateral();
    error FlashLoansDisabled();

    // ============ Constructor ============

    constructor(address _oracle, address _treasury) {
        if (_oracle == address(0) || _treasury == address(0)) revert InvalidAddress();
        
        oracle = IPriceOracle(_oracle);
        treasury = _treasury;
        maxStableRateBorrowSizePercent = 2500;
        flashLoansEnabled = true;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(POOL_ADMIN_ROLE, msg.sender);
        _grantRole(EMERGENCY_ADMIN_ROLE, msg.sender);
        _grantRole(RISK_ADMIN_ROLE, msg.sender);
    }

    // ============ Core Functions ============

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external override nonReentrant whenNotPaused {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        
        // Use DepositLogic's validation
        DepositLogic.validateDeposit(
            reserve,
            DataTypes.ExecuteDepositParams({
                asset: asset,
                amount: amount,
                onBehalfOf: onBehalfOf,
                referralCode: referralCode,
                supplyCap: reserve.configuration.getSupplyCap()
            })
        );

        // Execute deposit
        DepositLogic.executeDeposit(
            reserve,
            DataTypes.ExecuteDepositParams({
                asset: asset,
                amount: amount,
                onBehalfOf: onBehalfOf,
                referralCode: referralCode,
                supplyCap: 0
            })
        );

        // Enable collateral for first deposit
        if (!_usersConfig[onBehalfOf].isUsingAsCollateral(reserve.id)) {
            _usersConfig[onBehalfOf].setUsingAsCollateral(reserve.id, true);
            emit ReserveUsedAsCollateralEnabled(asset, onBehalfOf);
        }

        emit Deposit(asset, msg.sender, onBehalfOf, amount, referralCode);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override nonReentrant whenNotPaused returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        uint256 userBalance = IAToken(reserve.aTokenAddress).balanceOf(msg.sender);
        uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;

        // Execute withdraw using library
        uint256 amountWithdrawn = WithdrawLogic.executeWithdraw(
            reserve,
            DataTypes.ExecuteWithdrawParams({
                user: msg.sender,
                asset: asset,
                amount: amountToWithdraw,
                to: to
            })
        );

        // Disable collateral if balance becomes zero
        if (IAToken(reserve.aTokenAddress).balanceOf(msg.sender) == 0) {
            _usersConfig[msg.sender].setUsingAsCollateral(reserve.id, false);
            emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
        }

        emit Withdraw(asset, msg.sender, to, amountWithdrawn);
        return amountWithdrawn;
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external override nonReentrant whenNotPaused {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        // Execute borrow
        BorrowLogic.executeBorrow(
            reserve,
            DataTypes.ExecuteBorrowParams({
                asset: asset,
                user: msg.sender,
                onBehalfOf: onBehalfOf,
                amount: amount,
                interestRateMode: interestRateMode,
                referralCode: referralCode,
                borrowCap: reserve.configuration.getBorrowCap(),
                totalStableDebt: IStableDebtToken(reserve.stableDebtTokenAddress).totalSupply(),
                totalVariableDebt: IVariableDebtToken(reserve.variableDebtTokenAddress).totalSupply(),
                delegatedAllowance: 0,
                availableBorrows: 0,
                amountInBase: 0
            })
        );

        // Mark user as borrowing
        if (!_usersConfig[onBehalfOf].isBorrowing(reserve.id)) {
            _usersConfig[onBehalfOf].setBorrowing(reserve.id, true);
        }

        emit Borrow(asset, msg.sender, onBehalfOf, amount, interestRateMode, reserve.currentVariableBorrowRate, referralCode);
    }

    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external override nonReentrant whenNotPaused returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        uint256 paybackAmount = RepayLogic.executeRepay(
            reserve,
            DataTypes.ExecuteRepayParams({
                asset: asset,
                amount: amount,
                interestRateMode: interestRateMode,
                onBehalfOf: onBehalfOf
            })
        );

        // Update borrowing status if debt fully repaid
        uint256 stableDebt = IStableDebtToken(reserve.stableDebtTokenAddress).balanceOf(onBehalfOf);
        uint256 variableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).balanceOf(onBehalfOf);
        if (stableDebt == 0 && variableDebt == 0) {
            _usersConfig[onBehalfOf].setBorrowing(reserve.id, false);
        }

        emit Repay(asset, onBehalfOf, msg.sender, paybackAmount, false);
        return paybackAmount;
    }

    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external override nonReentrant whenNotPaused {
        DataTypes.ReserveData storage collateralReserve = _reserves[collateralAsset];
        DataTypes.ReserveData storage debtReserve = _reserves[debtAsset];

        (uint256 actualDebtToLiquidate, uint256 actualCollateralToSeize) = LiquidationLogic.executeLiquidationCall(
            collateralReserve,
            debtReserve,
            DataTypes.ExecuteLiquidationCallParams({
                reservesCount: uint8(_reservesList.length),
                debtToCover: debtToCover,
                collateralAsset: collateralAsset,
                debtAsset: debtAsset,
                user: user,
                receiveAToken: receiveAToken
            }),
            address(oracle)
        );

        // Update user config if collateral fully liquidated
        if (IAToken(collateralReserve.aTokenAddress).balanceOf(user) == 0) {
            _usersConfig[user].setUsingAsCollateral(collateralReserve.id, false);
            emit ReserveUsedAsCollateralDisabled(collateralAsset, user);
        }

        // Update borrowing status
        uint256 stableDebt = IStableDebtToken(debtReserve.stableDebtTokenAddress).balanceOf(user);
        uint256 variableDebt = IVariableDebtToken(debtReserve.variableDebtTokenAddress).balanceOf(user);
        if (stableDebt == 0 && variableDebt == 0) {
            _usersConfig[user].setBorrowing(debtReserve.id, false);
        }

        emit LiquidationCall(collateralAsset, debtAsset, user, actualDebtToLiquidate, actualCollateralToSeize, msg.sender, receiveAToken);
    }

    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external override nonReentrant whenNotPaused {
        if (!flashLoansEnabled) revert FlashLoansDisabled();

        FlashLoanLogic.executeFlashLoan(
            _reserves,
            DataTypes.ExecuteFlashLoanParams({
                receiverAddress: receiverAddress,
                assets: assets,
                amounts: amounts,
                interestRateModes: interestRateModes,
                onBehalfOf: onBehalfOf,
                params: params,
                referralCode: referralCode
            }),
            FLASHLOAN_PREMIUM_TOTAL,
            FLASHLOAN_PREMIUM_TO_PROTOCOL
        );

        for (uint256 i = 0; i < assets.length; i++) {
            uint256 premium = amounts[i].percentMul(FLASHLOAN_PREMIUM_TOTAL);
            emit FlashLoan(receiverAddress, msg.sender, assets[i], amounts[i], interestRateModes[i], premium, referralCode);
        }
    }

    function setUserUseReserveAsCollateral(
        address asset,
        bool useAsCollateral
    ) external override nonReentrant whenNotPaused {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        uint256 userBalance = IAToken(reserve.aTokenAddress).balanceOf(msg.sender);
        if (userBalance == 0) revert NotEnoughCollateral();

        _usersConfig[msg.sender].setUsingAsCollateral(reserve.id, useAsCollateral);

        if (useAsCollateral) {
            emit ReserveUsedAsCollateralEnabled(asset, msg.sender);
        } else {
            emit ReserveUsedAsCollateralDisabled(asset, msg.sender);
        }
    }

    // ============ View Functions ============

    function getReserveData(address asset) external view override returns (DataTypes.ReserveData memory) {
        return _reserves[asset];
    }

    function getUserAccountData(address user) public view override returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return HealthFactor.calculateUserAccountData(
            user,
            _reserves,
            _reservesList,
            address(oracle)
        );
    }

    function getUserConfiguration(address user) external view override returns (DataTypes.UserConfigurationMap memory) {
        return _usersConfig[user];
    }

    function getConfiguration(address asset) external view override returns (DataTypes.ReserveConfigurationMap memory) {
        return _reserves[asset].configuration;
    }

    function getReserveNormalizedIncome(address asset) external view override returns (uint256) {
        return _reserves[asset].liquidityIndex;
    }

    function getReserveNormalizedVariableDebt(address asset) external view override returns (uint256) {
        return _reserves[asset].variableBorrowIndex;
    }

    function getReservesList() external view override returns (address[] memory) {
        return _reservesList;
    }

    function getReservesCount() external view returns (uint256) {
        return _reservesList.length;
    }

    // ============ Admin Functions ============

    function initReserve(
        address asset,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress
    ) external onlyRole(POOL_ADMIN_ROLE) {
        if (_reserves[asset].aTokenAddress != address(0)) revert ReserveAlreadyInitialized();
        if (_reservesList.length >= MAX_NUMBER_RESERVES) revert MaxReservesExceeded();

        _reserves[asset] = DataTypes.ReserveData({
            aTokenAddress: aTokenAddress,
            stableDebtTokenAddress: stableDebtTokenAddress,
            variableDebtTokenAddress: variableDebtTokenAddress,
            interestRateStrategyAddress: interestRateStrategyAddress,
            availableLiquidity: 0,
            liquidityIndex: uint128(WadRayMath.RAY),
            variableBorrowIndex: uint128(WadRayMath.RAY),
            currentLiquidityRate: 0,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: uint40(block.timestamp),
            configuration: DataTypes.ReserveConfigurationMap({data: 0}),
            id: uint16(_reservesList.length),
            isActive: true,
            isFrozen: false,
            borrowingEnabled: true,
            stableBorrowRateEnabled: true,
            isPaused: false
        });

        _reservesListIndex[asset] = _reservesList.length;
        _reservesList.push(asset);

        emit ReserveInitialized(asset, aTokenAddress, stableDebtTokenAddress, variableDebtTokenAddress, interestRateStrategyAddress);
    }

    function setReserveConfiguration(
        address asset,
        DataTypes.ReserveConfigurationMap calldata configuration
    ) external onlyRole(RISK_ADMIN_ROLE) {
        if (_reserves[asset].aTokenAddress == address(0)) revert ReserveNotActive();
        _reserves[asset].configuration = configuration;
    }

    function setOracle(address newOracle) external onlyRole(POOL_ADMIN_ROLE) {
        if (newOracle == address(0)) revert InvalidAddress();
        oracle = IPriceOracle(newOracle);
        emit OracleUpdated(newOracle);
    }

    function setTreasury(address newTreasury) external onlyRole(POOL_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert InvalidAddress();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function setFlashLoansEnabled(bool enabled) external onlyRole(POOL_ADMIN_ROLE) {
        flashLoansEnabled = enabled;
    }

    function pause() external onlyRole(EMERGENCY_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(EMERGENCY_ADMIN_ROLE) {
        _unpause();
    }
}
