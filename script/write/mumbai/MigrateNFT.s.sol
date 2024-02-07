// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// v1 imports
import { TangibleERC20Mock } from "../../../test/utils/TangibleERC20Mock.sol";
import { PassiveIncomeNFT } from "../../../src/refs/PassiveIncomeNFT.sol";

// local imports
import { CrossChainMigrator } from "../../../src/CrossChainMigrator.sol";
import { LZEndpointMock } from "../../../test/utils/LZEndpointMock.sol";
import { RWAVotingEscrow } from "../../../src/governance/RWAVotingEscrow.sol";
import { RWAToken } from "../../../src/RWAToken.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/write/mumbai/MigrateNFT.s.sol:MigrateNFT --broadcast

/**
 * @title MigrateNFT
 * @author Chase Brown
 * @notice This script allows us to migrate a 3,3+ NFT to a veRWA NFT from Mumbai to a destination chain.
 */
contract MigrateNFT is Script {

    // ~ Variables ~

    CrossChainMigrator public migrator = CrossChainMigrator(0xD42F6Ce9fc98440c518A01749d6fB526CAd52E11);
    LZEndpointMock public endpoint = LZEndpointMock(0xf69186dfBa60DdB133E91E9A4B5673624293d8F8);

    //RWAToken public rwaToken = RWAToken(payable(0xAf960b9B057f59c68e55Ff9aC29966d9bf62b71B));
    //RWAVotingEscrow public veRWA = RWAVotingEscrow(0x297670562a8BcfACBe5c30BBAC5ca7062ac7f652);

    TangibleERC20Mock public tngblToken = TangibleERC20Mock(MUMBAI_TNGBL_TOKEN);
    PassiveIncomeNFT public piNFT = PassiveIncomeNFT(MUMBAI_PI_NFT);

    uint16 public remoteEndpointId = SEPOLIA_CHAINID;

    uint256 public tokenId = 7;

    address public ADMIN = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    address public ME = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");


    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        (uint256 startTime,
        uint256 endTime,
        uint256 lockedAmount,
        /** multiplier */,
        uint256 claimed,
        uint256 maxPayout) = piNFT.locks(tokenId);

        console2.log("========= V1 =========");
        console2.log("startTime", startTime);
        console2.log("endTime", endTime);
        console2.log("current", block.timestamp);
        console2.log("lockedAmount", lockedAmount); // 35.000000000000000000
        console2.log("claimed", claimed); // 0
        console2.log("maxPayout", maxPayout); // 325.216445126622952945

        uint256 amountETH;

        // create adapterParams for custom gas.
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(200000));

        (amountETH,) = migrator.estimateMigrateNFTFee(
            remoteEndpointId,
            abi.encodePacked(ME),
            lockedAmount + maxPayout,
            endTime - startTime,
            false,
            adapterParams
        ); // .182266933120659462

        console2.log("estimated fees", amountETH);

        // tngblToken.approve(address(migrator), amountTokens);
        // migrator.migrateTokens{value:amountETH}(
        //     amountTokens,
        //     ME,
        //     payable(ME),
        //     address(0),
        //     adapterParams
        // );

        piNFT.approve(address(migrator), tokenId);
        migrator.migrateNFT{value:amountETH}(
            tokenId,
            ME,
            payable(ME),
            address(0),
            adapterParams
        );

        vm.stopBroadcast();
    }
}