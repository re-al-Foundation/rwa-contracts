// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Script.sol";
import { DeployUtility } from "../../base/DeployUtility.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
// token
import { RWAToken } from "../../../src/RWAToken.sol";
import { RoyaltyHandler } from "../../../src/RoyaltyHandler.sol";
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/unreal/DeployRoyaltyHandler.s.sol:DeployRoyaltyHandler --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \ 
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv
*/

/**
 * @title DeployRoyaltyHandler
 * @author Chase Brown
 * @notice This script deploys the RoyaltyHandler contract to Unreal.
 */
contract DeployRoyaltyHandler is DeployUtility {

    // ~ Contracts ~

    // core contracts
    RWAToken public rwaToken;
    RevenueDistributor public revDistributor;

    // ~ Variables ~

    address public BOXMANAGER = 0xce777A3e9D2F6B80D4Ff2297346Ef572636d8FCE;

    address public USTB = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;

    address public passiveIncomeNFTV1 = POLYGON_PI_NFT;
    address public tngblToken = POLYGON_TNGBL_TOKEN;

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");
    address public adminAddress = vm.envAddress("DEPLOYER_ADDRESS");

    bytes4 public selector_swapExactTokensForETH =
        bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"));
    bytes4 public selector_exactInput = 
        bytes4(keccak256("multicall(bytes[])"));

    function setUp() public {
        vm.createSelectFork("https://rpc.unreal-orbit.gelato.digital");
        _setUp("unreal");

        rwaToken = RWAToken(payable(_loadDeploymentAddress("RWAToken")));
        revDistributor = RevenueDistributor(payable(_loadDeploymentAddress("RevenueDistributor")));
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy royaltyHandler base
        RoyaltyHandler royaltyHandler = new RoyaltyHandler();
        // Deploy proxy for royaltyHandler
        ERC1967Proxy royaltyHandlerProxy = new ERC1967Proxy(
            address(royaltyHandler),
            abi.encodeWithSelector(RoyaltyHandler.initialize.selector,
                adminAddress,
                address(revDistributor),
                address(rwaToken),
                UNREAL_WETH,
                UNREAL_SWAP_ROUTER,
                UNREAL_BOX_MANAGER,
                UNREAL_TNGBLV3ORACLE
            )
        );
        console2.log("royaltyHandler", address(royaltyHandlerProxy));
        royaltyHandler = RoyaltyHandler(payable(address(royaltyHandlerProxy)));

        // TODO: setPearl

        rwaToken.setRoyaltyHandler(address(royaltyHandler));

        revDistributor.setSelectorForTarget(UNREAL_SWAP_ROUTER, bytes4(keccak256("multicall(bytes[])")), true);
        rwaToken.excludeFromFees(UNREAL_SWAP_ROUTER, true);

        _saveDeploymentAddress("RoyaltyHandler", address(royaltyHandler));

        vm.stopBroadcast();
    }
}