// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./RentManager.sol";
import "./interfaces/IRentManager.sol";
import "./interfaces/IRentManagerDeployer.sol";

import "./abstract/FactoryModifiers.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @title RentManagerDeployer
 * @author Veljko Mihailovic
 * @notice This contract is used to deploy new RentManager contracts.
 */
contract RentManagerDeployer is IRentManagerDeployer, FactoryModifiers {
    /// notice Tnft contract address => RentManager beacon proxy address.
    mapping(address => address) public rentManagersBeaconProxy;
    /// @notice UpgradeableBeacon contract instance. Deployed by this contract upon initialization.
    UpgradeableBeacon public beacon;

    RentManager public implementation;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ~ Initializer ~

    /**
     * @notice Initializes the RentManagerDeployer contract.
     * @param _factory Address for the  Factory contract.
     */
    function initialize(address _factory) external initializer {
        __FactoryModifiers_init(_factory);
        // deploy RentManager to use for implementation
        implementation = new RentManager();

        beacon = new UpgradeableBeacon(address(implementation), address(this));
    }

    // ~ Functions ~

    /**
     * @notice This method will deploy a new RentManager contract.
     * @param tnft Address of TangibleNFT contract the new RentManager will manage rent for.
     * @return Returns a reference to the new RentManager.
     */
    function deployRentManager(address tnft) external returns (IRentManager) {
        require(msg.sender == factory(), "NF");
        // create new basket beacon proxy
        BeaconProxy newRentManagerBeacon = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(RentManager(address(0)).initialize.selector, tnft, factory())
        );
        // store beacon proxy address in mapping
        rentManagersBeaconProxy[tnft] = address(newRentManagerBeacon);

        return IRentManager(address(newRentManagerBeacon));
    }

    /**
     * @notice This function allows the factory owner to update the RentManager implementation.
     */
    function updateRentManagerImplementation() external onlyFactoryOwner {
        // deploy RentManager to use for implementation
        implementation = new RentManager();
        beacon.upgradeTo(address(implementation));
    }
}
