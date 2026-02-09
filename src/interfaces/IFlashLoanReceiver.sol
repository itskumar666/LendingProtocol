// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IFlashLoanReceiver
 * @notice Interface for flash loan receiver contracts
 * @dev Contracts that receive flash loans must implement this interface
 */
interface IFlashLoanReceiver {
    
    /**
     * @notice Execute operation after receiving flash loan
     * @param assets The addresses of the assets being flash borrowed
     * @param amounts The amounts being flash borrowed
     * @param premiums The fees to be paid for each asset
     * @param initiator The address that initiated the flash loan
     * @param params Arbitrary bytes data passed from the initiator
     * @return True if the operation was successful
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

/**
 * @title IFlashLoanSimpleReceiver
 * @notice Interface for simple flash loan (single asset) receiver
 */
interface IFlashLoanSimpleReceiver {
    
    /**
     * @notice Execute operation after receiving simple flash loan
     * @param asset The address of the asset being flash borrowed
     * @param amount The amount being flash borrowed
     * @param premium The fee to be paid
     * @param initiator The address that initiated the flash loan
     * @param params Arbitrary bytes data passed from the initiator
     * @return True if the operation was successful
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}
