// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";
import { RevenueStream } from "../../../src/RevenueStream.sol";
import { RWAToken } from "../../../src/RWAToken.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/unreal/DeployRevStream.s.sol:DeployRevStream --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \ 
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api
*/

/**
 * @title DeployRevStream
 * @author Chase Brown
 * @notice This script deploys a new RevenueStreamETH contract with a new proxy and updates the RevenueDistributor.
 */
contract DeployRevStream is DeployUtility {

    // ~ Contracts ~

    RevenueDistributor public revDistributor;
    RWAToken public rwaToken;
    address public veRWA;

    address public revStreamToken;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");
    address public adminAddress = vm.envAddress("DEPLOYER_ADDRESS");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");
        revDistributor = RevenueDistributor(payable(_loadDeploymentAddress("RevenueDistributor")));
        veRWA = _loadDeploymentAddress("RWAVotingEscrow");
        rwaToken = RWAToken(_loadDeploymentAddress("RWAToken"));

        revStreamToken = address(rwaToken); // TODO
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        // Deploy revStream contract
        RevenueStream revStream = new RevenueStream(revStreamToken);

        // Deploy proxy for revStream
        ERC1967Proxy revStreamProxy = new ERC1967Proxy(
            address(revStream),
            abi.encodeWithSelector(RevenueStream.initialize.selector,
                address(revDistributor),
                address(veRWA),
                adminAddress
            )
        );
        revStream = RevenueStream(address(revStreamProxy));

        // update RevenueDistributor
        revDistributor.setRevenueStreamForToken(revStreamToken, address(revStream));

        // exclude revStream from fees if token == RWA
        rwaToken.excludeFromFees(address(revStream), true);

        // save address in JSON
        _saveDeploymentAddress("RevenueStreamRWA", address(revStream));

        vm.stopBroadcast();
    }
}