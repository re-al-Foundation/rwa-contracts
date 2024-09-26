// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console } from "forge-std/Script.sol";
import { DeployUtility } from "../../utils/DeployUtility.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { TokenSilo } from "../../../src/staking/TokenSilo.sol";
import { stRWA as StakedRWA } from "../../../src/staking/stRWA.sol";
import { WrappedstRWASatellite } from "../../../src/staking/WrappedstRWASatellite.sol";
import { RWAToken } from "../../../src/RWAToken.sol";

// helper contracts
import "../../../test/utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/deploy/unreal/DeployStRWACrossChain.s.sol:DeployStRWACrossChain --broadcast --legacy \
    --gas-estimate-multiplier 400 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually main chain: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch src/staking/stRWA.sol:stRWA --verifier blockscout --verifier-url https://unreal.blockscout.com/api

    @dev To verify manually satellite token:
    export ETHERSCAN_API_KEY="<API_KEY>"
    forge verify-contract <CONTRACT_ADDRESS> --chain-id <CHAIN_ID> --watch src/staking/WrappedstRWASatellite.sol:WrappedstRWASatellite \
    --verifier etherscan --constructor-args $(cast abi-encode "constructor(address)" <LZ_ENDPOINT>)
*/

/**
 * @title DeployStRWACrossChain
 * @author Chase Brown
 * @notice This script deploys a new instance of a wrapped baskets vault token to the Unreal Testnet.
 */
contract DeployStRWACrossChain is DeployUtility {

    // ~ Script Configure ~

    struct NetworkData {
        string chainName;
        string rpc_url;
        address lz_endpoint;
        uint16 chainId;
        bool mainChain;
        string name;
        string symbol;
    }

    NetworkData[] internal allChains;

    address public rwaToken;
    address public rwaVotingEscrow;
    address public revStream;
    address public revDist;

    address immutable public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    uint256 internal mainChainId = 18233;

    function setUp() public {
        _setup("stRWA.testnet.deployment");

        rwaToken = _loadDeploymentAddress("unreal", "RWAToken");
        rwaVotingEscrow = _loadDeploymentAddress("unreal", "RWAVotingEscrow");
        revStream = _loadDeploymentAddress("unreal", "RevenueStreamETH");
        revDist = _loadDeploymentAddress("unreal", "RevenueDistributor");

        allChains.push(NetworkData(
            {
                chainName: "unreal", 
                rpc_url: vm.envString("UNREAL_RPC_URL"), 
                lz_endpoint: UNREAL_LZ_ENDPOINT_V1, 
                chainId: UNREAL_LZ_CHAIN_ID_V1,
                mainChain: true,
                name: "Liquid Staked RWA",
                symbol: "stRWA"
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "sepolia", 
                rpc_url: vm.envString("SEPOLIA_RPC_URL"), 
                lz_endpoint: SEPOLIA_LZ_ENDPOINT_V1, 
                chainId: SEPOLIA_LZ_CHAIN_ID_V1,
                mainChain: false,
                name: "Wrapped Staked RWA",
                symbol: "wstRWA"
            }
        ));
    }

    function run() public {

        uint256 len = allChains.length;
        for (uint256 i; i < len; ++i) {

            vm.createSelectFork(allChains[i].rpc_url);
            vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

            address tokenAddress;
            address tokenSilo;
            if (allChains[i].mainChain) {
                tokenAddress = _deployLiquidStakedRWAToken(allChains[i].lz_endpoint, allChains[i].name, allChains[i].symbol);
                if (address(StakedRWA(tokenAddress).tokenSilo()) == address(0)) {
                    // deploy new tokenSilo
                    tokenSilo = _deployTokenSilo(tokenAddress);
                }
            }
            else {
                tokenAddress = _deployWrappedStakedRWATokenForSatellite(allChains[i].lz_endpoint, allChains[i].name, allChains[i].symbol);
            }

            StakedRWA stRWAToken = StakedRWA(tokenAddress);

            // set trusted remote address on all other chains for each token.
            for (uint256 j; j < len; ++j) {
                if (i != j) {
                    if (
                        !stRWAToken.isTrustedRemote(
                            allChains[j].chainId, abi.encodePacked(tokenAddress, tokenAddress)
                        )
                    ) {
                        stRWAToken.setTrustedRemoteAddress(
                            allChains[j].chainId, abi.encodePacked(tokenAddress)
                        );
                    }
                }
            }

            // config on main chain
            if (tokenSilo != address(0) && allChains[i].mainChain) {
                _saveDeploymentAddress(allChains[i].chainName, "TokenSilo", tokenSilo);

                if (address(stRWAToken.tokenSilo()) != tokenSilo) stRWAToken.setTokenSilo(payable(tokenSilo));
                if (RWAToken(rwaToken).tokenSilo() != tokenSilo) RWAToken(rwaToken).setTokenSilo(tokenSilo);
                TokenSilo(payable(tokenSilo)).updateRatios(2, 0, 8);
                TokenSilo(payable(tokenSilo)).setSelectorForTarget(
                    UNREAL_SWAP_ROUTER,
                    bytes4(keccak256("exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))")),
                    true
                );
                TokenSilo(payable(tokenSilo)).setFee(350);
            }

            // save stRWAToken addresses to appropriate JSON
            _saveDeploymentAddress(allChains[i].chainName, allChains[i].symbol, tokenAddress);
            vm.stopBroadcast();
        }
    }

    /**
     * @dev This method is in charge of deploying and upgrading stRWA on any chain.
     * This method will perform the following steps:
     *    - Compute the stRWA implementation address
     *    - If this address is not deployed, deploy new implementation
     *    - Computes the proxy address. If implementation of that proxy is NOT equal to the stRWA address computed,
     *      it will upgrade that proxy.
     */
    function _deployLiquidStakedRWAToken(address layerZeroEndpoint, string memory name, string memory symbol) internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(type(StakedRWA).creationCode);
        address tokenAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(block.chainid, layerZeroEndpoint, rwaToken)))
        );

        StakedRWA wrappedToken;

        if (_isDeployed(tokenAddress)) {
            console.log("wrappedToken is already deployed to %s", tokenAddress);
            wrappedToken = StakedRWA(tokenAddress);
        } else {
            wrappedToken = new StakedRWA{salt: _SALT}(block.chainid, layerZeroEndpoint, rwaToken);
            assert(tokenAddress == address(wrappedToken));
            console.log("wrappedToken deployed to %s", tokenAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            StakedRWA.initialize.selector,
            DEPLOYER_ADDRESS,
            name,
            symbol
        );

        proxyAddress = _deployProxy("wrappedBasketToken", address(wrappedToken), init);
    }

    /**
     * @dev This method is in charge of deploying and upgrading TokenSilo on any chain.
     * This method will perform the following steps:
     *    - Deploy a new implementation contract
     *    - Deploy a new proxy for the tokenSilo and returns the address
     */
    function _deployTokenSilo(address wrappedToken) internal returns (address proxyAddress) {
        ERC1967Proxy siloProxy = new ERC1967Proxy(
            address(new TokenSilo(wrappedToken, rwaVotingEscrow, revStream, UNREAL_WETH)),
            abi.encodeWithSelector(TokenSilo.initialize.selector,
                DEPLOYER_ADDRESS
            )
        );

        proxyAddress = address(siloProxy);
        console.log("deployed new tokenSilo %s", proxyAddress);
    }

    /**
     * @dev This method is in charge of deploying and upgrading WrappedstRWASatellite on a satellite chain.
     * This method will perform the following steps:
     *    - Compute the WrappedstRWASatellite implementation address
     *    - If this address is not deployed, deploy new implementation
     *    - Computes the proxy address. If implementation of that proxy is NOT equal to the WrappedstRWASatellite address computed,
     *      it will upgrade that proxy.
     */
    function _deployWrappedStakedRWATokenForSatellite(address layerZeroEndpoint, string memory name, string memory symbol) internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(type(WrappedstRWASatellite).creationCode);
        address wrappedTokenAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(mainChainId, layerZeroEndpoint)))
        );

        WrappedstRWASatellite wrappedToken;

        if (_isDeployed(wrappedTokenAddress)) {
            console.log("wrappedToken is already deployed to %s", wrappedTokenAddress);
            wrappedToken = WrappedstRWASatellite(wrappedTokenAddress);
        } else {
            wrappedToken = new WrappedstRWASatellite{salt: _SALT}(mainChainId, layerZeroEndpoint);
            assert(wrappedTokenAddress == address(wrappedToken));
            console.log("wrappedToken deployed to %s", wrappedTokenAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            WrappedstRWASatellite.initialize.selector,
            DEPLOYER_ADDRESS,
            name,
            symbol
        );

        proxyAddress = _deployProxy("wrappedBasketToken", address(wrappedToken), init);
    }
}