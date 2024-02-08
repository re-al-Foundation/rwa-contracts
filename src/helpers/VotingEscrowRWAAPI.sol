// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";


contract VotingEscrowRWAAPI is UUPSUpgradeable, AccessControlUpgradeable {

    // ---------------
    // State Variables
    // ---------------

    address public veRWA;

    address public rwaToken;

    address public veVesting;


    // -----------
    // Constructor
    // -----------

    constructor() {
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    /**
     * @notice This initializes RWAToken.
     * @param _admin Initial default admin address.
     */
    function initialize(
        address _admin,
        address _veRWA,
        address _veVesting,
        address _rwaToken
    ) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        veRWA = _veRWA;
        rwaToken = _rwaToken;
        veVesting = _veVesting;
    }


    // ----------------
    // External Methods
    // ----------------

    
    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice Overriden from UUPSUpgradeable
     * @dev Restricts ability to upgrade contract to `DEFAULT_ADMIN_ROLE`
     */
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

}