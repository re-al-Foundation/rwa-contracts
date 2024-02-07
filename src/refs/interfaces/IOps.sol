// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

interface IOps {
    function cancelTask(bytes32 _taskId) external;

    function createTask(
        address _execAddress,
        bytes4 _execSelector,
        address _resolverAddress,
        bytes calldata _resolverData
    ) external returns (bytes32 task);
}