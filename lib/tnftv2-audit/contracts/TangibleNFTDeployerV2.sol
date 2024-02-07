// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./TangibleNFTV2.sol";
import "./interfaces/ITangibleNFTDeployer.sol";
import "./abstract/FactoryModifiers.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @title TangibleNFTDeployer
 * @author Veljko Mihailovic
 * @notice This contract is used to deploy new TangibleNFT contracts.
 */
contract TangibleNFTDeployerV2 is ITangibleNFTDeployer, FactoryModifiers {
    /// notice tnft symbol => TangibleNFT beacon proxy address.
    mapping(string => address) public tnftBeaconProxy;
    /// @notice UpgradeableBeacon contract instance. Deployed by this contract upon initialization.
    UpgradeableBeacon public beacon;

    TangibleNFTV2 public implementation;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ~ Initializer ~

    /**
     * @notice Initializes the TangibleNFTDeployer contract
     * @param _factory Address for the  Factory contract.
     */
    function initialize(address _factory) external initializer {
        __FactoryModifiers_init(_factory);
        // deploy TangibleNFT to use for implementation
        implementation = new TangibleNFTV2();

        beacon = new UpgradeableBeacon(address(implementation), address(this));
    }

    // ~ Functions ~
    /**
     * @notice This method will deploy a new TangibleNFT contract.
     * @return Returns a reference to the new TangibleNFT contract.
     */
    function deployTnft(
        string calldata name,
        string calldata symbol,
        string calldata uri,
        bool isStoragePriceFixedAmount,
        bool storageRequired,
        bool _symbolInUri,
        uint256 _tnftType
    ) external onlyFactory returns (ITangibleNFT) {
        BeaconProxy newTangibleNFTV2Beacon = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(
                TangibleNFTV2.initialize.selector,
                factory(),
                name,
                symbol,
                uri,
                isStoragePriceFixedAmount,
                storageRequired,
                _symbolInUri,
                _tnftType
            )
        );
        // store beacon proxy address in mapping
        tnftBeaconProxy[symbol] = address(newTangibleNFTV2Beacon);

        return ITangibleNFT(address(newTangibleNFTV2Beacon));
    }

    /**
     * @notice This function allows the factory owner to update the TangibleNFTV2 implementation.
     */
    function updateTnftImplementation() external onlyFactoryOwner {
        // deploy TangibleNFTV2 to use for implementation
        implementation = new TangibleNFTV2();
        beacon.upgradeTo(address(implementation));
    }
}
