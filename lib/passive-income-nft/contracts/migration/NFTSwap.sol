// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../interfaces/ERC20Burnable.sol";
import "../interfaces/ERC20Mintable.sol";
import "../PassiveIncomeNFT.sol";
import "../NidhiLegacyNFT.sol";
import "./TokenSwap.sol";

abstract contract Staking {
    function claim(address recipient) public virtual;

    function unstake(uint256 amount, bool trigger) external virtual;
}

abstract contract NidhiNFT is IERC721 {
    struct Metadata {
        string image;
        string externalURL;
        string description;
        string name;
        uint256 intrinsicValue;
    }

    struct StoredMetadata {
        string image;
        string description;
        string name;
    }

    function metadata(uint256 tokenId)
        external
        view
        virtual
        returns (Metadata memory meta);

    function burn(uint256 tokenId) external virtual;
}

contract PassiveIncomeNFTSwap is Ownable {
    uint8 public minLockDuration;

    NidhiNFT public immutable nidhiNFT;
    NidhiLegacyNFT public immutable nidhiLegacyNFT;
    PassiveIncomeNFT public immutable passiveIncomeNFT;
    TangibleTokenSwap public immutable tokenSwap;
    Staking public immutable staking;
    IERC20 public immutable stakingToken;

    constructor(
        address nidhiNFT_,
        address nidhiLegacyNFT_,
        address tangibleNFT,
        address tokenSwapContractAddress,
        address stakingContractAddress,
        address stakingTokenContractAddress
    ) {
        minLockDuration = 24;
        nidhiNFT = NidhiNFT(nidhiNFT_);
        nidhiLegacyNFT = NidhiLegacyNFT(nidhiLegacyNFT_);
        passiveIncomeNFT = PassiveIncomeNFT(tangibleNFT);
        tokenSwap = TangibleTokenSwap(tokenSwapContractAddress);
        staking = Staking(stakingContractAddress);
        stakingToken = IERC20(stakingTokenContractAddress);
    }

    function setMinLockDuration(uint8 minLockDuration_) external onlyOwner {
        minLockDuration = minLockDuration_;
    }

    function swap(
        uint256 tokenId,
        uint8 lockDurationInMonths,
        bool onlyLock,
        bool generateRevenue
    ) external {
        require(
            lockDurationInMonths >= minLockDuration,
            "invalid lock duration"
        );
        nidhiNFT.transferFrom(msg.sender, address(this), tokenId);
        NidhiNFT.Metadata memory metadata = nidhiNFT.metadata(tokenId);
        nidhiLegacyNFT.mint(msg.sender, metadata.image);
        nidhiNFT.burn(tokenId);
        uint256 amount = _swapTokens();
        if (amount > 0) {
            ERC20(tokenSwap.TNGBL()).approve(address(passiveIncomeNFT), amount);
            passiveIncomeNFT.mint(
                msg.sender,
                amount,
                lockDurationInMonths,
                onlyLock,
                generateRevenue
            );
        }
    }

    function swapGURU(
        uint256 amountIn,
        uint8 lockDurationInMonths,
        bool onlyLock,
        bool generateRevenue
    ) external returns (uint256 tokenId) {
        require(
            lockDurationInMonths >= minLockDuration,
            "invalid lock duration"
        );
        IERC20 guru = IERC20(tokenSwap.GURU());
        guru.transferFrom(msg.sender, address(this), amountIn);
        guru.approve(address(tokenSwap), amountIn);
        uint256 amount = tokenSwap.swap(amountIn);
        if (amount > 0) {
            ERC20(tokenSwap.TNGBL()).approve(address(passiveIncomeNFT), amount);
            tokenId = passiveIncomeNFT.mint(
                msg.sender,
                amount,
                lockDurationInMonths,
                onlyLock,
                generateRevenue
            );
        }
    }

    function _swapTokens() private returns (uint256) {
        uint256 amount = stakingToken.balanceOf(address(this));
        stakingToken.approve(address(staking), amount);
        staking.claim(address(this));
        staking.unstake(amount, false);
        IERC20 guru = IERC20(tokenSwap.GURU());
        guru.approve(address(tokenSwap), amount);
        return tokenSwap.swap(amount);
    }
}
