// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { CrossChainMigrator } from "../../../src/CrossChainMigrator.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/mumbai/DeployMigrator.s.sol:DeployMigrator --broadcast --verify -vvvv

    @dev To verify manually: 
    forge verify-contract 0xE58CCEEC2E47A93182A6DF6F5Bb4B6F92491Cdb8 --chain-id 80001 --watch \
    src/CrossChainMigrator.sol:CrossChainMigrator --verifier etherscan \
    --constructor-args $(cast abi-encode "constructor(address)" 0xf69186dfBa60DdB133E91E9A4B5673624293d8F8)
*/

/**
 * @title DeployMigrator
 * @author Chase Brown
 * @notice This script deploys CrossChainMigrator to Mumbai
 */
contract DeployMigrator is Script {

    // ~ Variables ~

    address public localEndpoint = MUMBAI_LZ_ENDPOINT_V1;
    uint16 public remoteEndpointId = UNREAL_CHAINID;

    address public receiver = 0x12c211824d3413fE0b2671a3C27e779c21a10c20; // unreal
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
        CrossChainMigrator migrator = new CrossChainMigrator(localEndpoint); /// @dev: forge verify-contract 0xE58CCEEC2E47A93182A6DF6F5Bb4B6F92491Cdb8 --chain-id 80001 --watch src/CrossChainMigrator.sol:CrossChainMigrator --verifier etherscan --constructor-args $(cast abi-encode "constructor(address)" 0xf69186dfBa60DdB133E91E9A4B5673624293d8F8)

        // Deploy proxy for migrator
        ERC1967Proxy migratorProxy = new ERC1967Proxy(
            address(migrator),
            abi.encodeWithSelector(CrossChainMigrator.initialize.selector,
                MUMBAI_PI_NFT,      // LOCAL ADDRESS 1 -> 3,3+ NFT
                MUMBAI_PI_CALC,      // piCalc NFT address
                MUMBAI_TNGBL_TOKEN,  // LOCAL ADDRESS 2 -> $TNGBL
                receiver,            // REMOTE ADDRESS 1 -> RECEIVER
                remoteEndpointId,    // REMOTE CHAIN ID -> now endpoint ID
                ADMIN
            )
        );
        migrator = CrossChainMigrator(address(migratorProxy));


        // ~ Config ~

        CrossChainMigrator(address(migrator)).setMinDstGas(remoteEndpointId, 0, 200000);
        CrossChainMigrator(address(migrator)).setMinDstGas(remoteEndpointId, 1, 200000);
        CrossChainMigrator(address(migrator)).setMinDstGas(remoteEndpointId, 2, 200000);

        CrossChainMigrator(address(migrator)).setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver)));

        CrossChainMigrator(address(migrator)).toggleMigration();


        // ~ Logs ~

        console2.log("Migrator =", address(migrator));

        vm.stopBroadcast();
    }
}