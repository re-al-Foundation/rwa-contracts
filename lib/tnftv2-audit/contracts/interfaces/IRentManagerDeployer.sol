// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./IRentManager.sol";

/// @title IRentManagerDeployer interface defines the interface of the RentManagerDeployer.
interface IRentManagerDeployer {
    /// @dev Will deploy a new RentManager contract and return the RentManager reference.
    function deployRentManager(address tnft) external returns (IRentManager);
}
