// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// oz imports
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// local imports
import { stRWA as StakedRWA } from "../../src/staking/stRWA.sol";
import { TokenSilo } from "../../src/staking/TokenSilo.sol";
import { stRWARebaseManager } from "../../src/staking/stRWARebaseManager.sol";
import { RWAToken } from "../../src/RWAToken.sol";
import { RWAVotingEscrow } from "../../src/governance/RWAVotingEscrow.sol";
import { RevenueStreamETH } from "../../src/RevenueStreamETH.sol";
import { RevenueDistributor } from "../../src/RevenueDistributor.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { IQuoterV2 } from "../../src/interfaces/IQuoterV2.sol";
import { IWETH } from "../../src/interfaces/IWETH.sol";

// local helper imports
import "../utils/Utility.sol";
import "../utils/Constants.sol";

/**
 * @title StakedRWAManualRebaseTest
 * @author @chasebrownn
 */
contract StakedRWAManualRebaseTest is Utility {

    // ~ Contracts ~

    StakedRWA public stRWA = StakedRWA(0x154F5DB4950d2cd4a7Af425E11865215F90DdB07);
    TokenSilo public tokenSilo = TokenSilo(payable(0x1A9388A0fbA95A570583e036a3B1e6926613aE8d));
    stRWARebaseManager public rebaseManager = stRWARebaseManager(0x33E10DD4794D0213cf65F2dde68dFd55f0D57baD);

    // rwa contracts
    RWAToken public constant rwaToken = RWAToken(0x4644066f535Ead0cde82D209dF78d94572fCbf14);
    RWAVotingEscrow public constant rwaVotingEscrow = RWAVotingEscrow(0xa7B4E29BdFf073641991b44B283FD77be9D7c0F4);
    RevenueStreamETH public constant revStream = RevenueStreamETH(0xf4e03D77700D42e13Cd98314C518f988Fd6e287a);
    RevenueDistributor public constant revDist = RevenueDistributor(payable(0x7a2E4F574C0c28D6641fE78197f1b460ce5E4f6C));

    // pearl contracts
    ISwapRouter public constant router = ISwapRouter(0xa1F56f72b0320179b01A947A5F78678E8F96F8EC);
    IQuoterV2 public constant quoter = IQuoterV2(0xDe43aBe37aB3b5202c22422795A527151d65Eb18);

    // variables
    IWETH public constant WETH = IWETH(0x90c6E93849E06EC7478ba24522329d14A5954Df4);

    function setUp() public virtual {
        vm.createSelectFork(REAL_RPC_URL, 829962);
        _createLabels();
    }


    // -------
    // Utility
    // -------

    /// @dev Instantiates labels for all global contracts.
    function _createLabels() internal {
        vm.label(address(stRWA), "stRWA");
        vm.label(address(tokenSilo), "TokenSilo");
        vm.label(address(rwaToken), "RWAToken");
        vm.label(address(rwaVotingEscrow), "RWAVotingEscrow");
        vm.label(address(revStream), "RevenueStreamETH");
    }


    // -----
    // Tests
    // -----

    function test_convert() public {
        uint256 amount = .1 ether;
        address target = address(router);

        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(rwaToken);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(WETH),
            tokenOut: address(rwaToken),
            fee: 3000,
            recipient: address(tokenSilo),
            deadline: 10000000000000000000,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory data = 
            abi.encodeWithSignature(
                "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
                params.tokenIn,
                params.tokenOut,
                params.fee,
                params.recipient,
                params.deadline,
                params.amountIn,
                params.amountOutMinimum,
                params.sqrtPriceLimitX96
            );

        vm.prank(tokenSilo.owner());
        tokenSilo.convertRewardToken(address(0), amount, target, data);

        emit log_named_bytes("data", data);
    }
}