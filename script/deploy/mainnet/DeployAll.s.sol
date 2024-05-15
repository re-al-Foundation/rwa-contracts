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
import { CrossChainMigrator } from "../../../src/CrossChainMigrator.sol";
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
    forge script script/deploy/mainnet/DeployAll.s.sol:DeployAll --broadcast --legacy \
    --gas-estimate-multiplier 600 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \ 
    src/Contract.sol:Contract --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv
*/

/**
 * @title DeployAll
 * @author Chase Brown
 * @notice This script deploys the RWA ecosystem to Re.al chain.
 */
contract DeployAll is DeployUtility {

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

    // ~ SwapRouter Target Paths for RevDist ~

    bytes4 public selector_exactInputSingle = 
        bytes4(keccak256("exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))"));
    bytes4 public selector_exactInputSingleFeeOnTransfer = 
        bytes4(keccak256("exactInputSingleFeeOnTransfer((address,address,uint24,address,uint256,uint256,uint256,uint160))"));
    bytes4 public selector_exactInput = 
        bytes4(keccak256("exactInput((bytes,address,uint256,uint256,uint256))"));
    bytes4 public selector_exactInputFeeOnTransfer = 
        bytes4(keccak256("exactInputFeeOnTransfer((bytes,address,uint256,uint256,uint256))"));

    // ~ Variables ~

    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");
    address public adminAddress = vm.envAddress("DEPLOYER_ADDRESS");

    function setUp() public {
        _setUp("re.al");
    }

    function run() public {
        vm.createSelectFork(REAL_RPC_URL);
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
                REAL_LZ_ENDPOINT_V1, // lz endpoint
                adminAddress // admin address
            )
        );
        console2.log("veRWA", address(veRWAProxy));
        veRWA = RWAVotingEscrow(address(veRWAProxy));


        // Deploy RealReceiver
        receiver = new RealReceiver(REAL_LZ_ENDPOINT_V1);
        // Deploy proxy for receiver
        ERC1967Proxy receiverProxy = new ERC1967Proxy(
            address(receiver),
            abi.encodeWithSelector(RealReceiver.initialize.selector,
                uint16(137), // polygon chainId
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
                address(veRWA),
                REAL_WREETH
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
                REAL_WREETH,
                REAL_SWAP_ROUTER,
                REAL_BOX_MANAGER,
                REAL_TNGBLV3ORACLE
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
        console2.log("revStreamRWA", address(revStreamProxy));
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
        // add revenue streams TODO: Add rev token POST deployment for w3f config
        //revDistributor.addRevenueToken(address(rwaToken)); // from RWA buy/sell taxes
        //revDistributor.addRevenueToken(UNREAL_DAI); // DAI - bridge yield (ETH too)
        //revDistributor.addRevenueToken(UNREAL_MORE); // MORE - Borrowing fees
        //revDistributor.addRevenueToken(USTB); // USTB - caviar incentives, basket rent yield, marketplace fees
        // add necessary selectors for swaps
        revDistributor.setSelectorForTarget(REAL_SWAP_ROUTER, selector_exactInputSingle, true);
        revDistributor.setSelectorForTarget(REAL_SWAP_ROUTER, selector_exactInputSingleFeeOnTransfer, true);
        revDistributor.setSelectorForTarget(REAL_SWAP_ROUTER, selector_exactInput, true);
        revDistributor.setSelectorForTarget(REAL_SWAP_ROUTER, selector_exactInputFeeOnTransfer, true);
        // add Revenue streams
        revDistributor.updateRevenueStream(payable(address(revStreamETH)));

        // RWAToken config
        rwaToken.setVotingEscrowRWA(address(veRWA));
        rwaToken.setReceiver(address(receiver));
        rwaToken.excludeFromFees(address(revDistributor), true);
        rwaToken.setRoyaltyHandler(address(royaltyHandler));
        rwaToken.excludeFromFees(address(revStreamRWA), true);
        
        // RoyaltyHandler config
        royaltyHandler.setPearl(REAL_PEARL);

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

        vm.stopBroadcast();


        // -----------------
        // Post-Deploy TODOs
        // -----------------

        // RealReceiver config
        // TODO: Set trusted remote address via CrossChainMigrator.setTrustedRemoteAddress(remoteEndpointId, abi.encodePacked(address(receiver))); ✅
        // TODO: Also set trusted remote on receiver via RealReceiver.setTrustedRemoteAddress(sourceEndpointId, abi.encodePacked(address(crossChainMigrator))); ✅

        // RevenueTokens
        // TODO: Add all revenue tokens
        // TODO: revDistributor.setRevenueStreamForToken(address(rwaToken), address(revStreamRWA));

        // TODO: Create the RWA/WETH pair, initialize, and add liquidity
        // TODO: Set RWA/WETH pair on RWAToken as automatedMarketMakerPair via RwaToken.setAutomatedMarketMakerPair(pair, true);
        // TODO: Set RWA/WETH fee on RoyaltyHandler
        // TODO: Create LiquidBox and GaugeV2ALM for RWA/WETH pair -> Set on RoyaltyHandler
        // TODO: Deploy and set ExactInputWrapper if needed
        // TODO: Set any permissions on any necessary Gelato Function callers

        // TODO: If mainnet, transfer ownership to multisig
    }
}