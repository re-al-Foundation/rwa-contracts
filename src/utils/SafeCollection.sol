// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "./Collection.sol";

library SafeCollection {
    function safeAdd(
        mapping(address => Collection) storage collections,
        address who,
        uint256 itemId
    ) public {
        Collection collection = collections[who];
        if (address(collection) == address(0)) {
            collections[who] = collection = new Collection();
        }
        collection.append(itemId);
    }

    function safeRemove(Collection collection, uint256 itemId) public {
        if (address(collection) != address(0)) {
            collection.remove(itemId);
        }
    }
}