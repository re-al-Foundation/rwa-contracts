// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { CrossChainMigrator } from "../../../src/CrossChainMigrator.sol";
import { LZEndpointMock } from "../../../test/utils/LZEndpointMock.sol";
import { TangibleERC20Mock } from "../../../test/utils/TangibleERC20Mock.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/mumbai/MigrateTokens.s.sol:MigrateTokens --broadcast -vvvv

/**
 * @title MigrateTokens
 * @author Chase Brown
 * @notice This script allows us to send a migration message through the migrator contract to migrate TNGBL
 *         ERC-20 tokens to RWA tokens on a destination chain.
 */
contract MigrateTokens is Script {

    // ~ Variables ~

    //CrossChainMigrator public migrator = CrossChainMigrator(0xD42F6Ce9fc98440c518A01749d6fB526CAd52E11); // Mumbai -> Sepolia
    CrossChainMigrator public migrator = CrossChainMigrator(0x7b480d219F68dA5c630534de8bFD0219Bd7BCFaB); // Mumbai -> Unreal
    LZEndpointMock public endpoint = LZEndpointMock(0xf69186dfBa60DdB133E91E9A4B5673624293d8F8);

    TangibleERC20Mock public tngblToken = TangibleERC20Mock(MUMBAI_TNGBL_TOKEN);

    uint16 public remoteEndpointId = UNREAL_CHAINID;

    uint256 public amountTokens = 1 ether;

    address public ADMIN = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    address public ME = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");


    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        uint256 amountETH;

        uint256 airdropAmount = .0001 ether;

        // create adapterParams for custom gas.
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(200000));
        //bytes memory adapterParams = abi.encodePacked(uint16(2), uint256(200000), airdropAmount, ME);

        (amountETH,) = migrator.estimateMigrateTokensFee(
            remoteEndpointId,
            abi.encodePacked(ME),
            amountTokens,
            false,
            adapterParams
        ); // 7.105256640404643037

        console2.log("estimed fees", amountETH);

        tngblToken.approve(address(migrator), amountTokens);
        migrator.migrateTokens{value:amountETH}(
            amountTokens,
            ME,
            payable(ME),
            address(0),
            adapterParams
        );

        vm.stopBroadcast();
    }
}