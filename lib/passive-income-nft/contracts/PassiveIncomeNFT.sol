// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./interfaces/ERC20Burnable.sol";
import "./interfaces/ERC20Mintable.sol";
import "./interfaces/RevenueShare.sol";
import "./utils/Base64.sol";
import "./PassiveIncomeCalculator.sol";
import "./interfaces/IMarketplace.sol";

// solhint-disable not-rely-on-time
contract PassiveIncomeNFT is ERC721Enumerable, AccessControl {
    event Claim(
        address indexed account,
        uint256 indexed tokenId,
        uint256 value
    );

    bytes32 public constant EARLY_MINTER_ROLE = keccak256("EARLY_MINTER");
    bytes32 public constant REVENUE_MANAGER_ROLE = keccak256("REVENUE_MANAGER");
    bytes32 public constant MIGRATOR_ROLE = keccak256("MIGRATOR");
    struct Lock {
        uint256 startTime;
        uint256 endTime;
        uint256 lockedAmount;
        uint256 multiplier;
        uint256 claimed;
        uint256 maxPayout;
    }

    uint256 public immutable boostStartTime;
    uint256 public immutable boostEndTime;

    mapping(uint256 => Lock) public locks;

    uint8 public maxLockDuration;
    uint256 public totalLocked;
    uint256 public totalClaimed;

    /* solhint-disable var-name-mixedcase */
    address private piTOKEN;
    IPassiveIncomeCalculator private piCALCULATOR;
    /* solhint-enable var-name-mixedcase */

    uint256 private _piTokenBalance;
    uint256 private _tokenIds;

    string private _imageBaseURI;

    mapping(uint8 => uint256) private _lockDurations;
    mapping(uint256 => bool) private _generateRevenue;

    RevenueShare public revenueShare;
    IMarketplace public marketplace;

    constructor(
        address piToken,
        address piCalculator,
        uint256 start
    ) ERC721("PI", "Passive Income NFT") {
        maxLockDuration = MAX_LOCK_DURATION;
        boostStartTime = start;
        boostEndTime = start + (1440 days);
        piTOKEN = piToken;
        piCALCULATOR = IPassiveIncomeCalculator(piCalculator);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setMaxLockDuration(uint8 months)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        maxLockDuration = months;
    }

    function setRevenueShareContract(address revenueShare_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        revenueShare = RevenueShare(revenueShare_);
    }

    function setMarketplaceContract(address marketplace_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        marketplace = IMarketplace(marketplace_);
    }

    function avgLockDuration() external view returns (uint256) {
        uint256 total = totalSupply();
        if (total == 0) return 0;
        uint256 sum;
        for (uint8 i = 2; i <= 48; i++) {
            sum += _lockDurations[i] * i;
        }
        return (sum * 10) / total;
    }

    function burn(uint256 tokenId) external returns (uint256 amount) {
        address sender = msg.sender;
        require(sender == ownerOf(tokenId), "caller is not the owner");
        Lock memory lock = locks[tokenId];
        require(block.timestamp >= lock.endTime, "not expired");
        if (_generateRevenue[tokenId]) {
            revenueShare.updateShare(
                address(this),
                tokenId,
                -int256(lock.lockedAmount + lock.maxPayout)
            );
        }
        (amount, ) = claimableIncome(tokenId);
        if (amount > 0) {
            totalClaimed += amount;
        }
        totalLocked -= lock.lockedAmount;
        amount += lock.lockedAmount;
        uint8 lockDuration = uint8((lock.endTime - lock.startTime) / (30 days));
        _lockDurations[lockDuration]--;
        delete locks[tokenId];
        _burn(tokenId);
        marketplace.afterBurnToken(tokenId);
        SafeERC20.safeTransfer(IERC20(piTOKEN), sender, amount);
    }

    function canEarnForAmount(uint256 amount) external view returns (bool) {
        uint8 duration = maxLockPeriodForAmount(amount);
        return
            duration > 0 &&
            piCALCULATOR.determineMultiplier(
                boostStartTime,
                boostEndTime,
                block.timestamp,
                duration
            ) >
            1e18;
    }

    function claim(uint256 tokenId, uint256 amount) external {
        address sender = msg.sender;
        require(sender == ownerOf(tokenId), "caller is not the owner");
        (uint256 free, uint256 max) = claimableIncome(tokenId);
        require(amount <= max, "amount exceeds claimable income");
        Lock storage lock = locks[tokenId];
        if (amount > free) {
            uint256 penalized = amount - free;
            uint256 percentOverFree = (penalized * 1e8) / (max - free);
            uint256 multiplier = lock.multiplier;
            uint256 decreaseMultiplierBy = ((multiplier - 1e18) *
                percentOverFree) / 1e8;
            uint256 newMultiplier = multiplier - decreaseMultiplierBy;
            uint256 newMaxPayout = (newMultiplier * lock.lockedAmount) / 1e18;
            if (_generateRevenue[tokenId]) {
                revenueShare.updateShare(
                    address(this),
                    tokenId,
                    -int256(lock.maxPayout - newMaxPayout)
                );
            }
            uint256 burnAmount = lock.maxPayout - newMaxPayout;
            IERC20(piTOKEN).approve(address(this), burnAmount);
            ERC20Burnable(piTOKEN).burn(burnAmount);
            lock.multiplier = newMultiplier;
            lock.maxPayout = newMaxPayout;
        }
        lock.claimed += amount;
        if (_generateRevenue[tokenId]) {
            revenueShare.updateShare(address(this), tokenId, -int256(amount));
        }
        SafeERC20.safeTransfer(IERC20(piTOKEN), sender, amount);
        emit Claim(sender, tokenId, amount);
    }

    function claimableIncome(uint256 tokenId)
        public
        view
        returns (uint256 free, uint256 max)
    {
        Lock memory lock = locks[tokenId];
        if (block.timestamp < boostStartTime) {
            return (0, 0);
        }
        if (block.timestamp >= lock.endTime) {
            free = max = lock.maxPayout - lock.claimed;
        } else {
            (free, max) = piCALCULATOR.claimableIncome(
                lock.startTime,
                lock.endTime,
                block.timestamp,
                lock.lockedAmount,
                lock.multiplier,
                lock.claimed
            );
            max -= lock.claimed;
            if (free < lock.claimed) {
                free = 0;
            } else {
                free -= lock.claimed;
            }
        }
        return (free, max);
    }

    function claimableIncomes(uint256[] calldata tokenIds)
        external
        view
        returns (uint256[] memory free, uint256[] memory max)
    {
        uint256 len = tokenIds.length;
        free = new uint256[](len);
        max = new uint256[](len);
        while (len > 0) {
            (uint256 free_, uint256 max_) = claimableIncome(tokenIds[--len]);
            free[len] = free_;
            max[len] = max_;
        }
    }

    function mint(
        address minter,
        uint256 lockedAmount,
        uint8 lockDurationInMonths,
        bool onlyLock,
        bool generateRevenue
    ) external returns (uint256 tokenId) {
        require(
            lockDurationInMonths >= MIN_LOCK_DURATION &&
                lockDurationInMonths <= maxLockDuration,
            "invalid lock duration"
        );
        tokenId = ++_tokenIds;
        Lock memory lock;
        if (block.timestamp >= boostStartTime) {
            lock.startTime = block.timestamp;
        } else {
            require(hasRole(EARLY_MINTER_ROLE, msg.sender), "too early");
            lock.startTime = boostStartTime;
        }
        lock.endTime = lock.startTime + uint256(lockDurationInMonths) * 30 days;
        lock.lockedAmount = lockedAmount;
        if (onlyLock) {
            lock.multiplier = 1e18;
            lock.maxPayout = 0;
        } else {
            lock.multiplier = piCALCULATOR.determineMultiplier(
                boostStartTime,
                boostEndTime,
                lock.startTime,
                lockDurationInMonths
            );
            lock.maxPayout = (lockedAmount * (lock.multiplier - 1e18)) / 1e18;
        }
        locks[tokenId] = lock;
        totalLocked += lockedAmount;
        _lockDurations[lockDurationInMonths]++;
        SafeERC20.safeTransferFrom(
            IERC20(piTOKEN),
            msg.sender,
            address(this),
            lockedAmount
        );
        ERC20Mintable(piTOKEN).mint(lock.maxPayout);
        _mint(minter, tokenId);
        if (_generateRevenue[tokenId] = generateRevenue) {
            revenueShare.updateShare(
                address(this),
                tokenId,
                int256(lock.lockedAmount + lock.maxPayout)
            );
        }
    }

    function migrate(
        address owner,
        uint256 lockedAmount,
        uint256 multiplier,
        uint8 lockDurationInMonths,
        uint256 claimed,
        uint256 maxPayout
    ) external onlyRole(MIGRATOR_ROLE) returns (uint256 tokenId) {
        tokenId = ++_tokenIds;
        Lock memory lock;
        if (block.timestamp >= boostStartTime) {
            lock.startTime = block.timestamp;
        } else {
            lock.startTime = boostStartTime;
        }
        lock.endTime = lock.startTime + uint256(lockDurationInMonths) * 30 days;
        lock.lockedAmount = lockedAmount;
        lock.multiplier = multiplier;
        lock.claimed = claimed;
        lock.maxPayout = maxPayout;
        locks[tokenId] = lock;
        totalLocked += lockedAmount;
        _lockDurations[lockDurationInMonths]++;
        ERC20Mintable(piTOKEN).mint(lockedAmount + lock.maxPayout);
        _mint(owner, tokenId);
        _generateRevenue[tokenId] = true;
        revenueShare.updateShare(
            address(this),
            tokenId,
            int256(lock.lockedAmount + lock.maxPayout)
        );
    }

    function maxLockPeriodForAmount(uint256 lockedAmount)
        public
        view
        returns (uint8)
    {
        uint256 totalSupply = IERC20(piTOKEN).totalSupply();
        for (
            uint8 duration = maxLockDuration;
            duration >= MIN_LOCK_DURATION;
            duration--
        ) {
            uint256 multiplier = piCALCULATOR.determineMultiplier(
                boostStartTime,
                boostEndTime,
                block.timestamp,
                duration
            );
            uint256 maxPayout = (lockedAmount * (multiplier - 1e18)) / 1e18;
            if (maxPayout + totalSupply <= 33333333e18) {
                return duration;
            }
        }
        return 0;
    }

    function setGenerateRevenue(uint256 tokenId, bool generate)
        external
        onlyRole(REVENUE_MANAGER_ROLE)
    {
        _generateRevenue[tokenId] = generate;
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
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"Passive Income NFT (3,3)+","description":"","attributes":"","image":"',
                                _imageBaseURI,
                                Strings.toString(tokenId),
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function setImageBaseURI(string memory baseURI)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _imageBaseURI = baseURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId);
        marketplace.updateTokenOwner(tokenId, from, to);
    }
}
