// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @dev Helper file for testing.
contract Utility is Test{

    // ~ RPCs ~

    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");
    

    // ~ Actors ~

    // permissioned
    address public constant MULTISIG = 0x946C569791De3283f33372731d77555083c329da;
    address public constant DEFAULT_ADMIN_TNGBL = 0x100fCC635acf0c22dCdceF49DD93cA94E55F0c71;
    address public constant DEFAULT_ADMIN_PI = 0x3d41487A3c5662eDE90D0eE8854f3cC59E8D66AD;
    address public constant ADMIN = address(bytes20(bytes("Admin")));
    address public constant LAYER_Z = address(bytes20(bytes("Layer Zero")));
    address public constant GELATO = address(bytes20(bytes("Gelato")));

    // permissionless
    address public constant JOE   = address(bytes20(bytes("Joe")));
    address public constant NIK   = address(bytes20(bytes("Nik")));
    address public constant ALICE = address(bytes20(bytes("Alice")));
    address public constant BOB   = address(bytes20(bytes("Bob")));


    // ~ Constants ~

    IERC20Metadata public constant MUMBAI_WETH = IERC20Metadata(0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa);


    // ~ Precision ~

    uint256 constant USD = 10 ** 6;  // USDC precision decimals
    uint256 constant BTC = 10 ** 8;  // WBTC precision decimals
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;


    // ~ Events ~

    event log_named_bool(string key, bool val);


    // ~ Utility Functions ~

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayUint(uint256 element) internal pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    /// @notice Turns a single address to an array of uints of size 1.
    function _asSingletonArrayAddress(address element) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = element;

        return array;
    }

    /// @notice Turns a single uint to an array of uints of size 1.
    function _asSingletonArrayString(string memory element) internal pure returns (string[] memory) {
        string[] memory array = new string[](1);
        array[0] = element;

        return array;
    }

    /// @notice Verify equality within accuracy decimals.
    function assertWithinPrecision(uint256 val0, uint256 val1, uint256 accuracy) internal {
        uint256 diff  = val0 > val1 ? val0 - val1 : val1 - val0;
        if (diff == 0) return;

        uint256 denominator = val0 == 0 ? val1 : val0;
        bool check = ((diff * RAY) / denominator) < (RAY / 10 ** accuracy);

        if (!check){
            emit log_named_uint("Error: approx a == b not satisfied, accuracy digits ", accuracy);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }

    /// @notice Verify equality within difference.
    function assertWithinDiff(uint256 val0, uint256 val1, uint256 expectedDiff) internal {
        uint256 actualDiff = val0 > val1 ? val0 - val1 : val1 - val0;
        bool check = actualDiff <= expectedDiff;

        if (!check) {
            emit log_named_uint("Error: approx a == b not satisfied, accuracy difference ", expectedDiff);
            emit log_named_uint("Actual difference ", actualDiff);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }
}