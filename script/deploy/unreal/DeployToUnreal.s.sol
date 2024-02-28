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

/// @dev To run: forge script script/deploy/unreal/DeployToUnreal.s.sol:DeployToUnreal --broadcast --legacy --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv
/// @dev To verify: forge verify-contract <CONTRACT_ADDRESS> --chain-id 18231 --watch src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api

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
    Delegator public delegator;

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

    address public layerZeroUnrealEndpoint = address(0); // TODO

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    address public adminAddress = 0x1F834C1a259AC590D61fd668fCb5E333E08614CE; // TODO

    bytes4 public selector_swapExactTokensForETH =
        bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)"));
    bytes4 public selector_exactInput = 
        bytes4(keccak256("multicall(bytes[])"));

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        _setUp("unreal");
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // ~ Deploy Contracts ~

        // (1) Deploy $RWA Token implementation
        rwaToken = new RWAToken();
        console2.log("RWA Implementation", address(rwaToken));

        // (2) Deploy proxy for $RWA Token
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                adminAddress
            )
        );
        console2.log("RWA", address(rwaTokenProxy));
        rwaToken = RWAToken(payable(address(rwaTokenProxy)));

        // (3) Deploy vesting contract
        vesting = new VotingEscrowVesting();
        console2.log("vesting Implementation", address(vesting));

        // (4) Deploy proxy for vesting contract
        vestingProxy = new ERC1967Proxy(
            address(vesting),
            abi.encodeWithSelector(VotingEscrowVesting.initialize.selector,
                adminAddress // admin address
            )
        );
        console2.log("vesting", address(vestingProxy));
        vesting = VotingEscrowVesting(address(vestingProxy));

        // (5) Deploy veRWA implementation
        veRWA = new RWAVotingEscrow();
        console2.log("veRWA Implementation", address(veRWA));

        // (6) Deploy proxy for veRWA
        veRWAProxy = new ERC1967Proxy(
            address(veRWA),
            abi.encodeWithSelector(RWAVotingEscrow.initialize.selector,
                address(rwaToken), // RWA token
                address(vesting),  // votingEscrowVesting
                layerZeroUnrealEndpoint, // LZ endpoint
                adminAddress // admin address
            )
        );
        console2.log("veRWA", address(veRWAProxy));
        veRWA = RWAVotingEscrow(address(veRWAProxy));

        // // (7) Deploy RealReceiver
        // receiver = new RealReceiver(address(endpoint));
        // console2.log("receiver Implementation", address(receiver));

        // // (8) Deploy proxy for receiver
        // receiverProxy = new ERC1967Proxy(
        //     address(receiver),
        //     abi.encodeWithSelector(RealReceiver.initialize.selector,
        //         uint16(block.chainid),
        //         address(veRWA),
        //         address(rwaToken),
        //         ADMIN
        //     )
        // );
        // console2.log("receiver", address(receiverProxy));
        // receiver = RealReceiver(address(receiverProxy));

        // (9) Deploy revDistributor contract
        revDistributor = new RevenueDistributor();
        console2.log("revDistributor Implementation", address(revDistributor));

        // (10) Deploy proxy for revDistributor
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

        // (11) Deploy royaltyHandler base
        royaltyHandler = new RoyaltyHandler();
        console2.log("royaltyHandler Implementation", address(royaltyHandler));

        // (12) Deploy proxy for royaltyHandler
        royaltyHandlerProxy = new ERC1967Proxy(
            address(royaltyHandler),
            abi.encodeWithSelector(RoyaltyHandler.initialize.selector,
                adminAddress,
                address(revDistributor),
                address(rwaToken),
                UNREAL_WETH,
                UNREAL_SWAP_ROUTER,
                UNREAL_QUOTERV2
            )
        );
        console2.log("royaltyHandler", address(royaltyHandlerProxy));
        royaltyHandler = RoyaltyHandler(payable(address(royaltyHandlerProxy)));

        // (13) Deploy revStreamETH contract
        revStreamETH = new RevenueStreamETH();
        console2.log("revStreamETH Implementation", address(revStreamETH));

        // (14) Deploy proxy for revStreamETH
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

        // (15) Deploy Delegator implementation
        delegator = new Delegator();
        console2.log("delegator Implementation", address(delegator));

        // (16) Deploy DelegateFactory
        delegateFactory = new DelegateFactory();
        console2.log("delegateFactory Implementation", address(delegateFactory));

        // (17) Deploy DelegateFactory proxy
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
        
        // ~ Config ~

        // (18) set votingEscrow on vesting contract
        vesting.setVotingEscrowContract(address(veRWA));

        // (19) RevenueDistributor config
        // (19a) grant DISTRIBUTOR_ROLE to Gelato functions
        //revDistributor.grantRole(DISTRIBUTOR_ROLE, GELATO); // for gelato functions to distribute TODO
        // (19b) add revStream contract
        revDistributor.updateRevenueStream(payable(address(revStreamETH)));
        // (19c) add revenue streams
        revDistributor.addRevenueToken(address(rwaToken)); // from RWA buy/sell taxes
        revDistributor.addRevenueToken(UNREAL_DAI); // DAI - bridge yield (ETH too)
        //revDistributor.addRevenueToken(address(0)); // MORE - Borrowing fees (note not deployed) TODO
        revDistributor.addRevenueToken(UNREAL_USTB); // USTB - caviar incentives, basket rent yield, marketplace fees
        // (19d) add necessary selectors for swaps
        //revDistributor.setSelectorForTarget(UNREAL_UNIV2_ROUTER, selector_swapExactTokensForETH); // for RWA -> ETH swaps
        revDistributor.setSelectorForTarget(UNREAL_SWAP_ROUTER, selector_exactInput); // for V3 swaps with swapRouter

        // (20) pair manager must create RWA/WETH pair
        //      TODO: Have pearlV2 pair manager create the RWA/WETH pair
        //vm.startPrank(UNREAL_PAIR_MANAGER);
        //address pair = IPearlV2PoolFactory(UNREAL_PEARLV2_FACTORY).createPool(address(rwaToken), WETH, 100);

        // (21) RWAToken config
        // (21a) TODO: set pair
        // rwaToken.setAutomatedMarketMakerPair(pair);
        // (21b) set veRWA
        rwaToken.setVotingEscrowRWA(address(veRWA)); // for RWAVotingEscrow:migrate
        // set RealReceiver
        // rwaToken.setReceiver(address(this)); // for testing TODO
        // (21c) whitelist
        rwaToken.excludeFromFees(address(revDistributor), true);
        // (21d) set royalty handler
        rwaToken.setRoyaltyHandler(address(royaltyHandler));

        rwaToken.mint(1_000_000 ether); // for testnet testing

        // (22) TODO: create the RWA/WETH pool

        vm.stopBroadcast();
    }
}

// == Logs ==
//   RWA 0xC9f2381e3f22e912e34033734977B58544518BFA
//   vesting 0xC176C092BE752E1193E48Ac6B0bBA69Ff30ab201
//   veRWA 0x7c501F5f0A23Dc39Ac43d4927ff9f7887A01869B
//   revDistributor 0xd0A610E26732aA01960BE87598106240a93b6595
//   revStreamETH 0x541c058d0D7Ab8474Ea10fb090677FaD992256d9
//   delegateFactory 0xAf960b9B057f59c68e55Ff9aC29966d9bf62b71B

// == Logs ==
//   RWA 0x909Fd75Ce23a7e61787FE2763652935F92116461
//   vesting 0xEE1643c7ED4e195893025df09E757Cc526F757F9
//   veRWA 0x6fa3d2CB3dEBE19e10778F3C3b95A6cDF911fC5B
//   revDistributor 0xa443Bf2fCA2119bFDb97Bc01096fBC4F1546c8Ae
//   revStreamETH 0x4f233dbA3E21D762AeAf7c81103A15A8980706B3
//   delegateFactory 0x6Ca53fe01D1007Ae89Ad730F5c66515819fD5145

// == Logs ==
//   RWA Implementation 0x8203bC5734B2d70287419F41eEd24878c9c006Fc
//   RWA 0xdb2664cc9C9a16a8e0608f6867bD67158AF59397
//   vesting Implementation 0xFd502b52B5B5b6ED097b307F168d296C4F7189b1
//   vesting 0x0f3be26c5eF6451823BD816B68E9106C8B65A5DA
//   veRWA Implementation 0x524BB37efDFcD2015fee2b41236579237db4CceE
//   veRWA 0x2afD4dC7649c2545Ab1c97ABBD98487B6006f7Ae
//   revDistributor Implementation 0xECB70e89638b42a5e9eC7a51E5FD229c4b40ed2A
//   revDistributor 0x56843df02d5A230929B3A572ACEf5048d5dB76db
//   royaltyHandler Implementation 0x5100990DC69Bc2A41e5C3409B3e41B40F606089a
//   royaltyHandler 0x138A0c41f9a8b99a07cA3B4cABc711422B7d8EAB
//   revStreamETH Implementation 0xB6C3f7dE6bf3137F30c64c77C691BC0CA889B3da
//   revStreamETH 0x5d79976Be5814FDC8d5199f0ba7fC3764082D635
//   delegator Implementation 0x8f9d60D80EE3F6c7e47b3a937823F28B75AB75ab
//   delegateFactory Implementation 0x6aA4A24Dd0624f24A6deD6435351bcb4Beb3CD20
//   delegateFactory 0xe988F47f227c7118aeB0E2954Ce6eed8822303d0