// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "../../abstract/AdminAccess.sol";

contract MockPassiveIncomeNFT is ERC721Enumerable, AdminAccess {
    struct Lock {
        uint256 startTime;
        uint256 endTime;
        uint256 tokenizationCost;
        uint256 multiplier;
        uint256 claimed;
        uint256 maxPayout;
    }
    uint256 private _tokenIds;
    //for piNFT
    bytes32 public constant EARLY_MINTER_ROLE = keccak256("EARLY_MINTER");
    bytes32 public constant REVENUE_MANAGER_ROLE = keccak256("REVENUE_MANAGER");
    bytes32 public constant SNAPPER_ROLE = keccak256("SNAPPER");

    string private _tokenBaseURI = "https://sometinhg.com";

    mapping(uint256 => uint256) private tokenIdToLockedAmount;

    uint256 ittearator;

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    constructor() ERC721("PI", "Passive Income NFT") {}

    function burn(uint256 tokenId) external returns (uint256 amount) {
        _burn(tokenId);
        amount = tokenIdToLockedAmount[tokenId];
        delete tokenIdToLockedAmount[tokenId];
    }

    function claim(uint256 tokenId, uint256 amount) external {}

    function claimableIncome(uint256 tokenId) public view returns (uint256, uint256) {
        return (0, tokenIdToLockedAmount[tokenId]);
    }

    function locks(uint256 piTokenId) external view returns (Lock memory lock) {
        lock.startTime = 111111111111;
        lock.endTime = 222222222;
        lock.tokenizationCost = 200;
        lock.multiplier = 11;
        lock.claimed = 0;
        lock.maxPayout = 400;
    }

    function canEarnForAmount(uint256 tngblAmount) external returns (bool) {
        return true;
    }

    function setGenerateRevenue(
        uint256 someAddress,
        bool value
    ) external onlyRole(REVENUE_MANAGER_ROLE) {
        ittearator++;
    }

    function mint(
        address minter,
        uint256 tokenizationCost,
        uint8 /*lockDurationInMonths*/,
        bool /*onlyLock*/,
        bool /*generateRevenue*/
    ) external returns (uint256 tokenId) {
        tokenId = ++_tokenIds;
        _mint(minter, tokenId);
        tokenIdToLockedAmount[tokenId] = tokenizationCost;
    }

    function _baseURI() internal view override returns (string memory) {
        return _tokenBaseURI;
    }

    function maxLockDuration() external pure returns (uint8) {
        return uint8(48);
    }

    function _update(
        address to,
        uint256 tokenId,
        address batchSize
    ) internal override returns (address) {
        return super._update(to, tokenId, batchSize);
    }
}
