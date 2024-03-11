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
import { RWAVotingEscrow } from "../../../src/governance/RWAVotingEscrow.sol";
// governance
import { VotingEscrowVesting } from "../../../src/governance/VotingEscrowVesting.sol";
import { DelegateFactory } from "../../../src/governance/DelegateFactory.sol";
import { Delegator } from "../../../src/governance/Delegator.sol";
// revenue management
import { RevenueDistributor } from "../../../src/RevenueDistributor.sol";
import { RevenueStreamETH } from "../../../src/RevenueStreamETH.sol";
// migration
import { RealReceiver } from "../../../src/RealReceiver.sol";
// mocks
import { LZEndpointMock } from "../../../test/utils/LZEndpointMock.sol";
import { MarketplaceMock } from "../../../test/utils/MarketplaceMock.sol";
// v1
import { PassiveIncomeNFT } from "../../../src/refs/PassiveIncomeNFT.sol";
import { TangibleERC20Mock } from "../../../test/utils/TangibleERC20Mock.sol";
// uniswap
import { IUniswapV2Router02 } from "../../../src/interfaces/IUniswapV2Router02.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/unreal/DeployToUnreal.s.sol:DeployToUnreal --broadcast --legacy \
    --gas-limit 30000000 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18231 --watch \ 
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv
*/

/**
 * @title DeployToUnreal
 * @author Chase Brown
 * @notice This script deploys the RWA ecosystem to Unreal chain.
 */
contract DeployToUnreal is DeployUtility {

    // ~ Contracts ~

    // core contracts
    RWAVotingEscrow public veRWA;
    RWAToken public rwaToken;
    RoyaltyHandler public royaltyHandler;
    VotingEscrowVesting public vesting;
    DelegateFactory public delegateFactory;
    RevenueDistributor public revDistributor;
    RevenueStreamETH public revStreamETH;
    RealReceiver public receiver;
    // proxies
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public rwaTokenProxy;
    ERC1967Proxy public royaltyHandlerProxy;
    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public delegateFactoryProxy;
    ERC1967Proxy public revDistributorProxy;
    ERC1967Proxy public revStreamETHProxy;
    ERC1967Proxy public receiverProxy;

    // ~ Variables ~

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
        console2.log("RWA", address(rwaTokenProxy));
        rwaToken = RWAToken(payable(address(rwaTokenProxy)));


        // Deploy vesting contract
        vesting = new VotingEscrowVesting();
        // Deploy proxy for vesting contract
        vestingProxy = new ERC1967Proxy(
            address(vesting),
            abi.encodeWithSelector(VotingEscrowVesting.initialize.selector,
                adminAddress // admin address
            )
        );
        console2.log("vesting", address(vestingProxy));
        vesting = VotingEscrowVesting(address(vestingProxy));


        // Deploy veRWA implementation
        veRWA = new RWAVotingEscrow();
        // Deploy proxy for veRWA
        veRWAProxy = new ERC1967Proxy(
            address(veRWA),
            abi.encodeWithSelector(RWAVotingEscrow.initialize.selector,
                address(rwaToken), // RWA token
                address(vesting),  // votingEscrowVesting
                address(0), // LZ endpoint TODO: Set post
                adminAddress // admin address
            )
        );
        console2.log("veRWA", address(veRWAProxy));
        veRWA = RWAVotingEscrow(address(veRWAProxy));


        // // Deploy RealReceiver
        // receiver = new RealReceiver(UNREAL_LZ_ENDPOINT_V1);
        // // Deploy proxy for receiver
        // receiverProxy = new ERC1967Proxy(
        //     address(receiver),
        //     abi.encodeWithSelector(RealReceiver.initialize.selector,
        //         uint16(block.chainid),
        //         address(veRWA),
        //         address(rwaToken),
        //         adminAddress
        //     )
        // );
        // console2.log("receiver", address(receiverProxy));
        // receiver = RealReceiver(address(receiverProxy));


        // Deploy revDistributor contract
        revDistributor = new RevenueDistributor();
        // Deploy proxy for revDistributor
        revDistributorProxy = new ERC1967Proxy(
            address(revDistributor),
            abi.encodeWithSelector(RevenueDistributor.initialize.selector,
                adminAddress,
                address(0), // rev stream ETH
                address(veRWA)
            )
        );
        console2.log("revDistributor", address(revDistributorProxy));
        revDistributor = RevenueDistributor(payable(address(revDistributorProxy)));


        // Deploy royaltyHandler base
        // royaltyHandler = new RoyaltyHandler();
        // // Deploy proxy for royaltyHandler
        // royaltyHandlerProxy = new ERC1967Proxy(
        //     address(royaltyHandler),
        //     abi.encodeWithSelector(RoyaltyHandler.initialize.selector,
        //         adminAddress,
        //         address(revDistributor),
        //         address(rwaToken),
        //         UNREAL_WETH,
        //         UNREAL_SWAP_ROUTER,
        //         UNREAL_QUOTERV2,
        //         UNREAL_BOX_MANAGER
        //     )
        // );
        // console2.log("royaltyHandler", address(royaltyHandlerProxy));
        // royaltyHandler = RoyaltyHandler(payable(address(royaltyHandlerProxy)));


        // Deploy revStreamETH contract
        revStreamETH = new RevenueStreamETH();
        // Deploy proxy for revStreamETH
        revStreamETHProxy = new ERC1967Proxy(
            address(revStreamETH),
            abi.encodeWithSelector(RevenueStreamETH.initialize.selector,
                address(revDistributor),
                address(veRWA),
                adminAddress
            )
        );
        console2.log("revStreamETH", address(revStreamETHProxy));
        revStreamETH = RevenueStreamETH(payable(address(revStreamETHProxy)));


        // Deploy Delegator implementation
        Delegator delegator = new Delegator();
        // Deploy DelegateFactory
        delegateFactory = new DelegateFactory();
        // Deploy DelegateFactory proxy
        delegateFactoryProxy = new ERC1967Proxy(
            address(delegateFactory),
            abi.encodeWithSelector(DelegateFactory.initialize.selector,
                address(veRWA),
                address(delegator),
                adminAddress
            )
        );
        console2.log("delegateFactory", address(delegateFactoryProxy));
        delegateFactory = DelegateFactory(address(delegateFactoryProxy));
        

        // ------
        // Config
        // ------

        // veVesting config
        vesting.setVotingEscrowContract(address(veRWA));

        // veRWA config
        // veRWA.updateEndpointReceiver(address(receiver)); TODO: Set post new deployment

        // RevenueDistributor config
        revDistributor.updateRevenueStream(payable(address(revStreamETH)));
        // add revenue streams
        revDistributor.addRevenueToken(address(rwaToken)); // from RWA buy/sell taxes
        revDistributor.addRevenueToken(UNREAL_DAI); // DAI - bridge yield (ETH too)
        revDistributor.addRevenueToken(UNREAL_MORE); // MORE - Borrowing fees
        revDistributor.addRevenueToken(UNREAL_USTB); // USTB - caviar incentives, basket rent yield, marketplace fees
        // add necessary selectors for swaps
        revDistributor.setSelectorForTarget(UNREAL_SWAP_ROUTER, selector_exactInput); // for V3 swaps with swapRouter

        // RWAToken config
        rwaToken.setVotingEscrowRWA(address(veRWA));
        // rwaToken.setReceiver(address(receiver)); TODO
        rwaToken.excludeFromFees(address(revDistributor), true);
        rwaToken.excludeFromFees(UNREAL_SWAP_ROUTER, true);
        // rwaToken.setRoyaltyHandler(address(royaltyHandler)); TODO: Set post new deployment

        rwaToken.mint(1_000_000 ether); // for testnet testing


        // --------------
        // Save Addresses
        // --------------

        _saveDeploymentAddress("RWAToken", address(rwaToken));
        _saveDeploymentAddress("VotingEscrowVesting", address(vesting));
        _saveDeploymentAddress("RWAVotingEscrow", address(veRWA));
        _saveDeploymentAddress("RealReceiver", address(receiver));
        _saveDeploymentAddress("RevenueDistributor", address(revDistributor));
        _saveDeploymentAddress("RoyaltyHandler", address(royaltyHandler));
        _saveDeploymentAddress("RevenueStreamETH", address(revStreamETH));
        _saveDeploymentAddress("DelegateFactory", address(delegateFactory));


        // -----------------
        // Post-Deploy TODOs
        // -----------------

        // TODO: Create the RWA/WETH pair, initialize, and add liquidity
        // TODO: Set RWA/WETH pair on RWAToken as automatedMarketMakerPair via RwaToken.setAutomatedMarketMakerPair(pair, true);
        // TODO: Create LiquidBox and GaugeV2ALM for RWA/WETH pair -> Set on RoyaltyHandler
        // TODO: Set trusted remote address via CrossChainMigrator.setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver)));
        // TODO: Set trusted remote on receiver via RealReceiver.setTrustedRemoteAddress(sourceEndpointId, abi.encodePacked(address(crossChainMigrator)));
        // TODO: Deploy and set ExactInputWrapper if needed
        // TODO: Set any permissions on any necessary Gelato Function callers

        // TODO: If mainnet, transfer ownership to multisig


        vm.stopBroadcast();
    }
}