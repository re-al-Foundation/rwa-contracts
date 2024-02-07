// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import "./interfaces/RevenueShare.sol";
import "./RentDistributer.sol";
import "./TangibleRevenueShare.sol";

contract TangibleRentShare is AccessControl {
    event RentShareDeployed(
        address indexed contractAddress,
        uint256 indexed tokenId,
        address rentShare,
        address rentDistributor,
        bytes32 taskId
    );

    struct RevenueShareContract {
        address revenueShare;
        address rentDistributor;
        address contractAddress;
        uint256 tokenId;
        bytes32 distributorTaskId;
    }

    using SafeERC20 for IERC20;

    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR");
    bytes32 public constant SHARE_MANAGER_ROLE = keccak256("SHARE_MANAGER");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR");

    address public immutable revenueToken;
    address public immutable ops;

    address public distributorAddress;

    mapping(bytes => RevenueShareContract) private _contractForToken;

    bytes[] private _tokens;

    constructor(address tokenContractAddress, address opsAddress) {
        revenueToken = tokenContractAddress;
        ops = opsAddress;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _distributorForToken(address contractAddress, uint256 tokenId)
        private
        view
        returns (RentDistributor)
    {
        bytes memory token = abi.encodePacked(contractAddress, tokenId);
        address distributor = _contractForToken[token].rentDistributor;
        require(distributor != address(0), "no distributor");
        return RentDistributor(distributor);
    }

    function deposit(
        address contractAddress,
        uint256 tokenId,
        uint256 amount
    ) public onlyRole(DEPOSITOR_ROLE) {
        IERC20(revenueToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        RentDistributor distributor = _distributorForToken(
            contractAddress,
            tokenId
        );
        IERC20(revenueToken).approve(address(distributor), amount);
        distributor.deposit(amount);
    }

    function forToken(address contractAddress, uint256 tokenId)
        external
        returns (RevenueShare)
    {
        bytes memory token = abi.encodePacked(contractAddress, tokenId);
        if (_contractForToken[token].revenueShare == address(0)) {
            _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
            _tokens.push(token);
            TangibleRevenueShare revenueShare = new TangibleRevenueShare(
                revenueToken
            );
            RentDistributor distributor = new RentDistributor(revenueToken);
            revenueShare.grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
            revenueShare.grantRole(DEPOSITOR_ROLE, address(distributor));
            distributor.setRevenueShareContract(address(revenueShare));
            distributor.grantRole(DEPOSITOR_ROLE, address(this));
            distributor.grantRole(DISTRIBUTOR_ROLE, ops);
            _contractForToken[token] = RevenueShareContract(
                address(revenueShare),
                address(distributor),
                contractAddress,
                tokenId,
                bytes32(0)
            );
            startDistributor(contractAddress, tokenId);
            emit RentShareDeployed(
                contractAddress,
                tokenId,
                address(revenueShare),
                address(distributor),
                _contractForToken[token].distributorTaskId
            );
        }
        return RevenueShare(_contractForToken[token].revenueShare);
    }

    function startDistributor(address contractAddress, uint256 tokenId)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bytes memory token = abi.encodePacked(contractAddress, tokenId);
        RevenueShareContract storage contract_ = _contractForToken[token];
        if (contract_.distributorTaskId != bytes32(0)) {
            stopDistributor(contractAddress, tokenId);
        }
        RentDistributor distributor = RentDistributor(
            contract_.rentDistributor
        );
        contract_.distributorTaskId = IOps(ops).createTask(
            address(distributor),
            distributor.distribute.selector,
            address(distributor),
            abi.encodeWithSelector(distributor.checker.selector)
        );
    }

    function stopDistributor(address contractAddress, uint256 tokenId)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bytes memory token = abi.encodePacked(contractAddress, tokenId);
        RevenueShareContract storage contract_ = _contractForToken[token];
        require(
            contract_.distributorTaskId != bytes32(0),
            "task is not running"
        );
        IOps(ops).cancelTask(contract_.distributorTaskId);
        contract_.distributorTaskId = bytes32(0);
    }

    function getManagedContracts()
        external
        view
        returns (RevenueShareContract[] memory contracts)
    {
        uint256 length = _tokens.length;
        contracts = new RevenueShareContract[](length);
        for (uint256 i = 0; i < length; i++) {
            contracts[i] = _contractForToken[_tokens[i]];
        }
    }

    function withdraw(
        address contractAddress,
        uint256 tokenId,
        uint256 amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        RentDistributor distributor = _distributorForToken(
            contractAddress,
            tokenId
        );
        if (amount == 0) {
            amount = IERC20(revenueToken).balanceOf(address(distributor));
        }
        distributor.withdraw(amount);
        IERC20(revenueToken).transfer(msg.sender, amount);
    }
}
