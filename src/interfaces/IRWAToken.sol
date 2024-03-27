// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IRWAToken {

    /**
     * @notice Allows a permissioned address to burn tokens.
     * @param amount Amount of tokens to burn.
     */
    function burn(uint256 amount) external;
    
    /**
     * @notice Allows a permissioned address to mint new $RWA tokens.
     * @param amount Amount of tokens to mint.
     */
    function mint(uint256 amount) external;

    /**
     * @notice Allows a permissioned address to mint tokens to an external address.
     * @param who Address to mint tokens to.
     * @param amount Amount of tokens to mint.
     */
    function mintFor(address who, uint256 amount) external;
}