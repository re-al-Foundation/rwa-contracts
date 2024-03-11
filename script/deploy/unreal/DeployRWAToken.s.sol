// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
// token
import { RWAToken } from "../../../src/RWAToken.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/unreal/DeployRWAToken.s.sol:DeployRWAToken --broadcast --legacy \
    --gas-limit 30000000 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18231 --watch \ 
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv
*/

/**
 * @title DeployRWAToken
 * @author Chase Brown
 * @notice This script deploys the RWA ecosystem to Unreal chain.
 */
contract DeployRWAToken is DeployUtility {

    // ~ Contracts ~

    // core contracts
    RWAToken public rwaToken;
    // proxies
    ERC1967Proxy public rwaTokenProxy;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");
    address public adminAddress = vm.envAddress("DEPLOYER_ADDRESS");

    function setUp() public {
        vm.createSelectFork("https://rpc.unreal-orbit.gelato.digital");
        _setUp("unreal");
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // ----------------
        // Deploy Contracts
        // ----------------

        // Deploy $RWA Token implementation
        rwaToken = new RWAToken();
        // Deploy proxy for $RWA Token
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                adminAddress
            )
        );
        console2.log("RWAToken", address(rwaTokenProxy));
        rwaToken = RWAToken(payable(address(rwaTokenProxy)));


        vm.stopBroadcast();
    }
}