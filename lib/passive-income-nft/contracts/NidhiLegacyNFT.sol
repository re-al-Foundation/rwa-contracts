// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./utils/Base64.sol";

contract NidhiLegacyNFT is ERC721Enumerable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    uint256 private _tokenIds;
    string private _imageBaseURL;

    mapping(uint256 => string) private _images;

    event Minted(uint256 indexed tokenId, string tokenURI);

    constructor() ERC721("NDL", "NidhiDAO Legacy NFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _imageBaseURL = "https://infura-ipfs.io/ipfs/";
    }

    function mint(address minter, string memory image)
        external
        onlyRole(MINTER_ROLE)
    {
        _safeMint(minter, ++_tokenIds);
        _images[_tokenIds] = image;
        emit Minted(_tokenIds, tokenURI(_tokenIds));
    }

    function setImageBaseURL(string memory baseURL)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _imageBaseURL = baseURL;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return
            ERC721Enumerable.supportsInterface(interfaceId) ||
            AccessControl.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            bytes(_images[tokenId]).length > 0,
            "URI query for nonexistent token"
        );
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"NidhiDAO Legacy NFT","description":"","attributes":"","image":"',
                                abi.encodePacked(
                                    _imageBaseURL,
                                    _images[tokenId]
                                ),
                                '"}'
                            )
                        )
                    )
                )
            );
    }
}
