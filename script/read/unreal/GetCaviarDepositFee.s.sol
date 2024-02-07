// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

/// @dev To run: forge script script/read/unreal/GetCaviarDepositFee.s.sol:GetCaviarDepositFee --broadcast

interface ICaviarManager {
    function disableRedeem() external;
    function getCurrentEpoch() external view returns (uint256);
    function getCurrentDepositFee() external view returns (uint256);
}

/**
 * @title GetCaviarDepositFee
 * @author Chase Brown
 * @notice This script reads the deposit fee var from the caviar manager.
 */
contract GetCaviarDepositFee is Script {

    // ~ Variables ~

    ICaviarManager public caviarManager = ICaviarManager(0xBAcBdF8Fc01D25A632a19236aB88162C931775Df);

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");


    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        uint256 fee = caviarManager.getCurrentDepositFee();

        console2.log("fee", fee);

        vm.stopBroadcast();
    }
}
