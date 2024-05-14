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
import { RevenueStream } from "../../../src/RevenueStream.sol";
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
// periphery
import { VotingEscrowRWAAPI } from "../../../src/helpers/VotingEscrowRWAAPI.sol";

//helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/unreal/DeployToUnreal.s.sol:DeployToUnreal --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \ 
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api
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
    Delegator public delegator;
    DelegateFactory public delegateFactory;
    RevenueDistributor public revDistributor;
    RevenueStreamETH public revStreamETH;
    RevenueStream public revStreamRWA;
    RealReceiver public receiver;
    // helper
    VotingEscrowRWAAPI public api;

    // ~ For RoyaltyHandler ~

    address public WETH9 = 0x0C68a3C11FB3550e50a4ed8403e873D367A8E361;
    address public SWAP_ROUTER = 0x0a42599e0840aa292C76620dC6d4DAfF23DB5236;
    address public QUOTER = 0x6B6dA57BA5E77Ed5504Fe778449056fbb18020D5;
    address public BOXMANAGER = 0xce777A3e9D2F6B80D4Ff2297346Ef572636d8FCE;

    address public USTB = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    address public PEARL = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;

    // ~ Variables ~

    address public passiveIncomeNFTV1 = POLYGON_PI_NFT;
    address public tngblToken = POLYGON_TNGBL_TOKEN;

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
        ERC1967Proxy rwaTokenProxy = new ERC1967Proxy(
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
        ERC1967Proxy vestingProxy = new ERC1967Proxy(
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
        ERC1967Proxy veRWAProxy = new ERC1967Proxy(
            address(veRWA),
            abi.encodeWithSelector(RWAVotingEscrow.initialize.selector,
                address(rwaToken), // RWA token
                address(vesting),  // votingEscrowVesting
                address(0), // Set post
                adminAddress // admin address
            )
        );
        console2.log("veRWA", address(veRWAProxy));
        veRWA = RWAVotingEscrow(address(veRWAProxy));


        // Deploy RealReceiver
        receiver = new RealReceiver(UNREAL_LZ_ENDPOINT_V1);
        // Deploy proxy for receiver
        ERC1967Proxy receiverProxy = new ERC1967Proxy(
            address(receiver),
            abi.encodeWithSelector(RealReceiver.initialize.selector,
                uint16(block.chainid),
                address(veRWA),
                address(rwaToken),
                adminAddress
            )
        );
        console2.log("receiver", address(receiverProxy));
        receiver = RealReceiver(address(receiverProxy));


        // Deploy revDistributor contract
        revDistributor = new RevenueDistributor();
        // Deploy proxy for revDistributor
        ERC1967Proxy revDistributorProxy = new ERC1967Proxy(
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
        royaltyHandler = new RoyaltyHandler();
        // Deploy proxy for royaltyHandler
        ERC1967Proxy royaltyHandlerProxy = new ERC1967Proxy(
            address(royaltyHandler),
            abi.encodeWithSelector(RoyaltyHandler.initialize.selector,
                adminAddress,
                address(revDistributor),
                address(rwaToken),
                WETH9,
                SWAP_ROUTER,
                UNREAL_BOX_MANAGER,
                UNREAL_TNGBLV3ORACLE
            )
        );
        console2.log("royaltyHandler", address(royaltyHandlerProxy));
        royaltyHandler = RoyaltyHandler(payable(address(royaltyHandlerProxy)));


        // Deploy revStreamETH contract
        revStreamETH = new RevenueStreamETH();
        // Deploy proxy for revStreamETH
        ERC1967Proxy revStreamETHProxy = new ERC1967Proxy(
            address(revStreamETH),
            abi.encodeWithSelector(RevenueStreamETH.initialize.selector,
                address(revDistributor),
                address(veRWA),
                adminAddress
            )
        );
        console2.log("revStreamETH", address(revStreamETHProxy));
        revStreamETH = RevenueStreamETH(payable(address(revStreamETHProxy)));

        // Deploy revStreamRWA contract
        revStreamRWA = new RevenueStream(address(rwaToken));

        // Deploy proxy for revStreamRWA
        ERC1967Proxy revStreamProxy = new ERC1967Proxy(
            address(revStreamRWA),
            abi.encodeWithSelector(RevenueStream.initialize.selector,
                address(revDistributor),
                address(veRWA),
                adminAddress
            )
        );
        console2.log("revStreamETH", address(revStreamProxy));
        revStreamRWA = RevenueStream(address(revStreamProxy));


        // Deploy Delegator implementation
        delegator = new Delegator();
        // Deploy DelegateFactory
        delegateFactory = new DelegateFactory();
        // Deploy DelegateFactory proxy
        ERC1967Proxy delegateFactoryProxy = new ERC1967Proxy(
            address(delegateFactory),
            abi.encodeWithSelector(DelegateFactory.initialize.selector,
                address(veRWA),
                address(delegator),
                adminAddress
            )
        );
        console2.log("delegateFactory", address(delegateFactoryProxy));
        delegateFactory = DelegateFactory(address(delegateFactoryProxy));


        // Deploy api
        api = new VotingEscrowRWAAPI();
        // Deploy proxy for api
        ERC1967Proxy apiProxy = new ERC1967Proxy(
            address(api),
            abi.encodeWithSelector(VotingEscrowRWAAPI.initialize.selector,
                adminAddress, // admin
                address(veRWA),
                address(vesting),
                address(revStreamETH)
            )
        );
        console2.log("api", address(apiProxy));
        api = VotingEscrowRWAAPI(address(apiProxy));
        

        // ------
        // Config
        // ------

        // veVesting config
        vesting.setVotingEscrowContract(address(veRWA));

        // veRWA config
        veRWA.updateEndpointReceiver(address(receiver));

        // RevenueDistributor config
        // add revenue streams
        revDistributor.addRevenueToken(address(rwaToken)); // from RWA buy/sell taxes
        revDistributor.addRevenueToken(UNREAL_DAI); // DAI - bridge yield (ETH too)
        revDistributor.addRevenueToken(UNREAL_MORE); // MORE - Borrowing fees
        revDistributor.addRevenueToken(USTB); // USTB - caviar incentives, basket rent yield, marketplace fees
        // add necessary selectors for swaps
        revDistributor.setSelectorForTarget(SWAP_ROUTER, bytes4(keccak256("multicall(bytes[])")), true); // TODO: Confirm the real targets
        // add Revenue streams
        revDistributor.updateRevenueStream(payable(address(revStreamETH)));
        revDistributor.setRevenueStreamForToken(address(rwaToken), address(revStreamRWA));

        // revStreamETH config
        // TODO: Opt out of rebase on USTB

        // RWAToken config
        rwaToken.setVotingEscrowRWA(address(veRWA));
        rwaToken.setReceiver(address(receiver));
        rwaToken.excludeFromFees(address(revDistributor), true);
        //rwaToken.excludeFromFees(SWAP_ROUTER, true);
        rwaToken.setRoyaltyHandler(address(royaltyHandler));
        rwaToken.excludeFromFees(address(revStreamRWA), true);
        
        // RoyaltyHandler config
        royaltyHandler.setPearl(PEARL);

        // RealReceiver config
        // TODO: Set trusted remote address via CrossChainMigrator.setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver)));
        // TODO: Also set trusted remote on receiver via RealReceiver.setTrustedRemoteAddress(sourceEndpointId, abi.encodePacked(address(crossChainMigrator)));


        rwaToken.mint(500_000 ether); // for testnet testing
        rwaToken.mintFor(0x54792B36bf490FC53aC56dB33fD3953B56DF6baF, 500_000 ether); // for testing -> Milica


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
        _saveDeploymentAddress("RevenueStreamRWA", address(revStreamRWA));
        _saveDeploymentAddress("DelegateFactory", address(delegateFactory));
        _saveDeploymentAddress("API", address(api));


        // -----------------
        // Post-Deploy TODOs
        // -----------------

        // TODO: Create the RWA/WETH pair, initialize, and add liquidity
        // TODO: Set RWA/WETH pair on RWAToken as automatedMarketMakerPair via RwaToken.setAutomatedMarketMakerPair(pair, true);
        // TODO: Set RWA/WETH fee on RoyaltyHandler
        // TODO: Create LiquidBox and GaugeV2ALM for RWA/WETH pair -> Set on RoyaltyHandler
        // TODO: Set trusted remote address via CrossChainMigrator.setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver))); ✅
        // TODO: Set trusted remote on receiver via RealReceiver.setTrustedRemoteAddress(sourceEndpointId, abi.encodePacked(address(crossChainMigrator))); ✅
        // TODO: Deploy and set ExactInputWrapper if needed
        // TODO: Set any permissions on any necessary Gelato Function callers

        // TODO: If mainnet, transfer ownership to multisig


        vm.stopBroadcast();
    }
}