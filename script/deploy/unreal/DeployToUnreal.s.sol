// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
// token
import { RWAToken } from "../../../src/RWAToken.sol";
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

/// @dev To run: forge script script/deploy/unreal/DeployToUnreal.s.sol:DeployToUnreal --broadcast --verify --legacy -vvvv
/// @dev To verify: forge verify-contract <CONTRACT_ADDRESS> --chain-id 18231 --watch src/Contract.sol:Contract --verifier blockscout --verifier-url https://unreal.blockscout.com/api

/**
 * @title DeployToUnreal
 * @author Chase Brown
 * @notice This script deploys the RWA ecosystem to Unreal chain.
 */
contract DeployToUnreal is Script {

    // ~ Contracts ~

    // core contracts
    RWAVotingEscrow public veRWA;
    RWAToken public rwaToken;

    VotingEscrowVesting public vesting;
    DelegateFactory public delegateFactory;
    Delegator public delegator;

    RevenueDistributor public revDistributor;
    RevenueStreamETH public revStreamETH;

    RealReceiver public receiver;
    
    // proxies
    ERC1967Proxy public veRWAProxy;
    ERC1967Proxy public rwaTokenProxy;

    ERC1967Proxy public vestingProxy;
    ERC1967Proxy public delegateFactoryProxy;

    ERC1967Proxy public revDistributorProxy;
    ERC1967Proxy public revStreamETHProxy;

    ERC1967Proxy public receiverProxy;

    // ~ Variables ~

    address public WETH;
    IUniswapV2Router02 public uniswapV2Router = IUniswapV2Router02(UNREAL_UNIV2_ROUTER);

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
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        WETH = uniswapV2Router.WETH();

        // ~ Deploy Contracts ~

        // (1) Deploy $RWA Token implementation
        rwaToken = new RWAToken();
        console2.log("RWA Implementation", address(rwaToken));

        // (2) Deploy proxy for $RWA Token
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaToken),
            abi.encodeWithSelector(RWAToken.initialize.selector,
                adminAddress,             // admin address
                address(uniswapV2Router), // uniswap v2 router
                address(0)  // TODO: set RevenueDistributor post-deploy
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

        // (11) Deploy revStreamETH contract
        revStreamETH = new RevenueStreamETH();
        console2.log("revStreamETH Implementation", address(revStreamETH));

        // (12) Deploy proxy for revStreamETH
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

        // (13) Deploy Delegator implementation
        delegator = new Delegator();
        console2.log("delegator Implementation", address(delegator));

        // (14) Deploy DelegateFactory
        delegateFactory = new DelegateFactory();
        console2.log("delegateFactory Implementation", address(delegateFactory));

        // (15) Deploy DelegateFactory proxy
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

        // (14) set votingEscrow on vesting contract
        vesting.setVotingEscrowContract(address(veRWA));

        // (15) RevenueDistributor config
        // (15a) grant DISTRIBUTOR_ROLE to Gelato functions
        //revDistributor.grantRole(DISTRIBUTOR_ROLE, GELATO); // for gelato functions to distribute TODO
        // (15b) add revStream contract
        revDistributor.updateRevenueStream(payable(address(revStreamETH)));
        // (15c) add revenue streams
        revDistributor.addRevenueToken(address(rwaToken)); // from RWA buy/sell taxes
        revDistributor.addRevenueToken(UNREAL_DAI); // DAI - bridge yield (ETH too)
        //revDistributor.addRevenueToken(address(0)); // MORE - Borrowing fees (note not deployed) TODO
        revDistributor.addRevenueToken(UNREAL_USTB); // USTB - caviar incentives, basket rent yield, marketplace fees
        // (15d) add necessary selectors for swaps
        revDistributor.setSelectorForTarget(UNREAL_UNIV2_ROUTER, selector_swapExactTokensForETH); // for RWA -> ETH swaps
        revDistributor.setSelectorForTarget(UNREAL_SWAP_ROUTER, selector_exactInput); // for V3 swaps with swapRouter

        // (16) pair manager must create RWA/WETH pair
        //      TODO: Have pearl UniV2 pair manager create the RWA/WETH pair
        //vm.startPrank(UNREAL_PAIR_MANAGER);
        //address pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(rwaToken), WETH);

        // (17) RWAToken config
        // (17a) TODO: set uniswap pair
        // rwaToken.setUniswapV2Pair(pair);
        // (17b) Grant roles
        rwaToken.grantRole(MINTER_ROLE, address(veRWA)); // for RWAVotingEscrow:migrate
        rwaToken.grantRole(BURNER_ROLE, address(veRWA)); // for RWAVotingEscrow early burn fee
        // (17c) whitelist
        rwaToken.excludeFromFees(address(veRWA), true);
        rwaToken.excludeFromFees(address(revDistributor), true);
        // (17d) set revenue distributor
        rwaToken.setRevenueDistributor(address(revDistributor));

        // (18) TODO: create the RWA/WETH pool

        vm.stopBroadcast();
    }
}

// == Logs ==
//   RWA Implementation 0xfA609181778B8494c680544A14De4eDa35F51D72 ✅
//   RWA 0xC9f2381e3f22e912e34033734977B58544518BFA ✅
//   vesting Implementation 0x3132BD707C017B7EC1Ff9f4C99C2ca0033747F35 ✅
//   vesting 0xC176C092BE752E1193E48Ac6B0bBA69Ff30ab201 ✅
//   veRWA Implementation 0xC556F5307D57163478EF56dB64C658D8879E4aa2 ✅
//   veRWA 0x7c501F5f0A23Dc39Ac43d4927ff9f7887A01869B ✅
//   revDistributor Implementation 0x6a2EA328DE836222BFC7bEA20C348856d2770a99 ✅
//   revDistributor 0xd0A610E26732aA01960BE87598106240a93b6595 ✅
//   revStreamETH Implementation 0x4a18685C617eac56EDF5F62227f2E8223E45Ff38 ✅
//   revStreamETH 0x541c058d0D7Ab8474Ea10fb090677FaD992256d9 ✅
//   delegator Implementation 0xBebe0cF3b3C881265803018fF211aBfc96FB3B61 ✅
//   delegateFactory Implementation 0x95A3Af3e65A669792d5AbD2e058C4EcC34A98eBb ✅
//   delegateFactory 0xAf960b9B057f59c68e55Ff9aC29966d9bf62b71B ✅

// == Logs ==
//   RWA Implementation 0xbDcCE39CF7bCB69Fbd716c894439f52217Eb5e40 ✅
//   RWA 0x909Fd75Ce23a7e61787FE2763652935F92116461 ✅
//   vesting Implementation 0xBe1d3320E1020910Cd3eb385ADc220e39E355640 ✅
//   vesting 0xEE1643c7ED4e195893025df09E757Cc526F757F9 ✅
//   veRWA Implementation 0x345D4dA62A1670891d697C2be5ADC38F625dE037 ✅
//   veRWA 0x6fa3d2CB3dEBE19e10778F3C3b95A6cDF911fC5B ✅
//   revDistributor Implementation 0xD06c6091f3c29c989172A64ce30AF84981c59D48 ✅
//   revDistributor 0xa443Bf2fCA2119bFDb97Bc01096fBC4F1546c8Ae ✅
//   revStreamETH Implementation 0xC781b3c9402DfEf5c94b57FC2c4741eb3E606193 ✅
//   revStreamETH 0x4f233dbA3E21D762AeAf7c81103A15A8980706B3 ✅
//   delegator Implementation 0xCfAEc6bBB31C69a1CF0108aF8936d9fC76B4D9E0 ✅
//   delegateFactory Implementation 0x3D476cF33307c3407A72399a10CA633480E0BdaE ✅
//   delegateFactory 0x6Ca53fe01D1007Ae89Ad730F5c66515819fD5145 ✅