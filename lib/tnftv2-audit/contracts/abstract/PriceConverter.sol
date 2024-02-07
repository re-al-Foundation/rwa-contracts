// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract PriceConverter {
    function toDecimals(
        uint256 amount,
        uint8 fromDecimal,
        uint8 toDecimal
    ) internal pure returns (uint256) {
        require(toDecimal >= uint8(0) && toDecimal <= uint8(18), "Invalid _decimals");
        if (fromDecimal > toDecimal) {
            amount = amount / (10 ** (fromDecimal - toDecimal));
        } else if (fromDecimal < toDecimal) {
            amount = amount * (10 ** (toDecimal - fromDecimal));
        }
        return amount;
    }
}
