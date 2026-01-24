// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IStableDebtToken
 * @notice Interface for the stable debt token
 * @dev Represents stable rate debt in the protocol
 */
interface IStableDebtToken is IERC20 {
    
    /**
     * @notice Mints debt token to the `onBehalfOf` address
     * @param user The address receiving the borrowed underlying
     * @param onBehalfOf The address getting the debt
     * @param amount The amount being minted
     * @param rate The stable rate at which the debt is borrowed
     * @return True if the previous balance of the user was 0, false otherwise
     * @return The new stable rate for the user after minting
     */
    function mint(
        address user,
        address onBehalfOf,
        uint256 amount,
        uint256 rate
    ) external returns (bool, uint256);
    
    /**
     * @notice Burns debt of `user`
     * @param from The address from which the debt will be burned
     * @param amount The amount getting burned
     * @return The new total supply after burn
     */
    function burn(address from, uint256 amount) external returns (uint256);
    
    /**
     * @notice Returns the average stable rate across all users
     * @return The average stable rate
     */
    function getAverageStableRate() external view returns (uint256);
    
    /**
     * @notice Returns the stable rate of the user
     * @param user The address of the user
     * @return The stable rate of the user
     */
    function getUserStableRate(address user) external view returns (uint256);
    
    /**
     * @notice Returns the timestamp of the last update
     * @param user The address of the user
     * @return The timestamp of the last update
     */
    function getUserLastUpdated(address user) external view returns (uint40);
    
    /**
     * @notice Returns the principal debt balance of the user
     * @param user The address of the user
     * @return The principal debt balance
     */
    function principalBalanceOf(address user) external view returns (uint256);
    
    /**
     * @notice Returns the address of the underlying asset
     * @return The address of the underlying asset
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    
    /**
     * @notice Returns the total supply of stable debt tokens including interest
     * @return The total supply with accrued interest
     */
    function getTotalSupplyAndAvgRate() external view returns (uint256, uint256);
}
