// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import "./interfaces/RevenueShare.sol";

contract TangibleRevenueShare is RevenueShare, AccessControl {
    event UpdatedShare(
        address indexed contractAddress,
        uint256 indexed tokenId,
        int256 delta,
        uint256 share
    );

    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR");
    bytes32 public constant SHARE_MANAGER_ROLE = keccak256("SHARE_MANAGER");

    using SafeERC20 for IERC20;

    IERC20 public immutable revenueToken;

    uint256[] public cycles;

    uint256 public total;

    mapping(uint256 => int256) public totals;
    mapping(uint256 => uint256) public revenue;

    mapping(bytes => int256) public share;
    mapping(bytes => mapping(uint256 => int256)) public changes;
    mapping(bytes => uint256) public lastClaim;

    mapping(address => uint256) public _contractIndex;

    address[] public _contracts;

    constructor(address tokenContractAddress) {
        revenueToken = IERC20(tokenContractAddress);
        cycles.push(block.timestamp);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function currentCycle() public view returns (uint256) {
        uint256 numCycles = cycles.length;
        return cycles[numCycles - 1];
    }

    function _claimableForToken(bytes memory token)
        internal
        view
        returns (uint256 amount)
    {
        int256 currentShare = share[token];
        uint256 numCycles = cycles.length;
        uint256 lastCycle = lastClaim[token];
        mapping(uint256 => int256) storage change = changes[token];
        uint256 i = 1;
        uint256 cycle = cycles[numCycles - i];
        int256 currentTotal = int256(total) - totals[cycle];
        currentShare -= change[cycle];
        while (i < numCycles && cycle > lastCycle) {
            uint256 currentRevenue = revenue[cycle];
            i++;
            cycle = cycles[numCycles - i];
            amount +=
                (currentRevenue * uint256(currentShare)) /
                uint256(currentTotal);
            currentShare -= change[cycle];
            currentTotal -= totals[cycle];
        }
    }

    function claimableForToken(address contractAddress, uint256 tokenId)
        external
        view
        override
        returns (uint256)
    {
        bytes memory token = abi.encodePacked(contractAddress, tokenId);
        return _claimableForToken(token);
    }

    function claimableForTokens(
        address[] memory contractAddresses,
        uint256[] memory tokenIds
    ) external view override returns (uint256[] memory) {
        uint256 len = contractAddresses.length;
        uint256[] memory result = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = _claimableForToken(
                abi.encodePacked(contractAddresses[i], tokenIds[i])
            );
        }
        return result;
    }

    function claimableFor(address account)
        external
        view
        returns (uint256 amount)
    {
        uint256 numContracts = _contracts.length;
        for (uint256 i = 0; i < numContracts; i++) {
            address contractAddress = _contracts[i];
            ERC721Enumerable nft = ERC721Enumerable(contractAddress);
            uint256 numTokens = nft.balanceOf(account);
            for (uint256 j = 0; j < numTokens; j++) {
                uint256 tokenId = nft.tokenOfOwnerByIndex(account, j);
                bytes memory token = abi.encodePacked(contractAddress, tokenId);
                amount += _claimableForToken(token);
            }
        }
    }

    function claimFor(address account) external {
        require(
            account == msg.sender || hasRole(CLAIMER_ROLE, msg.sender),
            "unauthorized claimer"
        );
        uint256 amount;
        uint256 cycle = currentCycle();
        uint256 numContracts = _contracts.length;
        for (uint256 j = 0; j < numContracts; j++) {
            address contractAddress = _contracts[j];
            ERC721Enumerable nft = ERC721Enumerable(contractAddress);
            uint256 numTokens = nft.balanceOf(account);
            for (uint256 k = 0; k < numTokens; k++) {
                uint256 tokenId = nft.tokenOfOwnerByIndex(account, k);
                bytes memory token = abi.encodePacked(contractAddress, tokenId);
                amount += _claimableForToken(token);
                lastClaim[token] = cycle;
            }
        }
        require(amount > 0, "no claimable amount");
        revenueToken.safeTransfer(account, amount);
    }

    function claimForToken(address contractAddress, uint256 tokenId) external {
        address owner = IERC721(contractAddress).ownerOf(tokenId);
        require(
            owner == msg.sender || hasRole(CLAIMER_ROLE, msg.sender),
            "unauthorized claimer"
        );
        uint256 cycle = currentCycle();
        bytes memory token = abi.encodePacked(contractAddress, tokenId);
        uint256 amount = _claimableForToken(token);
        if (amount > 0) {
            revenueToken.safeTransfer(owner, amount);
            lastClaim[token] = cycle;
        }
    }

    function shareFor(address account)
        external
        view
        returns (uint256 totalShare)
    {
        uint256 numContracts = _contracts.length;
        for (uint256 i = 0; i < numContracts; i++) {
            address contractAddress = _contracts[i];
            ERC721Enumerable nft = ERC721Enumerable(contractAddress);
            uint256 numTokens = nft.balanceOf(account);
            for (uint256 j = 0; j < numTokens; j++) {
                uint256 tokenId = nft.tokenOfOwnerByIndex(account, j);
                bytes memory token = abi.encodePacked(contractAddress, tokenId);
                totalShare += uint256(share[token]);
            }
        }
    }

    function deposit(uint256 amount)
        external
        override
        onlyRole(DEPOSITOR_ROLE)
    {
        revenueToken.safeTransferFrom(msg.sender, address(this), amount);
        cycles.push(block.timestamp);
        revenue[currentCycle()] = amount;
    }

    function updateShare(
        address contractAddress,
        uint256 tokenId,
        int256 amount
    ) external override onlyRole(SHARE_MANAGER_ROLE) {
        bytes memory token = abi.encodePacked(contractAddress, tokenId);
        uint256 cycle = currentCycle();
        if (share[token] == 0) {
            lastClaim[token] = cycle;
        }
        if (-amount > share[token]) {
            amount = -share[token];
        }
        share[token] += amount;
        changes[token][cycle] += amount;
        total = uint256(int256(total) + amount);
        totals[cycle] += amount;
        if (_contractIndex[contractAddress] == 0) {
            _contracts.push(contractAddress);
            _contractIndex[contractAddress] = _contracts.length;
        }
        emit UpdatedShare(
            contractAddress,
            tokenId,
            amount,
            uint256(share[token])
        );
    }

    function unregisterContract(address contractAddress)
        external
        override
        onlyRole(SHARE_MANAGER_ROLE)
    {
        uint256 index = _contractIndex[contractAddress];
        if (index != 0) {
            uint256 numContracts = _contracts.length;
            if (index != numContracts) {
                _contracts[index - 1] = _contracts[numContracts - 1];
            }
            _contracts.pop();
        }
    }
}
