// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { AutomatedDelegatee } from "../../../src/helpers/AutomatedDelegatee.sol";

/** 
    @dev To run: 
    forge script script/deploy/mainnet/DeployAutomatedDelegatee.s.sol:DeployAutomatedDelegatee --broadcast --legacy \
    --gas-estimate-multiplier 600 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv
*/

/**
 * @title DeployAutomatedDelegatee
 * @author Chase Brown
 * @notice This script deploys AutomatedDelegatee to Re.al
 */
contract DeployAutomatedDelegatee is DeployUtility {

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    address public ADMIN = 0x946C569791De3283f33372731d77555083c329da; // TODO: Verify
    address public DELEGATEE = 0x0E140Adb0a70569f0A8b3d48ab8c8c580939a120; // TODO: Verify

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // deploy AutomatedDelegatee
        AutomatedDelegatee automatedDelegatee = new AutomatedDelegatee();
        // deploy proxy
        ERC1967Proxy automatedDelegateeProxy = new ERC1967Proxy(
            address(automatedDelegatee),
            abi.encodeWithSelector(AutomatedDelegatee.initialize.selector,
                ADMIN,
                DELEGATEE
            )
        );
        automatedDelegatee = AutomatedDelegatee(payable(address(automatedDelegateeProxy)));

        vm.stopBroadcast();
    }
}