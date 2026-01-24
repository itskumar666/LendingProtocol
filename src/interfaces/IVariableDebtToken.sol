// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IVariableDebtToken
 * @notice Interface for the variable debt token
 * @dev Represents variable rate debt in the protocol
 */
interface IVariableDebtToken is IERC20 {
    
    /**
     * @notice Mints debt token to the `onBehalfOf` address
     * @param user The address receiving the borrowed underlying
     * @param onBehalfOf The address getting the debt
     * @param amount The amount being minted
     * @param index The variable debt index of the reserve
     * @return True if the previous balance of the user was 0, false otherwise
     */
    function mint(
        address user,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) external returns (bool);
    
    /**
     * @notice Burns debt of `user`
     * @param from The address from which the debt will be burned
     * @param amount The amount getting burned
     * @param index The variable debt index of the reserve
     * @return The new total supply after burn
     */
    function burn(
        address from,
        uint256 amount,
        uint256 index
    ) external returns (uint256);
    
    /**
     * @notice Returns the scaled balance of the user
     * @param user The address of the user
     * @return The scaled balance of the user
     */
    function scaledBalanceOf(address user) external view returns (uint256);
    
    /**
     * @notice Returns the scaled total supply of the debt token
     * @return The scaled total supply
     */
    function scaledTotalSupply() external view returns (uint256);
    
    /**
     * @notice Returns the address of the underlying asset
     * @return The address of the underlying asset
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
