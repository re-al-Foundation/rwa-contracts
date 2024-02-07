// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./abstract/PriceConverter.sol";
import "./interfaces/ITangibleMarketplace.sol";
import "./interfaces/ITNFTMetadata.sol";
import "./interfaces/IRentManagerDeployer.sol";
import "./interfaces/IVoucher.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./interfaces/ITangiblePriceManager.sol";
import "./interfaces/ITangibleNFTDeployer.sol";
import "./interfaces/IPriceOracle.sol";

/**
 * @title Factory
 * @author Veljko Mihailovic
 * @notice Central factory contract for the Tangible protocol. Manages contract ownership and metadata for all
 *         peripheral contracts in the ecosystem. Also allows for the creation and management of new category Tangible NFTs.
 */
contract FactoryV2 is IFactory, PriceConverter, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;
    // ~ State Variables ~

    /// @notice Default USD contract used for buying unminted tokens and paying for storage when required.
    IERC20 public defUSD;

    /// @notice Mapping used to store the ERC20 tokens accepted as payment. If bool is true, token is accepted as payment.
    mapping(IERC20 => bool) public paymentTokens;

    /// @notice Address of Marketplace contract.
    address public marketplace;

    /// @notice Address of TangibleNFTDeployer contract.
    address public tnftDeployer;

    /// @notice Address of Tangible multisig
    address public tangibleLabs;

    /// @notice Address of TangibleRevenueShare contract
    address public revenueShare;

    /// @notice PriceManager contract reference.
    ITangiblePriceManager public priceManager;

    /// @notice TNFTMetadata contract address.
    address public tnftMetadata;

    /// @notice RentManagerDeployer contract address.
    address public rentManagerDeployer;

    /// @notice Mapping from TangibleNFT contract to bool. If true, whitelist is required to mint from category of TangibleNFT contract.
    mapping(ITangibleNFT => bool) public onlyWhitelistedForUnmintedCategory;

    /// @notice Mapping to identify EOAs that can purchase tokens required by whitelist.
    mapping(ITangibleNFT => mapping(address => bool)) public whitelistForBuyUnminted;

    /// @notice Mapping of EOA to bool. If true, EOA can create a new category and provide their own products.
    mapping(address => bool) public categoryMinter;

    /// @notice Mapping that defines how many categories(TNFT contracts) approved minter can create and manage for given type.
    mapping(address => mapping(uint256 => uint256)) public numCategoriesToMint;

    /// @notice Manager of TNFT contract to approve fingerprints for new categories.
    mapping(ITangibleNFT => address) public fingerprintApprovalManager;

    /// @notice Mapping to map the owner EOA of a specified category for a TNFT contract.
    mapping(ITangibleNFT => address) public categoryOwner;

    /// @notice Mapping to map the payment wallet of category owner.
    mapping(address => address) public categoryOwnerPaymentAddress;

    /// @notice Maps category string to TNFT contract address.
    mapping(string => ITangibleNFT) public category;

    /// @notice Mapping of TNFT contract to RentManager contract.
    mapping(ITangibleNFT => IRentManager) public rentManager;

    /// @notice Number of days before the TNFT expires.
    /// @dev If a user does not pay their storage fees, TNFT will expire and be seized.
    mapping(ITangibleNFT => uint256) public daysBeforeSeize;

    /// @notice The constant expiration date for each TNFT.
    uint256 public constant DEFAULT_SEIZE_DAYS = 180;

    /// @notice Array of supported TNFTs
    ITangibleNFT[] private _tnfts;

    /// @notice Array of TNFTs owned by Tangible.
    ITangibleNFT[] public ownedByLabs;

    /// @notice Baskets manager address
    address public basketsManager;

    /// @notice Currency feed address
    address public currencyFeed;

    // ~ Events ~

    /**
     * @notice This event is emitted when the state of whitelistForBuyUnminted is updated.
     * @dev Only used in whitelistBuyer().
     * @param tnft Address of tNft contract.
     * @param buyer Address that is allowed to mint.
     * @param approved Status of allowance to mint. If true, buyer can mint. Otherwise false.
     */
    event WhitelistedBuyer(address indexed tnft, address indexed buyer, bool indexed approved);

    /**
     * @notice This event is emitted when there is a new minter of a categorized tNft.
     * @dev Only used in whitelistCategoryMinter().
     * @param minter Address of EOA that will be minting tNft(s).
     * @param approved If approved to mint will be true, otherwise false.
     * @param tnftType which category user is allowed to create.
     * @param amount Amount of categories minter is allowed to create.
     */
    event WhitelistedCategoryMinter(
        address indexed minter,
        bool indexed approved,
        uint256 indexed tnftType,
        uint16 amount
    );

    /**
     * @notice This event is emitted when a token or multiple tokens are minted.
     * @dev Only emitted when mint() is called.
     * @param tnft Address of tNft contract.
     * @param tokenIds Array of tokenIds that were minted.
     */
    event MintedTokens(address indexed tnft, uint256[] tokenIds);

    /**
     * @notice This event is emitted when the state of paymentTokens is updated.
     * @param token Address of ERC20 token that is accepted as payment.
     * @param approved If true, token is accepted as payment otherwise false.
     */
    event PaymentToken(address indexed token, bool approved);

    /**
     * @notice This event is emitted when the walet for payment is changed.
     * @param owner Address owner which want to change his wallet for payments.
     * @param wallet Address of the wallet to use
     */
    event WalletChanged(address indexed owner, address wallet);

    /**
     * @notice This event is emitted when a new category of tNFTs is created and deployed.
     * @param tnft Address of tNft contract that is created.
     * @param minter Address of deployer EOA or multisig.
     */
    event NewCategoryDeployed(address indexed tnft, address indexed minter);

    /**
     * @notice This event is emitted when a new category name is added to the category mapping with a tnft value.
     * @param tnft address of tnft contract that is setting a new category name.
     */
    event CategoryMigrated(address indexed tnft);

    /**
     * @notice This event is emitted when a category owner is updated.
     * @param tnft TangibleNFT contract address.
     * @param owner Category owner address.
     */
    event CategoryOwner(address indexed tnft, address indexed owner);

    /**
     * @notice This event is emitted when there is a peripherial contract address from FACT_ADDRESSES type that is updated.
     * @param contractType Enum corresponding with FACT_ADDRESSES type.
     * @param oldAddress Old contract address.
     * @param newAddress New contract address.
     */
    event ContractUpdated(uint256 indexed contractType, address oldAddress, address newAddress);

    // ~ Modifiers ~

    /// @notice Modifier used to verify the function caller is the category owner.
    /// @param nft TangibleNFT contract reference.
    modifier onlyCategoryOwner(ITangibleNFT nft) {
        _checkCategoryOwner(nft);
        _;
    }

    /// @notice Modifier used to verify the function caller is a category minter.
    modifier onlyCategoryMinter() {
        require(categoryMinter[msg.sender], "Caller is not category minter");
        _;
    }

    /// @notice Modifier used to verify that the function caller is the Marketplace contract.
    modifier onlyMarketplace() {
        require(marketplace == msg.sender, "Factory: caller is not the marketplace");
        _;
    }

    /// @notice Modifier used to verify function caller is the marketplace or Tangible multisig.
    modifier onlyLabsOrMarketplace() {
        require(
            (tangibleLabs == msg.sender) || (marketplace == msg.sender),
            "Factory: caller is not the labs nor marketplace"
        );
        _;
    }

    // ~ Enums ~

    /**
     * @notice Enum object to identify a custom contract data type via an enumerable.
     * @param MARKETPLACE Marketplace contract (0)
     * @param TNFT_DEPLOYER TangibleNFTDeployer contract (1)
     * @param RENT_MANAGER_DEPLOYER Rent Manager deployer contract (2)
     * @param LABS Tangible multisig address (3)
     * @param PRICE_MANAGER Price Manager contract (4)
     * @param TNFT_META TangibleNFTMetadata contract (5)
     * @param REVENUE_SHARE TangibleRevenueShare contract (6)
     * @param BASKETS_DEPLOYER Baskets deployer contract (7)
     * @param CURRENCY_FEED Currency feed contract (8)
     */
    enum FACT_ADDRESSES {
        MARKETPLACE,
        TNFT_DEPLOYER,
        RENT_MANAGER_DEPLOYER,
        LABS,
        PRICE_MANAGER,
        TNFT_META,
        REVENUE_SHARE,
        BASKETS_MANAGER,
        CURRENCY_FEED
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ~ Initializer ~

    /**
     * @notice Initialize FactoryV2 contract.
     * @param _defaultUSDToken Address of the default USD Erc20 token accepted for payments.
     * @param _tangibleLabs Tangible multisig address.
     */
    function initialize(address _defaultUSDToken, address _tangibleLabs) external initializer {
        require(_defaultUSDToken != address(0), "UZ");
        __Ownable_init(msg.sender);

        defUSD = IERC20(_defaultUSDToken);
        paymentTokens[IERC20(_defaultUSDToken)] = true;

        tangibleLabs = _tangibleLabs;
        categoryMinter[_tangibleLabs] = true;
        categoryOwnerPaymentAddress[_tangibleLabs] = _tangibleLabs;

        emit ContractUpdated(uint256(FACT_ADDRESSES.LABS), address(0), _tangibleLabs);
    }

    // ~ Functions ~

    /**
     * @notice This onlyOwner function is used to update the defUSD state var.
     * @param usd Erc20 contract to set as new defUSD.
     */
    function setDefaultStableUSD(IERC20 usd) external onlyOwner {
        require(paymentTokens[usd], "NAPP");
        defUSD = usd;
    }

    /**
     * @notice This function is used to add a new payment token.
     * @param token Erc20 token to accept as payment method.
     * @param value If true, token is accepted, otherwise false.
     */
    function configurePaymentToken(IERC20 token, bool value) external onlyOwner {
        paymentTokens[token] = value;
        emit PaymentToken(address(token), value);
    }

    /**
     * @notice This function is used to change wallet address, where payments will go.
     * @param wallet address to where payment will go for msg.sender.
     */
    function configurePaymentWallet(address wallet) external {
        require(wallet != address(0), "no zero address");
        categoryOwnerPaymentAddress[msg.sender] = wallet;
        emit WalletChanged(msg.sender, wallet);
    }

    /**
     * @notice This onlyOwner function is used to set a contract address to a FACT_ADDRESSES contract type.
     * @param _contractId Enumerable of custom FACT_ADDRESSES type.
     * @param _contractAddress Contract address to set.
     */
    function setContract(FACT_ADDRESSES _contractId, address _contractAddress) external onlyOwner {
        _setContract(_contractId, _contractAddress);
    }

    /**
     * @notice This internal function is used to set a contract address to it's corresponding state var.
     * @param _contractId Enumerable of type FACT_ADDRESSES. Used to identify which state var the _contractAddress is for.
     * @param _contractAddress Address of smart contract.
     */
    function _setContract(FACT_ADDRESSES _contractId, address _contractAddress) internal {
        require(_contractAddress != address(0), "WADD");
        address old;
        if (_contractId == FACT_ADDRESSES.MARKETPLACE) {
            // 0
            old = marketplace;
            marketplace = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.TNFT_DEPLOYER) {
            //1
            old = tnftDeployer;
            tnftDeployer = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.RENT_MANAGER_DEPLOYER) {
            // 2
            old = rentManagerDeployer;
            rentManagerDeployer = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.LABS) {
            // 3
            // change ownership in tngbl labs and approver
            old = tangibleLabs;
            for (uint256 i; i < ownedByLabs.length; ) {
                ITangibleNFT tnft = ownedByLabs[i];
                categoryOwner[tnft] = _contractAddress;

                // fingerprint approval manager should change also
                _setFingerprintApprovalManager(tnft, _contractAddress);
                emit CategoryOwner(address(tnft), msg.sender);

                unchecked {
                    ++i;
                }
            }
            // switch approval
            categoryMinter[tangibleLabs] = false;
            categoryMinter[_contractAddress] = true;
            tangibleLabs = _contractAddress;
            // set payment wallet
            categoryOwnerPaymentAddress[_contractAddress] = categoryOwnerPaymentAddress[old];
            delete categoryOwnerPaymentAddress[old];
        } else if (_contractId == FACT_ADDRESSES.PRICE_MANAGER) {
            // 4
            old = address(priceManager);
            priceManager = ITangiblePriceManager(_contractAddress);
        } else if (_contractId == FACT_ADDRESSES.TNFT_META) {
            // 5
            old = tnftMetadata;
            tnftMetadata = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.REVENUE_SHARE) {
            // 6
            old = revenueShare;
            revenueShare = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.BASKETS_MANAGER) {
            // 7
            old = basketsManager;
            basketsManager = _contractAddress;
        } else if (_contractId == FACT_ADDRESSES.CURRENCY_FEED) {
            // 8
            old = currencyFeed;
            currencyFeed = _contractAddress;
        } else {
            revert("Incorrect _contractId input");
        }
        emit ContractUpdated(uint256(_contractId), old, _contractAddress);
    }

    /**
     * @notice This view function is used to return the array of TNFT contract addresses supported by the Factory.
     * @return Array returned of type ITangibleNFT.
     */
    function getCategories() external view returns (ITangibleNFT[] memory) {
        return _tnfts;
    }

    /**
     * @notice This view function is used to return payment wallet that should be used for buyUnminted and storage payments.
     * @return wallet address to be used as payment.
     */
    function categoryOwnerWallet(ITangibleNFT nft) external view returns (address wallet) {
        return _categoryOwnerWallet(nft);
    }

    /**
     * @notice This internal view function is used to return payment wallet that should be used for
     * buyUnminted and storage payments.
     * @return wallet address to be used as payment.
     */
    function _categoryOwnerWallet(ITangibleNFT nft) internal view returns (address wallet) {
        address _owner = categoryOwner[nft];
        wallet = categoryOwnerPaymentAddress[_owner];
        if (wallet == address(0)) {
            wallet = _owner;
        }
    }

    /**
     * @notice This view function is used to see which TNFT contract needs to pay rent.
     * @param tnft contract.
     * @return If true, tnft holders receive rent share. Note: Tenants of Real Estate pay rent.
     */
    function paysRent(ITangibleNFT tnft) external view returns (bool) {
        return _paysRent(tnft);
    }

    /**
     * @notice This function returns whether the `tnft` contract specified has a rent manager.
     * @dev If there exists a rent manager, the `tnft` holders receive rent share since tenants pay rent for Real Estate NFTs.
     * @param tnft TangibleNFT contract reference.
     */
    function _paysRent(ITangibleNFT tnft) internal view returns (bool) {
        return address(rentManager[tnft]) != address(0);
    }

    /**
     * @notice This function allows for a token holder to get a quote for storage costs and updates storage metadata.
     * @dev This function is only callable by the Marketplace
     * @param tnft TangibleNFT contract.
     * @param paymentToken Erc20 token being accepted as payment.
     * @param tokenId Token identifier.
     * @param _years Amount of years to extend expiration && quote for storage costs.
     */
    function adjustStorageAndGetAmount(
        ITangibleNFT tnft,
        IERC20Metadata paymentToken,
        uint256 tokenId,
        uint256 _years
    ) external onlyMarketplace returns (uint256) {
        (uint256 tokenPrice, , ) = priceManager.oracleForCategory(tnft).usdPrice(
            tnft,
            paymentToken,
            0,
            tokenId
        );

        bool storagePriceFixed = tnft.adjustStorage(tokenId, _years);
        //amount to pay
        uint256 amount;
        uint8 decimals = tnft.storageDecimals();

        if (storagePriceFixed) {
            amount =
                toDecimals(tnft.storagePricePerYear(), decimals, paymentToken.decimals()) *
                _years;
        } else {
            require(tokenPrice > 0, "Price 0");
            amount =
                (tokenPrice * tnft.storagePercentagePricePerYear() * _years) /
                (100 * (10 ** decimals));
        }
        return amount;
    }

    /**
     * @notice This function allows the owner to set an approval manager EOA to the fingerprintApprovalManager mapping.
     * @param tnft TangibleNFT contract.
     * @param _manager Manager EOA address.
     */
    function setFingerprintApprovalManager(ITangibleNFT tnft, address _manager) external onlyOwner {
        require(_manager != address(0), "ZA");
        _setFingerprintApprovalManager(tnft, _manager);
    }

    /**
     * @notice Internal function that updates state of fingerprintApprovalManager.
     * @param tnft TangibleNFT contract.
     * @param _manager Manager EOA address.
     */
    function _setFingerprintApprovalManager(ITangibleNFT tnft, address _manager) internal {
        fingerprintApprovalManager[tnft] = _manager;
    }

    /**
     * @notice This function mints the TangibleNFT token from the given MintVoucher.
     * @dev Voucher is received and token(s) is minted to vendor (category owner)
     *      for proof of ownership then transferred to the marketplace so that it can be sold.
     *      Tokens are minted only on purchase.
     *      Only tangibleLabs can mint tokens to sell.
     *      RealEstate TNFTs can be purchased only by whitelisted buyers.
     * @param voucher A mintVoucher is an unminted tNFT.
     */
    function mint(
        MintVoucher calldata voucher
    ) external onlyLabsOrMarketplace returns (uint256[] memory) {
        // marketplace must be set before minting
        require(marketplace != address(0), "MZ");
        //make sure that vendor(who is not admin nor marketplace) is minting just for himself
        uint256 mintCount = 1;
        if (marketplace != msg.sender) {
            require(voucher.vendor == msg.sender, "MFSE");
            mintCount = voucher.mintCount;
        } else if (marketplace == msg.sender) {
            require(voucher.buyer != address(0), "BMNBZ");
            require(
                voucher.vendor == categoryOwner[voucher.token] ||
                    voucher.vendor == _categoryOwnerWallet(voucher.token),
                "MFSEO"
            );
            //houses can't be bought by marketplace unless
            if (_paysRent(voucher.token)) {
                require(onlyWhitelistedForUnmintedCategory[voucher.token], "OWL");
            }
        }
        uint256 sellStock = priceManager.oracleForCategory(voucher.token).availableInStock(
            voucher.fingerprint
        );
        require(sellStock > 0, "Not enough in stock");

        // first assign the token to the vendor, to establish provenance on-chain
        uint256[] memory tokenIds = voucher.token.produceMultipleTNFTtoStock(
            mintCount,
            voucher.fingerprint,
            voucher.vendor
        );
        emit MintedTokens(address(voucher.token), tokenIds);

        //option only available to tangibleLabs to mint and get in his own wallet (eg. realestate)
        address transferTo = marketplace;
        if (voucher.sendToVendor && msg.sender == tangibleLabs) {
            transferTo = msg.sender;
        }

        // send minted tokens to marketplace. when price is 0 - use oracle
        uint256 tokenIdsLength = tokenIds.length;
        for (uint256 i = 0; i < tokenIdsLength; i++) {
            //decrease stock
            priceManager.oracleForCategory(voucher.token).decrementSellStock(voucher.fingerprint);
            // send NFT
            IERC721(voucher.token).safeTransferFrom(
                voucher.vendor,
                transferTo,
                tokenIds[i],
                abi.encode(voucher.price)
            );
            // if there is a buyer in voucher and sender is the vendor, set the designated buyer
            if (voucher.buyer != address(0) && voucher.vendor == msg.sender) {
                ITangibleMarketplace(marketplace).setDesignatedBuyer(
                    voucher.token,
                    tokenIds[i],
                    voucher.buyer
                );
            }
        }

        return tokenIds;
    }

    /**
     * @notice This function allows a category minter to create a new category of Tangible NFTs.
     * @param name Name of new TangibleNFT // category.
     * @param symbol Symbol of new TangibleNFT.
     * @param uri Base uri for NFT Metadata querying.
     * @param isStoragePriceFixedAmount If true, the storage fee is a fixed price.
     * @param storageRequired If true, storage is required for this token. Thus, owner has to pay a storage fee.
     * @param priceOracle Address of price oracle to manage purchase price of tokens.
     * @param symbolInUri Will append this symbol to the uri when querying TangibleNFT::tokenURI().
     * @param _tnftType TangibleNFT Type.
     * @return TangibleNFT contract reference
     */
    function newCategory(
        string calldata name,
        string calldata symbol,
        string calldata uri,
        bool isStoragePriceFixedAmount,
        bool storageRequired,
        address priceOracle,
        bool symbolInUri,
        uint256 _tnftType
    ) external onlyCategoryMinter returns (ITangibleNFT) {
        if (msg.sender != tangibleLabs) {
            require(numCategoriesToMint[msg.sender][_tnftType] > 0, "Can't create more");
            // reducing approved tnft creations
            numCategoriesToMint[msg.sender][_tnftType]--;
        }
        require(address(category[name]) == address(0), "CE");
        require(tnftDeployer != address(0), "Deployer zero");
        ITangibleNFT tangibleNFT = ITangibleNFTDeployer(tnftDeployer).deployTnft(
            name,
            symbol,
            uri,
            isStoragePriceFixedAmount,
            storageRequired,
            symbolInUri,
            _tnftType
        );
        category[name] = tangibleNFT;
        _tnfts.push(tangibleNFT);
        categoryOwner[tangibleNFT] = msg.sender;

        //for rent management
        (bool added, bool _rent, ) = ITNFTMetadata(tnftMetadata).tnftTypes(_tnftType);
        require(added, "tnftType not added");
        if (_rent) {
            IRentManager _rentManager = IRentManagerDeployer(rentManagerDeployer).deployRentManager(
                address(tangibleNFT)
            );
            rentManager[tangibleNFT] = _rentManager;
        }

        //set the oracle
        ITangiblePriceManager(priceManager).setOracleForCategory(
            tangibleNFT,
            IPriceOracle(priceOracle)
        );
        // update what owner owns
        if (msg.sender == tangibleLabs) {
            ownedByLabs.push(tangibleNFT);
        }

        fingerprintApprovalManager[tangibleNFT] = msg.sender;

        emit NewCategoryDeployed(address(tangibleNFT), msg.sender);
        emit CategoryOwner(address(tangibleNFT), msg.sender);
        return tangibleNFT;
    }

    /**
     * @notice This function allows a category owner to update the oracle for a category.
     * @param name Category.
     * @param priceOracle Address of PriceOracle contract.
     */
    function updateOracleForTnft(
        string calldata name,
        address priceOracle
    ) external onlyCategoryOwner(category[name]) {
        ITangiblePriceManager(priceManager).setOracleForCategory(
            category[name],
            IPriceOracle(priceOracle)
        );
    }

    /// @dev need to change, it should be whitelisting buyer per category of what is owner by category minter
    /**
     * @notice This function allows for a category owner to assign a whitelisted buyer to mint
     * @param tnft TangibleNFT contract that the `buyer` is/isnt whitelisted from.
     * @param buyer Address of whitelisted minter.
     * @param approved Status of whitelist. If true, `buyer` is whitelisted, otherwise false.
     */
    function whitelistBuyer(
        ITangibleNFT tnft,
        address buyer,
        bool approved
    ) external onlyCategoryOwner(tnft) {
        require(buyer != address(0), "Zero address");
        whitelistForBuyUnminted[tnft][buyer] = approved;
        emit WhitelistedBuyer(address(tnft), buyer, approved);
    }

    /**
     * @notice This function allows for the contract owner to whitelist a minter of a certain category.
     * @param minter Address to whitelist.
     * @param approved Status of whitelist. If true, able to mint. Otherwise false.
     * @param amount Amount of tokens the `minter` is allowed to mint.
     * @param _tnftType categories minter is allowed to create.
     */
    function whitelistCategoryMinter(
        address minter,
        bool approved,
        uint16 amount,
        uint256 _tnftType
    ) external onlyOwner {
        require(minter != address(0), "Zero address");
        (bool added, , ) = ITNFTMetadata(tnftMetadata).tnftTypes(_tnftType);
        require(added, "tnftType not added");
        categoryMinter[minter] = approved;
        numCategoriesToMint[minter][_tnftType] = amount;
        emit WhitelistedCategoryMinter(minter, approved, _tnftType, amount);
    }

    /**
     * @notice This function allows a category owner to assign a whitelist status to a category.
     * @param tnft TangibleNFT contract.
     * @param required Bool of whether or not whitelist is required to mint from the category.
     */
    function setRequireWhitelistCategory(
        ITangibleNFT tnft,
        bool required
    ) external onlyCategoryOwner(tnft) {
        onlyWhitelistedForUnmintedCategory[tnft] = required;
    }

    /**
     * @notice This function allows the category owner to add a storage expiration to a category.
     * @param tnft TangibleNFT contract.
     * @param numDays amount of days before storage expires.
     */
    function setCategoryStorageExpire(
        ITangibleNFT tnft,
        uint256 numDays
    ) external onlyCategoryOwner(tnft) {
        daysBeforeSeize[tnft] = numDays;
    }

    /**
     * @notice This function allows a category owner to seize NFTs that are expired
     * @dev If a token is expired, the storage has not been paid for.
     * @param tnft TangibleNFT contract.
     * @param tokenIds Array of tokenIds to seize.
     */
    function seizeTnft(
        ITangibleNFT tnft,
        uint256[] memory tokenIds
    ) external onlyCategoryOwner(tnft) {
        uint256 length = tokenIds.length;
        uint256 expiryDays = daysBeforeSeize[tnft] != 0
            ? daysBeforeSeize[tnft]
            : DEFAULT_SEIZE_DAYS;
        for (uint256 i; i < length; ) {
            uint256 token = tokenIds[i];

            require(tnft.storageEndTime(token) + expiryDays * 1 days < block.timestamp);

            address ownerTnft = tnft.ownerOf(token);
            tnft.safeTransferFrom(ownerTnft, categoryOwner[tnft], token);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This view function is used to return whether or not a specified address is the contract owner.
     * @param account EOA to check owner status.
     * @return If true, account is the contract owner otherwise will be false.
     */
    function isOwner(address account) internal view returns (bool) {
        return owner() == account;
    }

    /**
     * @notice This view function is used to return whether or not a specified address is the Marketplace contract.
     * @param account address to query marketplace status.
     * @return If true, account is the address of the Marketplace contract.
     */
    function isMarketplace(address account) internal view returns (bool) {
        return marketplace == account;
    }

    /**
     * @notice This internal method is used to check if msg.sender is a category owner.
     * @dev Only called by modifier `onlyCategoryOwner`. Meant to reduce bytecode size
     */
    function _checkCategoryOwner(ITangibleNFT nft) internal view {
        require(
            address(nft) != address(0) && categoryOwner[nft] == msg.sender,
            "Caller is not category owner"
        );
    }
}
