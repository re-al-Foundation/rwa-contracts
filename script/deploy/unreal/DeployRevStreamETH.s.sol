// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";
import { RevenueStreamETH } from "../../../src/RevenueStreamETH.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/// @dev To run: forge script script/deploy/unreal/DeployRevStreamETH.s.sol:DeployRevStreamETH --broadcast --verify --legacy -vvvv

/**
 * @title DeployRevStreamETH
 * @author Chase Brown
 * @notice This script deploys a new RevenueStreamETH contract with a new proxy and updates the RevenueDistributor.
 */
contract DeployRevStreamETH is DeployUtility {

    // ~ Contracts ~

    RevenueDistributor public revDistributor;

    address public veRWA = 0x6fa3d2CB3dEBE19e10778F3C3b95A6cDF911fC5B;

    address public adminAddress = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE; // TODO

    RevenueStreamETH public revStreamETH;
    ERC1967Proxy public revStreamETHProxy;

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");
        revDistributor = RevenueDistributor(payable(_loadDeploymentAddress("RevenueDistributor")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        // deploy implementation
        revStreamETH = new RevenueStreamETH();
        console2.log("revStreamETH Implementation", address(revStreamETH)); // 0xA7337e01FB60B4b144cb4ce106101FDe6E9eCf52

        // deploy proxy
        revStreamETHProxy = new ERC1967Proxy(
            address(revStreamETH),
            abi.encodeWithSelector(RevenueStreamETH.initialize.selector,
                address(revDistributor),
                veRWA,
                adminAddress
            )
        );
        console2.log("revStreamETH", address(revStreamETHProxy)); // 0xeDfe244aBf03999DdAEE52E2D3E61d27517708a8
        revStreamETH = RevenueStreamETH(payable(address(revStreamETHProxy)));

        // update RevenueDistributor
        revDistributor.updateRevenueStream(payable(address(revStreamETH)));

        vm.stopBroadcast();
    }
}