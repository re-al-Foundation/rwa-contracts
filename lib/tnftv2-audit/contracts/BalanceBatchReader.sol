// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BalanceBatchReader
 * @author Veljko Mihailovic
 * @notice This contract is used to fetch multiple balances of a single token.
 */
contract BalanceBatchReader {
    /**
     * @notice This method is used to return the balances for an array of wallet addresses.
     * @param tokenAddress Erc20 token contract address we wish to fetch balances for.
     * @param wallets Array of EOAs containing some amount of `tokenAddress` tokens.
     * @return balances -> Array of balances corresponding with the array of wallets provided.
     */
    function balancesOfAddresses(
        IERC20 tokenAddress,
        address[] calldata wallets
    ) external view returns (uint256[] memory balances) {
        uint256 length = wallets.length;
        balances = new uint256[](length);

        for (uint256 i; i < length; ) {
            balances[i] = tokenAddress.balanceOf(wallets[i]);
            unchecked {
                ++i;
            }
        }
    }
}
