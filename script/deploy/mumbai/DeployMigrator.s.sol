// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { CrossChainMigrator } from "../../../src/CrossChainMigrator.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/mumbai/DeployMigrator.s.sol:DeployMigrator --broadcast --verify -vvvv
/// @dev To verify: forge verify-contract <CONTRACT_ADDRESS> --chain-id 80001 --watch src/CrossChainMigrator.sol:CrossChainMigrator --verifier etherscan

/**
 * @title DeployMigrator
 * @author Chase Brown
 * @notice This script deploys CrossChainMigrator to Mumbai
 */
contract DeployMigrator is Script {

    // ~ Contracts ~

    // core contracts
    CrossChainMigrator public migrator;
    
    // proxies
    ERC1967Proxy public migratorProxy;

    // ~ Variables ~

    address public passiveIncomeNFTV1 = MUMBAI_PI_NFT;
    address public tngblToken = MUMBAI_TNGBL_TOKEN;

    address public localEndpoint = MUMBAI_LZ_ENDPOINT_V1;
    uint16 public remoteEndpointId = UNREAL_CHAINID;

    address public receiver = 0x36b6240FD63D5A4fb095AbF7cC8476659C76071C; // unreal
    //address public receiver = 0x5aE75eb64478067e537F0534Fc6cE4dAf464E84d; // sepolia
    //address public receiver = 0x3dddcbbF364bDD8C61274Fdbb8F0821476CEA5d1; // bsc_testnet
    //address public realReceiverRWA = 0x422EA457842aB25d7287dDfe2Bc84317d1bf61d0; // goerli

    address public ADMIN = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");


    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy CrossChainMigrator
        migrator = new CrossChainMigrator(localEndpoint); /// @dev: forge verify-contract 0xE58CCEEC2E47A93182A6DF6F5Bb4B6F92491Cdb8 --chain-id 80001 --watch src/CrossChainMigrator.sol:CrossChainMigrator --verifier etherscan --constructor-args $(cast abi-encode "constructor(address)" 0xf69186dfBa60DdB133E91E9A4B5673624293d8F8)

        // Deploy proxy for migrator
        migratorProxy = new ERC1967Proxy(
            address(migrator),
            abi.encodeWithSelector(CrossChainMigrator.initialize.selector,
                passiveIncomeNFTV1,  // LOCAL ADDRESS 1 -> 3,3+ NFT
                tngblToken,          // LOCAL ADDRESS 2 -> $TNGBL
                receiver,            // REMOTE ADDRESS 1 -> RECEIVER
                remoteEndpointId,    // REMOTE CHAIN ID -> now endpoint ID
                ADMIN
            )
        );


        // ~ Config ~

        CrossChainMigrator(address(migratorProxy)).setMinDstGas(remoteEndpointId, 0, 200000);
        CrossChainMigrator(address(migratorProxy)).setMinDstGas(remoteEndpointId, 1, 200000);
        CrossChainMigrator(address(migratorProxy)).setMinDstGas(remoteEndpointId, 2, 200000);
        CrossChainMigrator(address(migratorProxy)).setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver)));

        CrossChainMigrator(address(migratorProxy)).toggleMigration();


        // ~ Logs ~

        console2.log("1a. Migrator       =", address(migratorProxy));
        console2.log("1b. Migrator (Imp) =", address(migrator));

        vm.stopBroadcast();
    }
}

// mumbai -> unreal
// == Logs ==
//   1a. Migrator       = 0x7b480d219F68dA5c630534de8bFD0219Bd7BCFaB
//   1b. Migrator (Imp) = 0xE58CCEEC2E47A93182A6DF6F5Bb4B6F92491Cdb8

// mumbai -> sepolia
// == Logs ==
//   1a. Migrator       = 0xD42F6Ce9fc98440c518A01749d6fB526CAd52E11
//   1b. Migrator (Imp) = 0xe988F47f227c7118aeB0E2954Ce6eed8822303d0