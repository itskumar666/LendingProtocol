// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAToken
 * @notice Interface for the interest-bearing token (aToken)
 * @dev Represents deposits in the protocol that earn interest
 */
interface IAToken is IERC20 {
    
    /**
     * @notice Mints aTokens to user
     * @param caller The address performing the supply (msg.sender)
     * @param onBehalfOf The address that will receive the aTokens
     * @param amount The amount being minted
     * @param index The new liquidity index of the reserve
     */
    function mint(
        address caller,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) external;
    
    /**
     * @notice Burns aTokens from user
     * @param user The owner of the aTokens, getting them burned
     * @param receiverOfUnderlying The address that will receive the underlying
     * @param amount The amount being burned
     * @param index The new liquidity index of the reserve
     */
    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external;
    
    /**
     * @notice Mints aTokens to the reserve treasury
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve
     */
    function mintToTreasury(uint256 amount, uint256 index) external;
    
    /**
     * @notice Transfers the underlying asset to target
     * @param target The recipient of the underlying
     * @param amount The amount getting transferred
     */
    function transferUnderlyingTo(address target, uint256 amount) external;
    
    /**
     * @notice Returns the scaled balance of the user
     * @param user The address of the user
     * @return The scaled balance of the user
     */
    function scaledBalanceOf(address user) external view returns (uint256);
    
    /**
     * @notice Returns the scaled total supply of the aToken
     * @return The scaled total supply
     */
    function scaledTotalSupply() external view returns (uint256);
    
    /**
     * @notice Returns the address of the underlying asset
     * @return The address of the underlying asset
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
