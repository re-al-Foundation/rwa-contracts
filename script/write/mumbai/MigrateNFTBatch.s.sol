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

/// @dev To run: forge script script/write/mumbai/MigrateNFTBatch.s.sol:MigrateNFTBatch --broadcast

/**
 * @title MigrateNFTBatch
 * @author Chase Brown
 * @notice This script allows us to migrate a 3,3+ NFT to a veRWA NFT from Mumbai to a destination chain.
 */
contract MigrateNFTBatch is Script {

    // ~ Variables ~

    CrossChainMigrator public migrator = CrossChainMigrator(0xD42F6Ce9fc98440c518A01749d6fB526CAd52E11);
    LZEndpointMock public endpoint = LZEndpointMock(0xf69186dfBa60DdB133E91E9A4B5673624293d8F8);

    //RWAToken public rwaToken = RWAToken(payable(0xAf960b9B057f59c68e55Ff9aC29966d9bf62b71B));
    //RWAVotingEscrow public veRWA = RWAVotingEscrow(0x297670562a8BcfACBe5c30BBAC5ca7062ac7f652);

    TangibleERC20Mock public tngblToken = TangibleERC20Mock(MUMBAI_TNGBL_TOKEN);
    PassiveIncomeNFT public piNFT = PassiveIncomeNFT(MUMBAI_PI_NFT);

    uint16 public remoteEndpointId = SEPOLIA_LZ_CHAIN_ID_V1;

    uint256 public numTokens = 2;

    address public ADMIN = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    address public ME = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");


    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        uint256[] memory tokenIds = new uint256[](numTokens);
        tokenIds[0] = 4;
        tokenIds[1] = 19;

        uint256[] memory lockedAmounts = new uint256[](numTokens);
        uint256[] memory durations = new uint256[](numTokens);

        uint256[] memory startTime = new uint256[](numTokens);
        uint256[] memory endTime = new uint256[](numTokens);
        uint256[] memory lockedAmount = new uint256[](numTokens);
        uint256[] memory claimed = new uint256[](numTokens);
        uint256[] memory maxPayout = new uint256[](numTokens);

        for (uint i; i < numTokens; ++i) {
            (startTime[i],
            endTime[i],
            lockedAmount[i],
            /** multiplier */,
            claimed[i],
            maxPayout[i]) = piNFT.locks(tokenIds[i]);

            lockedAmounts[i] = (lockedAmount[i] + maxPayout[i]) - claimed[i];
            durations[i] = endTime[i] - startTime[i];

            console2.log("========= V1 =========");
            console2.log("tokenId", tokenIds[i]);
            console2.log("duration left", durations[i]);
            console2.log("lockedAmount", lockedAmount[i]);
            console2.log("claimed", claimed[i]);
            console2.log("maxPayout", maxPayout[i]);
        }

        uint256 amountETH;

        // create adapterParams for custom gas.
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(200000));

        (amountETH,) = migrator.estimateMigrateNFTFee(
            remoteEndpointId,
            abi.encodePacked(ME),
            lockedAmounts,
            durations,
            false,
            adapterParams
        );

        console2.log("estimated fees", amountETH); // 129.864991452257277872

        for (uint i; i < numTokens; ++i) {
            piNFT.approve(address(migrator), tokenIds[i]);
        }
        // migrator.migrateNFTBatch{value:amountETH}(
        //     tokenIds,
        //     ME,
        //     payable(ME),
        //     address(0),
        //     adapterParams
        // );

        vm.stopBroadcast();
    }
}