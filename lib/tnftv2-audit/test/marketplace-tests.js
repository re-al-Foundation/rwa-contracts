const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const {
    loadFixture,
    mine,
    time
  } = require("@nomicfoundation/hardhat-network-helpers");

const hre = require("hardhat");
const { tnftTypes } = require("../hardhat-config-utils")

require('dotenv').config();
const { fingerprints, weSellAt, lockedAmount, weSellAtStock, currency, location} = require("./helpers/reData.json");


describe.only("TNFT Ecosystem", () => {
    let deployer, dai, vendorWine,  operator, randomUser, feeStorageAddress, marketplace, usdc, factoryContract, goldTnft, GoldNFT;
    let randomUser2, randomUser3, randomUser4, sellFeeDistributor, rentManager;
    let goldOracle, reOracle, priceManager, tnftDeployer, mockRevenueShare;
    let mockOracle, tnftMetadata, tngbl, mockrouter, mockPassiveNft, feeSellAddress, realEstate, RealEstateNFT;
    let exchange, rentDeployer, tangibleReaderHelper, onSaleTracker, RentManager;
    let usdr, mockUSDoracle, currencyFeed, mockGBPOracle, mockMatrixOracle;
    //!fixedStorage, storageRequired, goldOracle.target, !paysRent
    const fixedStorage = true;
    const storageRequired = true;
    const paysRent = true;
    const zeroAddress = '0x0000000000000000000000000000000000000000';
    const oneAddress = '0x0000000000000000000000000000000000000001';
    function getNewEmptyVoucher(){
        return {
            token: zeroAddress,
            mintCount: 1,
            price: 0,
            vendor: zeroAddress,
            buyer: zeroAddress,
            fingerprint: 1,
            sendToVendor: false
        };
    }

    const payStorage = async function (nft, tokenId, years, from){
        const bal1 = await usdr.balanceOf(tangibleLabs.address);
        await marketplace.connect(from).payStorage(
            nft.target,
            usdr.target,
            tokenId,
            years
        );

        const bal2 = await usdr.balanceOf(tangibleLabs.address);

        expect(Number(bal1) < Number(bal2)).to.be.true;
    }

    async function impersonateContract(address){
        //Impersonate the contrat to make calls
        const contractSigner = await ethers.getSigner(address);

        return contractSigner;
    }

    async function populateOracle(oracle) {
        for (let i = 0; i < fingerprints.length; i++) {
            await oracle.createItem(
                fingerprints[i],
                weSellAt[i],
                lockedAmount[i],
                weSellAtStock[i],
                currency[i],
                location[i]
                );
        }
    }
    
    async function populateFingerprintsInReTnft() {
        const res = [];
        for (let i = 0; i < fingerprints.length; i++) {
            res.push("house"+fingerprints[i]);
            
        }
        await RealEstateNFT.connect(tangibleLabs).addFingerprints(
            fingerprints
        );
    }    

    async function deployContracts() {
        //deploy usdc
        const USDC = await ethers.getContractFactory("USDCMock");
        usdc = await USDC.deploy();
        await usdc.waitForDeployment();;

        //deploy usdc
        const USDR = await ethers.getContractFactory("USDRMock");
        usdr = await USDR.deploy();
        await usdr.waitForDeployment();

        //deploy dai
        const DAI = await ethers.getContractFactory("DAIMock");
        dai = await DAI.deploy();
        await dai.waitForDeployment();

        //deploy tngbl
        const TNGBL = await ethers.getContractFactory("TNGBLMock");
        tngbl = await TNGBL.deploy();
        await tngbl.waitForDeployment();

        //deploy MockMatrixOracle
        const MockMatrixOracle = await ethers.getContractFactory("MockMatrixOracle");
        mockMatrixOracle = await MockMatrixOracle.deploy();
        await mockMatrixOracle.waitForDeployment(); 
        await populateOracle(mockMatrixOracle);
        

        //deploy mock chainlink oracle
        const MockOracle = await ethers.getContractFactory("EACAggregatorProxy");
        mockOracle = await MockOracle.deploy();

        //deploy usd oracle
        const USDOracle = await ethers.getContractFactory("UsdUsdOracle");
        mockUSDoracle = await USDOracle.deploy();

        //deploy Mock GBP oracle
        const MockGBPUSDOracle = await ethers.getContractFactory("MockGBPUSDOracle");
        mockGBPOracle = await MockGBPUSDOracle.deploy();
        await mockGBPOracle.waitForDeployment();

        //deploy factory
        const Factory = await ethers.getContractFactory("FactoryV2");
        factoryContract = await upgrades.deployProxy(Factory, [usdr.target, tangibleLabs.address]);
        await factoryContract.waitForDeployment();

        // deploy currency feed
        const CurrencyFeed = await ethers.getContractFactory("CurrencyFeedV2");
        currencyFeed = await upgrades.deployProxy(CurrencyFeed, [factoryContract.target]);
        await currencyFeed.waitForDeployment(); 
        console.log("owner factory: " + await factoryContract.owner());

        await currencyFeed.setCurrencyConversionPremium("GBP", 1000000);
        await currencyFeed.setISOCurrencyData("GBP", 826);
        await currencyFeed.setISOCountryData("GBR", 826);
        await currencyFeed.setISOCurrencyData("USD", 840);
        await currencyFeed.setISOCountryData("USA", 840);
        await currencyFeed.setISOCurrencyData("XAU", 959);
        await currencyFeed.setCurrencyFeed("GBP", mockGBPOracle.target);
        await currencyFeed.setCurrencyFeed("XAU", mockOracle.target);
        await currencyFeed.setCurrencyFeed("USA", mockUSDoracle.target);
        // ENABLE TO HAVE CONVERSION PREMIUM
        // await currencyFeed.setCurrencyConversionPremium("GBP", 1000000);

        //deploy oracles
        const GoldOracle = await ethers.getContractFactory("GoldOracleTangibleV2");
        goldOracle = await upgrades.deployProxy(GoldOracle, [factoryContract.target, currencyFeed.target]);
        await goldOracle.waitForDeployment(); 

        const RealEstateOracle = await ethers.getContractFactory("RealtyOracleTangibleV2");
        reOracle = await upgrades.deployProxy(RealEstateOracle, [factoryContract.target, currencyFeed.target, mockMatrixOracle.target]);
        await reOracle.waitForDeployment(); 

        //deploy mockRouter
        const MockRouter = await ethers.getContractFactory("MockRouter");
        mockrouter = await MockRouter.deploy();
        await mockrouter.waitForDeployment();

        //deploy mockPassiveNft
        const MockPassiveIncomeNFT = await ethers.getContractFactory("MockPassiveIncomeNFT");
        mockPassiveNft = await MockPassiveIncomeNFT.deploy();
        await mockPassiveNft.waitForDeployment();

        //deploy mockRevenueShare
        const MockRevenueShare = await ethers.getContractFactory("MockRevenueShare");
        mockRevenueShare = await MockRevenueShare.deploy();
        await mockRevenueShare.waitForDeployment();

        //deploy Exchange
        const Exchange = await ethers.getContractFactory("ExchangeV2");
        exchange = await upgrades.deployProxy(Exchange, [factoryContract.target]);
        await exchange.waitForDeployment();

        tx = await exchange.addRouterForTokens(
            usdr.target,
            dai.target,
            mockrouter.target,
            [],
            [],
            true, // simple swap
            true
        );
        tx = await exchange.addRouterForTokens(
            usdc.target,
            dai.target,
            mockrouter.target,
            [{from:usdc.target, to: usdr.target, stable:true}, {from:usdr.target, to: dai.target, stable:true}],
            [{from:dai.target, to: usdr.target, stable:true}, {from:usdr.target, to: usdc.target, stable:true}],
            true, // simple swap
            true
        );
        tx = await exchange.addRouterForTokens(
            usdr.target,
            usdc.target,
            mockrouter.target,
            [],
            [],
            true, // simple swap
            true
        );
        tx = await exchange.addRouterForTokens(
            usdr.target,
            usdc.target,
            mockrouter.target,
            [],
            [],
            true, // simple swap
            true
        );
        tx = await exchange.addRouterForTokens(
            usdr.target,
            tngbl.target,
            mockrouter.target,
            [],
            [],
            true, // simple swap
            false
        );

        //deploy SellFeeDistributor
        const SellFeeDistributor = await ethers.getContractFactory("SellFeeDistributorV2");
        sellFeeDistributor = await upgrades.deployProxy(SellFeeDistributor, [factoryContract.target, mockRevenueShare.target, usdc.target, tngbl.target, false]);
        await sellFeeDistributor.waitForDeployment();
        await sellFeeDistributor.setExchange(exchange.target);

        //deploy tnft deployer, must be before newCategory is called
        const TnftDeployer = await ethers.getContractFactory("TangibleNFTDeployerV2");
        tnftDeployer = await upgrades.deployProxy(TnftDeployer, [factoryContract.target]);
        await tnftDeployer.waitForDeployment();
        
        // deploy price manager
        const PriceManager = await ethers.getContractFactory("TangiblePriceManagerV2");
        priceManager = await upgrades.deployProxy(PriceManager, [factoryContract.target]);
        await priceManager.waitForDeployment();

        //deploy rent deployer, must be before newCategory is called
        const RentDeployer = await ethers.getContractFactory("RentManagerDeployer");
        rentDeployer = await upgrades.deployProxy(RentDeployer, [factoryContract.target]);
        await rentDeployer.waitForDeployment();

        //deploy tnft metadata, must be before newCategory is called
        const TNFTMetadata = await ethers.getContractFactory("TNFTMetadata");
        tnftMetadata = await upgrades.deployProxy(TNFTMetadata, [factoryContract.target]);
        await tnftMetadata.waitForDeployment();

        //deploy onSaleTracker
        const OST = await ethers.getContractFactory("OnSaleTracker");
        onSaleTracker = await upgrades.deployProxy(OST, [factoryContract.target]);
        await onSaleTracker.waitForDeployment();

        //deploy and set marketplace
        const Marketplace = await ethers.getContractFactory("TNFTMarketplaceV2");
        marketplace = await upgrades.deployProxy(Marketplace, [factoryContract.target]);
        await marketplace.waitForDeployment();
        await marketplace.setSellFeeAddress(sellFeeDistributor.target);
        await marketplace.setOnSaleTracker(onSaleTracker.target);
        // configure onSale tracker
        await onSaleTracker.setMarketplace(marketplace.target);
        
        // configure factory
        // setting labs is 3 (already set)
        await factoryContract.setContract(1, tnftDeployer.target);
        await factoryContract.setContract(0, marketplace.target);
        await factoryContract.setContract(5, tnftMetadata.target);
        await factoryContract.setContract(6, mockRevenueShare.target);
        await factoryContract.setContract(4, priceManager.target);
        await factoryContract.setContract(2, rentDeployer.target);
        
        //deploy tangible reader helper
        const TRH = await ethers.getContractFactory("TangibleReaderHelperV2");
        tangibleReaderHelper = await TRH.deploy(factoryContract.target, mockPassiveNft.target, mockRevenueShare.target);
        await tangibleReaderHelper.waitForDeployment();

        // set tnft metadata
        for(const type of tnftTypes) {
            tx = await tnftMetadata.addTNFTType(
                type.id,
                type.description,
                type.paysRent
            );
            console.log(`type ${type.id} ${type.description} submitted. pays rent ${type.paysRent}`);
        }
        //add 2 categories, gold and real estate
        //gold !fixedStorage, storageRequired, goldOracle.target, !paysRent
        tx = await factoryContract.connect(tangibleLabs).newCategory(
            "TangibleGoldBar",
            "TanXAU",
            "https://github.com/ethers-io/ethers.js/issues",
            !fixedStorage, 
            storageRequired, 
            goldOracle.target,
            true, // symbol in uri
            1 // tnft type previously added
        );
        const newCategoryResult = await tx.wait();
        const [categoryEvent] = await newCategoryResult.logs.filter(
            (evt) => evt.eventName === "NewCategoryDeployed"
        );
        const categoryDepployed = categoryEvent.args[0];
        goldTnft = await factoryContract.category("TangibleGoldBar");
        expect(categoryDepployed).equal(goldTnft);

        //house
        const tx2 = await factoryContract.connect(tangibleLabs).newCategory(
            "RealEstate",
            "RLTY",
            "https://github.com/ethers-io/ethers.js/issues",
            fixedStorage,
            !storageRequired,
            reOracle.target,
            true,
            2
        );
        
        const newCategoryResult2 = await tx2.wait();
        const [categoryEvent2] = await newCategoryResult2.logs.filter(
            (evt) => evt.eventName === "NewCategoryDeployed"
        );
        const categoryDepployed2 = categoryEvent2.args[0];
        realEstate = await factoryContract.category("RealEstate");
        expect(categoryDepployed2).equal(realEstate);
        //set contracts
        const GOLD = await ethers.getContractFactory("TangibleNFTV2");
        const REALESTATE = await ethers.getContractFactory("TangibleNFTV2");
        const RENTMANAGER = await ethers.getContractFactory("RentManager");
        rentManager = await factoryContract.rentManager(realEstate);
        GoldNFT = await GOLD.attach(goldTnft);
        RealEstateNFT = await REALESTATE.attach(realEstate);
        RentManager = await RENTMANAGER.attach(rentManager);

        //special setup for gold oracle 
        await GoldNFT.connect(tangibleLabs).addFingerprints([1,2,3,4]);
        await GoldNFT.connect(tangibleLabs).setStoragePercentPricePerYear(10);
        await goldOracle.connect(tangibleLabs).addGoldBar( 1, 100);
        await goldOracle.connect(tangibleLabs).addGoldBar( 2, 250);
        await goldOracle.connect(tangibleLabs).addGoldBar( 3, 500);
        await goldOracle.connect(tangibleLabs).addGoldBar( 4, 1000);
        await goldOracle.connect(tangibleLabs).addGoldBarStock( 1, 5);
        await goldOracle.connect(tangibleLabs).addGoldBarStock( 2, 5);
        await goldOracle.connect(tangibleLabs).addGoldBarStock( 3, 5);
        await goldOracle.connect(tangibleLabs).addGoldBarStock( 4, 5);
        
        //re oracle setup
        await populateFingerprintsInReTnft(RealEstateNFT);

        await tnftMetadata.addFeatures(
            [1,2,3,4,5,6,7,8],
            ["beach","river","mountain","flat","balcony","backyard","pool","coin"]
        );

        // for real estate
        await tnftMetadata.addFeaturesForTNFTType( 2, [1,2,3,4,5,6,7]);
        // for gold bars
        await tnftMetadata.addFeaturesForTNFTType( 1, [8]);

        await factoryContract.configurePaymentToken(usdr.target, true);
        await factoryContract.configurePaymentToken(usdc.target, true);
                        
    }
    
    beforeEach(async () => {
        [deployer, tangibleLabs, vendorWine, operator, randomUser, feeSellAddress, feeStorageAddress, randomUser2, randomUser3, randomUser4]=await ethers.getSigners();
        
        await loadFixture(deployContracts);
        //do some money minting and approval
        usdr.mint(deployer.address, 3000000000000000); //3 000 000 USD
        usdr.mint(tangibleLabs.address, 3000000000000000); //3 000 000 USD
        usdr.mint(operator.address, 3000000000000000); // 3 000 000 USD
        usdr.mint(randomUser.address, 3000000000000000); // 3 000 000 USD
        usdr.mint(randomUser.address, 3000000000000000); // 3 000 000 USD
        usdr.mint(randomUser.address, 3000000000000000); // 3 000 000 USD
        usdr.mint(randomUser2.address, 3000000000000000); // 3 000 000 USD
        usdr.mint(randomUser3.address, 3000000000000000); // 3 000 000 USD
        usdr.mint(randomUser4.address, 3000000000000000); // 3 000 000 USD

        //approve spending 
        usdr.approve(marketplace.target, 300000000000000);
        usdr.connect(randomUser).approve(marketplace.target, 3000000000000000);
        usdr.connect(randomUser2).approve(marketplace.target, 300000000000000);
        usdr.connect(randomUser3).approve(marketplace.target, 300000000000000);
        usdr.connect(randomUser4).approve(marketplace.target, 300000000000000);
        usdr.connect(tangibleLabs).approve(marketplace.target, 300000000000000);
        usdr.connect(tangibleLabs).approve(RentManager.target, 300000000000000);
        usdr.connect(randomUser).approve(RentManager.target, 300000000000000);

        //do some money minting and approval
        usdc.mint(deployer.address, 300000000000000); //300 000 000 USD
        usdc.mint(tangibleLabs.address, 300000000000000); //300 000 000 USD
        usdc.mint(operator.address, 10000000000000); // 10 000 000 USD
        usdc.mint(randomUser.address, 3000000000000000); // 30 000 000 USD
        usdc.mint(randomUser.address, 3000000000000000); // 30 000 000 USD
        usdc.mint(randomUser.address, 3000000000000000); // 30 000 000 USD
        usdc.mint(randomUser2.address, 30000000000000); // 30 000 000 USD
        usdc.mint(randomUser3.address, 30000000000000); // 30 000 000 USD
        usdc.mint(randomUser4.address, 30000000000000); // 30 000 000 USD

        //approve spending 
        usdc.approve(marketplace.target, 300000000000);
        usdc.connect(randomUser).approve(marketplace.target, 300000000000000);
        usdc.connect(randomUser2).approve(marketplace.target, 300000000000);
        usdc.connect(randomUser3).approve(marketplace.target, 300000000000);
        usdc.connect(randomUser4).approve(marketplace.target, 300000000000);
        usdc.connect(tangibleLabs).approve(marketplace.target, 300000000000);
        usdc.connect(tangibleLabs).approve(RentManager.target, 300000000000);
        usdc.connect(randomUser).approve(RentManager.target, 300000000000);

        //do some money minting and approval
        dai.mint(deployer.address, 300000000000000); //300 000 000 USD
        dai.mint(tangibleLabs.address, 300000000000000); //300 000 000 USD
        dai.mint(operator.address, 10000000000000); // 10 000 000 USD
        dai.mint(randomUser.address, 3000000000000000); // 30 000 000 USD
        dai.mint(randomUser.address, 3000000000000000); // 30 000 000 USD
        dai.mint(randomUser.address, 3000000000000000); // 30 000 000 USD
        dai.mint(randomUser2.address, 30000000000000); // 30 000 000 USD
        dai.mint(randomUser3.address, 30000000000000); // 30 000 000 USD
        dai.mint(randomUser4.address, 30000000000000); // 30 000 000 USD

        //approve spending 
        dai.approve(marketplace.target, 300000000000);
        dai.connect(randomUser).approve(marketplace.target, 300000000000000);
        dai.connect(randomUser2).approve(marketplace.target, 300000000000);
        dai.connect(randomUser3).approve(marketplace.target, 300000000000);
        dai.connect(randomUser4).approve(marketplace.target, 300000000000);
        dai.connect(tangibleLabs).approve(marketplace.target, 300000000000);
        dai.connect(tangibleLabs).approve(RentManager.target, 300000000000);
        dai.connect(randomUser).approve(RentManager.target, 300000000000);

    });

    describe("TNFT tests", () => {
        it("should update uri", async () => {
            await GoldNFT.connect(tangibleLabs).setBaseURI("https://polygonscan.com/address/0xdA1Ba73Ef1598260fde3472B74057731D21cC7034");
            const url = await GoldNFT.baseSymbolURI();
            expect(url).to.equal("https://polygonscan.com/address/0xdA1Ba73Ef1598260fde3472B74057731D21cC7034/TanXAU/");
        });

        it("should check symbol in uri", async () => {
            const symb = await GoldNFT.symbolInUri();
            expect(symb).to.be.true;
        })
    
        it("should not update uri, because the wallet is not category owner", async () => {
            await expect( GoldNFT.connect(deployer).setBaseURI("https://polygonscan.com/address/0xdA1Ba73Ef1598260fde3472B74057731D21cC7034"))
                .to.be.revertedWith("NCO");
        });
    
        it("should check producing TNFT - not factory, factory owner", async () => {
            await expect( GoldNFT.produceMultipleTNFTtoStock.staticCall(1,1, deployer.address))
                .to.be.revertedWith("NFA");
        });
    
        it("should check producing TNFT - not factory, trying with randomUser", async () => {
            await expect(GoldNFT.connect(randomUser).produceMultipleTNFTtoStock(1,1, deployer.address))
                .to.be.revertedWith("NFA");
        });
    
        it("should fail producing - only factory does is", async () =>{
             await expect(GoldNFT.produceMultipleTNFTtoStock.staticCall(1,1, deployer.address))
                .to.be.revertedWith("NFA");
        })

        it("should fail minting when caller is not the labs", async () =>{
            const voucher = getNewEmptyVoucher();
            voucher.buyer = deployer.address;
            voucher.fingerprint = 5;
            voucher.mintCount = 1;
            voucher.sendToVendor = true;
            voucher.token = GoldNFT.target;
            await expect(factoryContract.mint(voucher))
               .to.be.revertedWith("Factory: caller is not the labs nor marketplace");
        })

        it("should fail producing when fingerprint is not added", async () =>{
            const impersonateFactory = await impersonateContract(factoryContract.target);
            await expect( GoldNFT.connect(impersonateFactory).produceMultipleTNFTtoStock.staticCall(1,5, deployer.address))
                    .to.be.revertedWith("FNA");
        })
    
        it("should check added fingerprints 1 and 2", async () =>{
            const approvedFingerprints = await  GoldNFT.getFingerprints();
            expect(approvedFingerprints[0]).equal(1);
            expect(approvedFingerprints[1]).equal(2);
        })

        it("should check that there are no fingerprints 1 and 2 in RE", async () =>{
            const approvedFingerprints = await  RealEstateNFT.getFingerprints();
            const size = await RealEstateNFT.getFingerprintsSize();
            expect(approvedFingerprints.includes(1)).to.be.false;
            expect(approvedFingerprints[0]).to.be.eq(1329);
            expect(Number(size)).to.be.eq(fingerprints.length);
        })

        it("should forbid adding fingerprint if not fingerprint approver", async () =>{
            await expect( GoldNFT.addFingerprints([2]))
                .to.be.revertedWith("NFAP");
        })

        it("should forbid adding fingerprint that already exists", async () =>{
            const apManager = await factoryContract.fingerprintApprovalManager(GoldNFT.target);
            expect(apManager).to.be.equal(tangibleLabs.address);
            await expect( GoldNFT.connect(tangibleLabs).addFingerprints([2]))
                .to.be.revertedWith("FAA");
        })
    
        it("should check producing TNFT - with factory", async () => {
            const impersonateFactory = await impersonateContract(factoryContract.target);
            const tokennId = await GoldNFT.connect(impersonateFactory).produceMultipleTNFTtoStock.staticCall(1,1, tangibleLabs.address);
            expect(Number(tokennId[0])).equal(Number(0x01));
        });
    
        it("should check producing TNFT - with factory multiple tokens", async () => {
            const impersonateFactory = await impersonateContract(factoryContract.target);
            const tokennIds = await GoldNFT.connect(impersonateFactory).produceMultipleTNFTtoStock.staticCall(3,1, tangibleLabs.address);
            expect(Number(tokennIds[0])).equal(Number(0x01));
            expect(Number(tokennIds[1])).equal(Number(0x02));
            expect(Number(tokennIds[2])).equal(Number(0x03));
        });
    
        it("should burn tnft - minter approved factory owns it", async () => {
            const voucher = getNewEmptyVoucher();
            voucher.vendor = tangibleLabs.address;
            voucher.fingerprint = 1;
            voucher.mintCount = 3;
            voucher.sendToVendor = true;
            voucher.token = GoldNFT.target;
            const tokennIdTx = await factoryContract.connect(tangibleLabs).mint(voucher);
            const tokkenIdResult = await tokennIdTx.wait();
            const [tokkenIdEvent] = await tokkenIdResult.logs.filter(
                (evt) => evt.eventName === "MintedTokens"
              );
            const tokennIds = tokkenIdEvent.args[1];
            // note add approve for factory!!
             expect(await GoldNFT.connect(tangibleLabs).burn( tokennIds[0]))
                    .to.be.ok;
            await expect( GoldNFT.ownerOf(tokennIds[0])).to.be.revertedWithCustomError(GoldNFT,"ERC721NonexistentToken");
    
        });

        it("should fail to mint - not sending to himself", async () => {
            const voucher = getNewEmptyVoucher();
            voucher.vendor = deployer.address;
            voucher.fingerprint = 1;
            voucher.mintCount = 3;
            voucher.sendToVendor = true;
            voucher.token = GoldNFT.target;
            await expect( factoryContract.connect(tangibleLabs).mint(voucher)).to.be.revertedWith("MFSE");
    
        });
    
        it("should check initial storage price - 20$", async () => {
            const storagePrice = await GoldNFT.storagePricePerYear();
            expect(storagePrice).to.equal(2000);
        });
    
        it("should check initial storage percentage - 1%", async () => {
            const storagePrice = await GoldNFT.storagePercentagePricePerYear();
            expect(storagePrice).to.equal(10);
        });
    
        it("should be able to set storage price to 90", async () => {
            await GoldNFT.connect(tangibleLabs).setStoragePricePerYear(Number(9000));
            const storagePrice = await GoldNFT.storagePricePerYear();
            expect(storagePrice).to.equal(9000);
            
        });
    
        it("should not revert set storage price - 0", async () => {
            await GoldNFT.connect(tangibleLabs).setStoragePricePerYear(Number(0));
            const storagePrice = await GoldNFT.storagePricePerYear();
            expect(storagePrice).to.equal(0);
            
        });
    
        it("should set storage percentage - 0", async () => {
            await GoldNFT.connect(tangibleLabs).setStoragePercentPricePerYear(Number(0));
            const storagePrice = await GoldNFT.storagePercentagePricePerYear();
            expect(storagePrice).to.equal(0);
        });
    
        it("should revert storage price - not category owner", async () => {
            await expect(GoldNFT.setStoragePricePerYear(Number(900000))).to.be.revertedWith("NCO");
        });
    
        it("should revert storage price - not category owner", async () => {
            await expect(GoldNFT.setStoragePercentPricePerYear(Number(60))).to.be.revertedWith("NCO");
        });
    
        it("should check fee switch - percentage in Gold", async () => {
            const check = await GoldNFT.connect(tangibleLabs).storagePriceFixed();
            await expect(check).equal(false);
        });
    
        it("should change fee switch - fixed", async () => {
            await GoldNFT.connect(tangibleLabs).toggleStorageFee(false);
            const check = await GoldNFT.storagePriceFixed();
            await expect(check).equal(false);
        });

        it("shouldn't add feature to unminted token", async () => {
            await expect(RealEstateNFT.connect(tangibleLabs).addMetadata(0x01, [1,2,3,4,5,6]))
                .to.be.revertedWith("token not minted");
        });

        it("should add feature to minted token", async () => {
            const voucher = getNewEmptyVoucher();
            voucher.vendor = tangibleLabs.address;
            voucher.fingerprint = 2168;
            voucher.mintCount = 1;
            voucher.sendToVendor = true;
            voucher.token = RealEstateNFT.target;
            const tokennIdTx = await factoryContract.connect(tangibleLabs).mint(voucher);
            expect(await RealEstateNFT.connect(tangibleLabs).addMetadata(0x01, [1,2,3,4,5,6]))
                .to.be.ok;
        });


        it("should remove feature from token", async () => {
            const voucher = getNewEmptyVoucher();
            voucher.vendor = tangibleLabs.address;
            voucher.fingerprint = 2168;
            voucher.mintCount = 1;
            voucher.sendToVendor = true;
            voucher.token = RealEstateNFT.target;
            const tokennIdTx = await factoryContract.connect(tangibleLabs).mint(voucher);
            await RealEstateNFT.connect(tangibleLabs).addMetadata(0x01, [1,2,3,4,5,6]);
            const tokenFeatures = await RealEstateNFT.getTokenFeatures(0x01);
            expect(await RealEstateNFT.connect(tangibleLabs).removeMetadata(0x01,[2,6,5,4])).to.be.ok;
            const tokenFeaturesAfter = await RealEstateNFT.getTokenFeatures(0x01);
            expect(tokenFeatures.length).equal(6);
            expect(tokenFeaturesAfter.length).equal(2);
        });
    
        it("empty to copy/paste", async () => {
        
        });
    });

    describe("TNFT Factory tests", () => {
    
        it("should revert changing feeAddress by anyone other than admin", async () => {
            await expect( factoryContract.connect(tangibleLabs).setContract(0,randomUser.address))
                .to.be.revertedWithCustomError(factoryContract,"OwnableUnauthorizedAccount");
        })
    
        it("should check contract owner", async () => {
            const owner = await factoryContract.owner();
            expect(owner).eq(deployer.address);
        })
    
        it("should transfer ownership, to new user", async ()=> {
           expect( await factoryContract.transferOwnership(randomUser3.address)).to.be.ok;
           expect( await factoryContract.connect(randomUser3).acceptOwnership()).to.be.ok;
    
           await expect(factoryContract.setContract(6,randomUser.address)).to.be.revertedWithCustomError(factoryContract,"OwnableUnauthorizedAccount");
           
           const owner = await factoryContract.owner();
           expect(owner).to.be.equal(randomUser3.address);
        })
    
        it("should revert when setting marketplace to 0x0", async () => {
            await expect(factoryContract.setContract(0,zeroAddress)).to.be.revertedWith("WADD");
        })
    
        it("should revert changing marketplace by anyone other than factory", async () => {
            await expect(factoryContract.connect(tangibleLabs).setContract(0,marketplace.target)).to.be.revertedWithCustomError(factoryContract,"OwnableUnauthorizedAccount");
        })
    
        it("should revert adding new category - not category minter/creator", async () => {
            await expect(factoryContract
                .newCategory("GoldBar25g", "GB25", "https://github.com/ethers-io/ethers.js/issues", !fixedStorage, storageRequired, goldOracle.target, !paysRent, 1))
                .to.be.revertedWith("Caller is not category minter");
            
        })

        it("should approve another seller for the protocol", async () => {
            await factoryContract.whitelistCategoryMinter(randomUser.address,true, 1, 1);
            const isApproved = await factoryContract.categoryMinter(randomUser.address);
            expect(isApproved).to.be.true;
            const amount = await factoryContract.numCategoriesToMint(randomUser.address, 1);
            const amount2 = await factoryContract.numCategoriesToMint(randomUser.address, 2);
            expect(amount).equal(1);
            expect(amount2).equal(0);
            
        })

        it("should approve another seller for the protocol and he should create", async () => {
            await factoryContract.whitelistCategoryMinter(randomUser.address,true, 1, 1);
            const isApproved = await factoryContract.categoryMinter(randomUser.address);
            expect(isApproved).to.be.true;
            const amount = await factoryContract.numCategoriesToMint(randomUser.address, 1);
            const amount2 = await factoryContract.numCategoriesToMint(randomUser.address, 2);
            expect(amount).equal(1);
            expect(amount2).equal(0);

            tx = await factoryContract.connect(randomUser).newCategory(
                "RandomGoldBar",
                "RanXAU",
                "https://github.com/ethers-io/ethers.js/issues",
                !fixedStorage, 
                storageRequired, 
                goldOracle.target,
                true, // symbol in uri
                1 // tnft type previously added
            );
            const newCategoryResult = await tx.wait();
            const [categoryEvent] = await newCategoryResult.logs.filter(
                (evt) => evt.eventName === "NewCategoryDeployed"
            );
            const categoryDepployed = categoryEvent.args[0];
            const ranTnft = await factoryContract.category("RandomGoldBar");
            expect(categoryDepployed).equal(ranTnft);

            const RanFactory = await ethers.getContractFactory("TangibleNFTV2");
            const RanTNFT =  RanFactory.attach(ranTnft);

            await expect( RanTNFT.connect(tangibleLabs).toggleStorageFee(false)).to.be.revertedWith("NCO")
            await expect( RanTNFT.toggleStorageFee(false)).to.be.revertedWith("NCO")
            expect(await RanTNFT.connect(randomUser).toggleStorageFee(false)).to.be.ok;
            
        })
    
        describe("When gold exist", () => {
    
            it("should revert when adding existing category", async () => {
                await expect(factoryContract.connect(tangibleLabs).newCategory(
                    "RealEstate",
                    "RLTY",
                    "https://github.com/ethers-io/ethers.js/issues",
                    fixedStorage,
                    !storageRequired,
                    reOracle.target,
                    true,
                    2
                ))
                    .to.be.revertedWith("CE");
            })
    
            describe("Minting new tnfts", () => {
    
                it("should mint tokens check ids", async () => {
                    const voucher = getNewEmptyVoucher();
                    voucher.token = goldTnft;
                    voucher.vendor = tangibleLabs.address;
                    voucher.mintCount = 3;
                    const tx = await factoryContract.connect(tangibleLabs).mint(voucher);
                    const result = await tx.wait();
                    const [tokenIdsEvent] = await result.logs.filter(
                        (evt) => evt.eventName === "MintedTokens"
                    );
                    const tokennIds = tokenIdsEvent.args[1];
                    expect(Number(tokennIds[0])).equal(Number(0x01));
                    expect(Number(tokennIds[1])).equal(Number(0x02));
                    expect(Number(tokennIds[2])).equal(Number(0x03));
                })
    
                it("should check if marketplace is owner of minted tokens", async () => {
                    const voucher = getNewEmptyVoucher();
                    voucher.token = goldTnft;
                    voucher.vendor = tangibleLabs.address;
                    voucher.mintCount = 3;
                    const tx = await factoryContract.connect(tangibleLabs).mint(voucher);
                    const result = await tx.wait();
                    const [tokenIdsEvent] = await result.logs.filter(
                        (evt) => evt.eventName === "MintedTokens"
                    );
                    const tokennIds = tokenIdsEvent.args[1];
                    const owner1 = await GoldNFT.ownerOf(tokennIds[0]);
                    const owner2 = await GoldNFT.ownerOf(tokennIds[1]);
                    const owner3 = await GoldNFT.ownerOf(tokennIds[2]);
                    expect(owner1).equal(marketplace.target);
                    expect(owner2).equal(marketplace.target);
                    expect(owner3).equal(marketplace.target);
                })
    
                it("should mint only one token if req is comming from marketplace", async () => {
                    const voucher = getNewEmptyVoucher();
                    voucher.token = goldTnft;
                    voucher.mintCount = 3;
                    voucher.buyer = randomUser.address;
                    voucher.vendor = tangibleLabs.address;
                    const impersonateMarketplace = await impersonateContract(marketplace.target);
                    const tokenIds = await factoryContract.connect(impersonateMarketplace).mint.staticCall(voucher);
                    
                    expect(tokenIds.length).equal(1);
                    
                    
                })
    
                it("should revert if buyer is not set and req is comming from marketplace", async () => {
                    const voucher = getNewEmptyVoucher();
                    voucher.token = goldTnft;
                    voucher.mintCount = 3;
                    voucher.vendor = tangibleLabs.address;
                    const impersonateMarketplace = await impersonateContract(marketplace.target);
                    await expect(factoryContract.connect(impersonateMarketplace).mint.staticCall(voucher))
                        .to.be.revertedWith("BMNBZ");
                    
                })

                it("should revert if vendor is not set and req is comming from marketplace", async () => {
                    const voucher = getNewEmptyVoucher();
                    voucher.token = goldTnft;
                    voucher.mintCount = 3;
                    voucher.buyer = randomUser.address;
                    const impersonateMarketplace = await impersonateContract(marketplace.target);
                    await expect(factoryContract.connect(impersonateMarketplace).mint.staticCall(voucher))
                        .to.be.revertedWith("MFSEO");
                })
    
                it("should fetch all tnfts/categories created", async () => {
                    const tnfts = await factoryContract.getCategories()
                    expect(tnfts[0]).equal(goldTnft);
                    expect(tnfts[1]).equal(realEstate);
                    expect(tnfts.length).equal(2);
                    
                })
    
                describe("Transfer ownership", () => {
                    beforeEach(async () => {
    
                        await factoryContract.transferOwnership(randomUser3.address);
                        await factoryContract.connect(randomUser3).acceptOwnership();
                    })
    
                    it("should not accept calling admin functions from deployer", async () => {
                        await expect(factoryContract.setContract(0,randomUser2.address)).to.be.revertedWithCustomError(factoryContract,"OwnableUnauthorizedAccount");
                    })
    
                    it("should accept calling admin functions from randomUser3", async () => {
                        expect(await factoryContract.connect(randomUser3).setContract(0,randomUser2.address)).to.be.ok;
                    })
    
                })
    
            })
        })
    });

    describe("TNFT Marketplace tests", () => {
        //address for storing fees
        it("should confirm initial sell fee address ", async () => {
            const feeAddress = await marketplace.sellFeeAddress();
            expect(feeAddress).equal(sellFeeDistributor.target);
        })

        it("should confirm initial balance 0", async () => {
            const balance = await usdc.balanceOf(feeSellAddress.address);
            expect(balance).equal(0);
        })

        it("should return unminted lot for non-existint nft", async () => {
            const lot = await tangibleReaderHelper.lotBatch(oneAddress, [0x0100000000000000000000000000000001n]);
            expect(lot[0].tokenId)
                .to.be.eq(0n);
        })

        it("should check initial sell fee to be 0% per category - contract uses default 2,5% in code", async () => {
            expect(await marketplace.feesPerCategory(realEstate)).to.equal(0);
            expect(await marketplace.feesPerCategory(goldTnft)).to.equal(0);
            
        })

        it("should change sell fee to be 3.5% ", async () => {
            await marketplace.connect(tangibleLabs).setFeeForCategory(goldTnft, 350);
            expect(await marketplace.feesPerCategory(goldTnft)).to.equal(350);
            await marketplace.connect(tangibleLabs).setFeeForCategory(realEstate, 10);
            expect(await marketplace.feesPerCategory(realEstate)).to.equal(10);
            
        })

        it("should fail to change sell fee to be 3.5% - not CATEGORY OWNER", async () => {
            await expect( marketplace.connect(randomUser).setFeeForCategory(goldTnft, 350)).to.be.revertedWith("NCO");
            
        })

        it("should fail buy and mint because token is not approved", async () => {
            await goldOracle.connect(tangibleLabs).addGoldBarStock( 1, 0);
            await expect( marketplace.connect(randomUser).buyUnminted(
                goldTnft,
                dai.target,
                1,
                1
            )).to.be.revertedWith("TNAPP");
            
        })

        it("should fail buy and mint because there is nothing to mint", async () => {
            await goldOracle.connect(tangibleLabs).addGoldBarStock( 1, 0);
            await expect( marketplace.connect(randomUser).buyUnminted(
                goldTnft,
                usdc.target,
                1,
                1
            )).to.be.revertedWith("!0S");
            
        })

        it("should not mint anything - 0 stock", async () => {
            await goldOracle.connect(tangibleLabs).addGoldBarStock( 1, 0);
            const voucher = getNewEmptyVoucher();
            voucher.mintCount = 1;
            voucher.token = GoldNFT.target;
            voucher.vendor = tangibleLabs.address;
            voucher.price = 2000000000;
            voucher.fingerprint = 1;

            await expect(factoryContract.connect(tangibleLabs).mint(voucher)).to.be.revertedWith("Not enough in stock");   
            
        })

        it("should sell for given price not oracle", async () => {

            const voucher = getNewEmptyVoucher();
            voucher.mintCount = 1;
            voucher.token = GoldNFT.target;
            voucher.vendor = tangibleLabs.address;
            voucher.price = 2000000000;
            voucher.fingerprint = 1;

            await factoryContract.connect(tangibleLabs).mint(voucher);

            const lot = await tangibleReaderHelper.lotBatch(goldTnft, [0x01n]);
            expect(lot[0].price).equal(2000000000);
            
            
        })

        it("should fetch batch oracle prices", async () => {

            
            const latestAnswer = await priceManager.itemPriceBatchFingerprints(realEstate,usdc.target,[2166,2175]);
            
            expect(latestAnswer[0][0]).to.be.equal(68243500000);
            expect(latestAnswer[0][1]).to.be.equal(510970200000);
            expect(latestAnswer[1][0]).to.be.equal(1);
            expect(latestAnswer[1][1]).to.be.equal(1);
            expect(latestAnswer[2][0]).to.be.equal(9313200000);
            expect(latestAnswer[2][1]).to.be.equal(63135800000);
            
        })

        it("should sell for price from RE oracle", async () => {

            const voucher = getNewEmptyVoucher();
            voucher.mintCount = 1;
            voucher.token = RealEstateNFT.target;
            voucher.vendor = tangibleLabs.address;
            voucher.price = 0;
            voucher.fingerprint = 2166;

            await factoryContract.connect(tangibleLabs).mint(voucher);

            const lot = await tangibleReaderHelper.lotBatch(realEstate, [0x01n]);
            
            expect(lot[0].price).equal(0);
            
            const lAnswer= await priceManager.itemPriceBatchTokenIds(realEstate,usdc.target,[0x01n]);
            
            expect(lAnswer.weSellAt[0]).to.be.equal(68243500000);
            expect(lAnswer.tokenizationCost[0]).to.be.equal(9313200000);
            
        })

        it("should buy and mint - initial sale no marketplace FEE!!!", async () => {

            const beforeSaleVendorBalance = await usdc.balanceOf(tangibleLabs.address);
            const beforeSaleBuyerBalance = await usdc.balanceOf(randomUser.address);
            const tx = await marketplace.connect(randomUser).buyUnminted(goldTnft, usdc.target ,1, 1);
            result = await tx.wait();

            const [boughtTokenEvent] = await result.logs.filter(
                (evt) => evt.eventName === "TnftBought"
            );
            const [storagePaidEvent] = await result.logs.filter(
                (evt) => evt.eventName === "StorageFeePaid"
            );
            const boughtArgs = boughtTokenEvent.args;
            const storageArgs = storagePaidEvent.args;
            const paidPriceEvent = boughtArgs.price;
            const paidStorageEvent = storageArgs.amount;

            const afterSaleVendorBalance = await usdc.balanceOf(tangibleLabs.address);
            const afterSaleBuyerBalance = await usdc.balanceOf(randomUser.address);
            const lAnswer = await priceManager.itemPriceBatchTokenIds(goldTnft,usdc.target,[0x01n]);
            const oraclePrice = lAnswer[0][0] + lAnswer[2][0];

            const feeBalance = await usdc.balanceOf(mockRevenueShare.target);
            const tokenOwner = await GoldNFT.ownerOf(0x01n);
            //first number is gold price second is storage fee of the price
            expect(paidPriceEvent).eq(lAnswer.weSellAt[0] + lAnswer.tokenizationCost[0])
            expect(beforeSaleBuyerBalance - afterSaleBuyerBalance).equal(5722832889n + 5722832n + lAnswer[2][0])
            expect(afterSaleVendorBalance - beforeSaleVendorBalance).equal(5722832889n + 5722832n);
            expect(afterSaleVendorBalance - beforeSaleVendorBalance).equal(oraclePrice - feeBalance + 5722832n);
            expect(feeBalance).equal(0); // sell fee is 2.5%
            expect(lAnswer[2][0]).equal(0n); //
            expect(tokenOwner).equal(randomUser.address);
            
            
        })

        it("should buy and mint - change payment wallet", async () => {

            await factoryContract.connect(tangibleLabs).configurePaymentWallet(randomUser4.address);
            const beforeSaleVendorBalance = await usdc.balanceOf(randomUser4.address);
            const beforeSaleBuyerBalance = await usdc.balanceOf(randomUser.address);
            const tx = await marketplace.connect(randomUser).buyUnminted(goldTnft, usdc.target ,1, 1);
            result = await tx.wait();

            const [boughtTokenEvent] = await result.logs.filter(
                (evt) => evt.eventName === "TnftBought"
            );
            const [storagePaidEvent] = await result.logs.filter(
                (evt) => evt.eventName === "StorageFeePaid"
            );
            const boughtArgs = boughtTokenEvent.args;
            const storageArgs = storagePaidEvent.args;
            const paidPriceEvent = boughtArgs.price;
            const paidStorageEvent = storageArgs.amount;

            const afterSaleVendorBalance = await usdc.balanceOf(randomUser4.address);
            const afterSaleBuyerBalance = await usdc.balanceOf(randomUser.address);
            const lAnswer = await priceManager.itemPriceBatchTokenIds(goldTnft,usdc.target,[0x01n]);
            const oraclePrice = lAnswer[0][0] + lAnswer[2][0];

            const feeBalance = await usdc.balanceOf(mockRevenueShare.target);
            const tokenOwner = await GoldNFT.ownerOf(0x01n);
            //first number is gold price second is storage fee of the price
            expect(paidPriceEvent).eq(lAnswer.weSellAt[0] + lAnswer.tokenizationCost[0])
            expect(beforeSaleBuyerBalance - afterSaleBuyerBalance).equal(5722832889n + 5722832n + lAnswer[2][0])
            expect(afterSaleVendorBalance - beforeSaleVendorBalance).equal(5722832889n + 5722832n);
            expect(afterSaleVendorBalance - beforeSaleVendorBalance).equal(oraclePrice - feeBalance + 5722832n);
            expect(feeBalance).equal(0); // sell fee is 2.5%
            expect( lAnswer[2][0]).equal(0n); //
            expect(tokenOwner).equal(randomUser.address);
            
            
        })

        it("should sell for given price not oracle and buy it with fee", async () => {

            const voucher = getNewEmptyVoucher();
            voucher.mintCount = 1;
            voucher.token = GoldNFT.target;
            voucher.vendor = tangibleLabs.address;
            voucher.price = 80000_000000000n;
            voucher.fingerprint = 1;

            await factoryContract.connect(tangibleLabs).mint(voucher);

            const lot = await tangibleReaderHelper.lotBatch(goldTnft, [0x01n]);
            expect(lot[0].price).equal(80000_000000000n);

            // now purchase
            const beforeSaleVendorBalance = await usdr.balanceOf(tangibleLabs.address);
            const beforeSaleBuyerBalance = await usdr.balanceOf(randomUser.address);
            const tx = await marketplace.connect(randomUser).buy(goldTnft, 0x01n ,1);
            result = await tx.wait();

            const [boughtTokenEvent] = await result.logs.filter(
                (evt) => evt.eventName === "TnftBought"
            );
            const [storagePaidEvent] = await result.logs.filter(
                (evt) => evt.eventName === "StorageFeePaid"
            );
            const [marketFeeEvent] = await result.logs.filter(
                (evt) => evt.eventName === "MarketplaceFeePaid"
            );
            const boughtArgs = boughtTokenEvent.args;
            const storageArgs = storagePaidEvent.args;
            const marketFeeArgs = marketFeeEvent.args;
            const paidPriceEvent = boughtArgs.price;
            const paidStorageEvent = storageArgs.amount;
            const marketPaidFeeEvent = marketFeeArgs.feeAmount;

            const afterSaleVendorBalance = await usdr.balanceOf(tangibleLabs.address);
            const afterSaleBuyerBalance = await usdr.balanceOf(randomUser.address);
            const lAnswer = await priceManager.itemPriceBatchTokenIds(goldTnft,usdr.target,[0x01n]);
            const oraclePrice = lAnswer[0][0] + lAnswer[2][0];

            const feeBalance = await usdc.balanceOf(mockRevenueShare.target);
            const tokenOwner = await GoldNFT.ownerOf(0x01n);
            //first number is gold price second is storage fee of the price
            expect(paidPriceEvent).eq(lot[0].price)
            expect(beforeSaleBuyerBalance - afterSaleBuyerBalance).equal(80000000000000n + 5722832889n ); //price and storage
            expect(afterSaleVendorBalance - beforeSaleVendorBalance).equal(80000000000000n - 2000000000000n  + 5722832889n); // price - fee + storage
            expect(feeBalance).equal(1333333333n); // this is the rev fee that is taken rest is burned in tngbl
            expect(tokenOwner).equal(randomUser.address);
            
        })

    })
    

    describe("When 3 gold minted and gold allowed to mint 2 amount", () => {
        let goldToken1, goldToken2, goldToken3;
        beforeEach(async () =>{
            //mint 3 wines 1 fixed price, 2 from oracle
            let voucher = getNewEmptyVoucher();
            voucher.mintCount = 1;
            voucher.token = goldTnft;
            voucher.price = 565000000;
            voucher.vendor = tangibleLabs.address;
            voucher.fingerprint = 1;

            let voucher1 = getNewEmptyVoucher();
            voucher1.mintCount = 2;
            voucher1.token = goldTnft;
            voucher1.price = 0;
            voucher1.vendor = tangibleLabs.address;
            voucher1.fingerprint = 1;

            const tx = await factoryContract.connect(tangibleLabs).mint(voucher);
            const result = await tx.wait();
                const [tokenIdsEvent] = await result.logs.filter(
                    (evt) => evt.eventName === "MintedTokens"
                );
            const tokennIds = tokenIdsEvent.args[1];
            const tx1 = await factoryContract.connect(tangibleLabs).mint(voucher1);
            const result1 = await tx1.wait();
                const [tokenIdsEvent1] = await result1.logs.filter(
                    (evt) => evt.eventName === "MintedTokens"
                );
            const tokennIds1 = tokenIdsEvent1.args[1];


            const lot1 = await tangibleReaderHelper.lotBatch(goldTnft, [tokennIds[0]]);
            const lot2 = await tangibleReaderHelper.lotBatch(goldTnft, [tokennIds1[0]]);
            const lot3 = await tangibleReaderHelper.lotBatch(goldTnft, [tokennIds1[1]]);

            expect(lot1[0].price).equal(565000000);
            expect(lot2[0].price).equal(0);

            goldToken1 = tokennIds[0];
            goldToken2 = tokennIds1[0];
            goldToken3 = tokennIds1[1];

            //here to add onSaleTracker checks

        })

        it("should fetch lot for provided tokenIds", async () => {
            const lots = await tangibleReaderHelper.lotBatch(goldTnft, [goldToken2, goldToken3]);
            // console.log(lots);
            expect(lots.length).equal(2);
        })

        it("should purchase gold from marketplace",async () => {
            const userBalance = await usdr.balanceOf(randomUser.address);
            await marketplace.connect(randomUser).buy(goldTnft, goldToken1, 1);
            expect(await GoldNFT.ownerOf(goldToken1)).equal(randomUser.address);
        })

        it("shouldn't purchase gold from marketplace - paused but buy after unpaused",async () => {
            const userBalance = await usdr.balanceOf(randomUser.address);
            await GoldNFT.connect(tangibleLabs).togglePause();
            await expect( marketplace.connect(randomUser).buy(goldTnft, goldToken1, 1))
                .to.be.revertedWithCustomError(GoldNFT,"EnforcedPause");
            await GoldNFT.connect(tangibleLabs).togglePause();
            
            await marketplace.connect(randomUser).buy(goldTnft, goldToken1, 1)
            expect(await GoldNFT.ownerOf(goldToken1)).equal(randomUser.address);
        })

        it("should not purchase gold from marketplace - fingerprint doesn't exist",async () => {

            await expect(marketplace.connect(randomUser).buy(goldTnft, 0x0200000000000000000000000000000004n, 1))
                .to.be.revertedWith("fingerprint must exist");
        })

        it("should purchase all gold from marketplace ",async () => {
            
            let tx = await marketplace.connect(randomUser).buy(goldTnft, goldToken1, 1);
            let result = await tx.wait();

            tx = await marketplace.connect(randomUser2).buy(goldTnft, goldToken2, 1);
            result = await tx.wait();

            tx = await marketplace.connect(randomUser3).buy(goldTnft, goldToken3, 1);
            result = await tx.wait();

            expect(await GoldNFT.ownerOf(goldToken1)).equal(randomUser.address);
            expect(await GoldNFT.ownerOf(goldToken2)).equal(randomUser2.address);
            expect(await GoldNFT.ownerOf(goldToken3)).equal(randomUser3.address);

            
        })

        it("should purchase and mint all gold and fail when no more gold is left",async () => {
            let tx = await marketplace.connect(randomUser).buyUnminted(goldTnft, usdc.target, 1, 1);
            await tx.wait();
            
            tx = await marketplace.connect(randomUser).buyUnminted(goldTnft, usdc.target,1, 1);
            await tx.wait();
            
            expect( marketplace.connect(randomUser).buyUnminted(goldTnft,usdc.target, 1, 1))
                .to.be.revertedWith("!0S");
            
        })

        it("should buy house, whitelist enabled",async () => {
            const deplBalance = await usdc.balanceOf(tangibleLabs.address);
            await factoryContract.connect(tangibleLabs).setRequireWhitelistCategory(realEstate, true);
            await factoryContract.connect(tangibleLabs).whitelistBuyer(realEstate, randomUser.address, true);
            const tx1 = await marketplace.connect(randomUser).buyUnminted(realEstate, usdc.target, 2320, 1);
            await tx1.wait();

            await RealEstateNFT.connect(randomUser)["safeTransferFrom(address,address,uint256)"](randomUser.address, deployer.address, 0x01n);
            const deplBalanceAfter = await usdc.balanceOf(tangibleLabs.address);
            expect(deplBalance < deplBalanceAfter).to.be.true;
        })

        it("shouldn't buy house, storage is not required whitelist not allowed",async () => {
            await expect ( marketplace.connect(randomUser).buyUnminted(realEstate, usdc.target, 2320, 1))
                .to.be.revertedWith("OWL"); 
        })
 

        describe("Users selling ", () => {
            let goldToken5, goldToken4;
            beforeEach(async () => {
                //buy gold
                let tx = await marketplace.connect(randomUser).buy(goldTnft, goldToken1, 1);
                let result = await tx.wait();
                
                tx = await marketplace.connect(randomUser2).buy(goldTnft, goldToken2, 1);
                result = await tx.wait();
                
                tx = await marketplace.connect(randomUser3).buy(goldTnft, goldToken3, 1);
                result = await tx.wait();
                //buy gold
                tx = await marketplace.connect(randomUser).buyUnminted(goldTnft,usdc.target, 1, 1);
                result = await tx.wait();
                
                const [boughtTokenEvent] = await result.logs.filter(
                    (evt) => evt.eventName === "TnftBought"
                );
                goldToken4 = boughtTokenEvent.args.tokenId;

                tx = await marketplace.connect(randomUser).buyUnminted(goldTnft,usdc.target,1, 1);
                result = await tx.wait();
                const [boughtTokenEvent1] = await result.logs.filter(
                    (evt) => evt.eventName === "TnftBought"
                );
                goldToken5 = boughtTokenEvent1.args.tokenId;

                //set approvals
                await GoldNFT.connect(randomUser).setApprovalForAll(marketplace.target, true);
                await GoldNFT.connect(randomUser2).setApprovalForAll(marketplace.target, true);
                await GoldNFT.connect(randomUser3).setApprovalForAll(marketplace.target, true);

            })

            it("should sell with users price", async () => {
                tx = await marketplace.connect(randomUser).sellBatch(goldTnft, usdc.target,[goldToken1], [1500000000n], ethers.ZeroAddress);
                await tx.wait();
                const lot = await tangibleReaderHelper.lotBatch(goldTnft, [goldToken1]);
                expect(lot[0].price).equal(1500000000n);
            })

            it("should sell with oracle price", async () => {
                const beforeSell = await usdr.balanceOf(randomUser.address);
                tx = await marketplace.connect(randomUser).sellBatch(goldTnft,usdr.target, [goldToken1], [0], ethers.ZeroAddress);
                await tx.wait();
                const latestAnswer = await priceManager.itemPriceBatchFingerprints(goldTnft,usdr.target,[1]);
                const weSellAt = Number(latestAnswer.weSellAt[0]);
                const lockedAmount = Number(latestAnswer.tokenizationCost[0]);
                
                const lot = await tangibleReaderHelper.lotBatch(goldTnft, [goldToken1]);
                expect(lot[0].price).equal(0);

                const tx2 = await marketplace.connect(randomUser2).buy(goldTnft,goldToken1, 0);
                result = await tx2.wait();
                const [boughtTokenEvent1] = await result.logs.filter(
                    (evt) => evt.eventName === "TnftBought"
                );
                const afterSell = await usdr.balanceOf(randomUser.address);
                const price = boughtTokenEvent1.args.price;
                expect(price).equal(weSellAt + lockedAmount);
                expect(afterSell - beforeSell).equal(Math.ceil((weSellAt + lockedAmount)*975 / 1000));
                
            })

            it("shouldn't double sell already sold item", async () => {
                await expect( marketplace.connect(randomUser2).buy(goldTnft,goldToken1, 0))
                    .to.be.revertedWith("NLO");
            })

            it("should stop selling the item", async () => {
                tx = await marketplace.connect(randomUser).sellBatch(goldTnft,usdc.target, [goldToken1], [0], ethers.ZeroAddress);
                await tx.wait();
                tx =  await marketplace.connect(randomUser).stopBatchSale(goldTnft, [goldToken1]);
                const owner = await GoldNFT.ownerOf(goldToken4);
                expect(owner).equal(randomUser.address);
            })

            it("shouldn't stop selling someone elses item", async () => {
                tx = await marketplace.connect(randomUser).sellBatch(goldTnft,usdc.target, [goldToken1], [0], ethers.ZeroAddress);
                await tx.wait();
                 await expect( marketplace.stopBatchSale(goldTnft, [goldToken1]))
                    .to.be.revertedWith("NOS");
            })


            it("should sell multiple items", async () => {
                
                tx = await marketplace.connect(randomUser2).sellBatch(goldTnft,usdr.target, [goldToken2], [0], ethers.ZeroAddress);
                await tx.wait();
                let itemsOnSale = await onSaleTracker.getTnftCategoriesOnSale();
                
                expect(itemsOnSale[0]).equal(goldTnft);

                await marketplace.connect(randomUser).buy(goldTnft, goldToken2,0);
                await expect(await marketplace.connect(randomUser).sellBatch(goldTnft,usdr.target, [goldToken5, goldToken4],[0,0], ethers.ZeroAddress))
                .to.be.ok;

                itemsOnSale = await onSaleTracker.getTnftCategoriesOnSale();
                let tokensOnSale = await onSaleTracker.getTnftTokensOnSale(itemsOnSale[0]);
                expect(itemsOnSale[0]).equal(goldTnft);
                expect(tokensOnSale[0]).equal(goldToken5);
                expect(tokensOnSale[1]).equal(goldToken4);
                
                await marketplace.connect(randomUser).sellBatch(goldTnft,usdr.target, [goldToken5, goldToken4],[0,0], ethers.ZeroAddress);
                
                itemsOnSale = await onSaleTracker.getTnftCategoriesOnSale();
                
                tokensOnSale = await onSaleTracker.getTnftTokensOnSale(itemsOnSale[0]);
                
                expect(itemsOnSale[0]).equal(goldTnft);
                expect(tokensOnSale[0]).equal(goldToken5);
                expect(tokensOnSale[1]).equal(goldToken4);

                await marketplace.connect(randomUser).stopBatchSale(goldTnft,[goldToken5, goldToken4]);
                
                itemsOnSale = await onSaleTracker.getTnftCategoriesOnSale();
                expect(itemsOnSale.length).equal(0);
                
            })

            it("should stop sale of multiple items", async () => {
                tx = await marketplace.connect(randomUser2).sellBatch(goldTnft,usdr.target, [goldToken2], [0], ethers.ZeroAddress);
                await tx.wait();
                await marketplace.connect(randomUser).buy(goldTnft, goldToken2,0);
                await expect(await marketplace.connect(randomUser).sellBatch(goldTnft,usdr.target, [goldToken2, goldToken1],[0,0], ethers.ZeroAddress))
                .to.be.ok;

                let itemsOnSale = await onSaleTracker.getTnftCategoriesOnSale();
                let tokensOnSale = await onSaleTracker.getTnftTokensOnSale(itemsOnSale[0]);

                expect(itemsOnSale.length).to.be.equal(1);
                expect(tokensOnSale.length).to.equal(2);
                expect(tokensOnSale[0]).to.equal(goldToken2);
                expect(tokensOnSale[1]).to.equal(goldToken1);
                
                await expect(await marketplace.connect(randomUser).stopBatchSale(goldTnft,[goldToken2, goldToken1]))
                .to.be.ok;

                itemsOnSale = await onSaleTracker.getTnftCategoriesOnSale();
                expect(itemsOnSale).to.be.empty;
                 
            })

            describe("Transferring/burning tests", ()=>{
                let tokenId1, tokenId2, tokenId3;
        
                it("should fail transfer, when storage is not paid and owner is not minter", async () => {
                    await hre.timeAndMine.increaseTime("1y");
                    await hre.timeAndMine.increaseTime("1w");
                    await expect(GoldNFT.connect(randomUser)["safeTransferFrom(address,address,uint256)"](randomUser.address, randomUser2.address, goldToken1))
                        .to.be.revertedWith("CT");
                });
        
                it("should fail transfer when storage is not paid and you are not owner ERC721 limitation", async () => {
                    await hre.timeAndMine.increaseTime("1y");
                    await hre.timeAndMine.increaseTime("1w");
                    await expect(GoldNFT["safeTransferFrom(address,address,uint256)"](randomUser.address, randomUser3.address, goldToken2))
                        .to.be.revertedWithCustomError(GoldNFT,"ERC721InsufficientApproval");
                });
        
                it("should pay for storage - we have initial storage fee set", async () => {
                    await hre.timeAndMine.increaseTime("1y");
                    await hre.timeAndMine.increaseTime("1w");
                    const usdcBalanceB = await usdr.balanceOf(tangibleLabs.address);
                    await payStorage(GoldNFT, goldToken1, 1, randomUser)
                    const usdcBalance = await usdr.balanceOf(tangibleLabs.address);
                    await expect(Number(usdcBalanceB))
                        .to.be.lessThan(Number(usdcBalance));
                });
        
                it("should transfer after paying for storage", async () => {
                    await hre.timeAndMine.increaseTime("1y");
                    await hre.timeAndMine.increaseTime("1w");
                    await payStorage(GoldNFT, goldToken1, 1, randomUser)
                    await GoldNFT.connect(randomUser)["safeTransferFrom(address,address,uint256)"](randomUser.address, randomUser2.address, goldToken1)
                    const owner = await GoldNFT["ownerOf(uint256)"](goldToken1);
                    await expect(owner)
                        .to.equal(randomUser2.address);
                });
        
                it("should not transfer after being blacklisted, storage paid", async () => {
                    await GoldNFT.connect(tangibleLabs).blacklistToken(goldToken1, true);
                    await expect(GoldNFT.connect(randomUser)["safeTransferFrom(address,address,uint256)"](randomUser.address, randomUser2.address, goldToken1))
                        .to.be.revertedWith("BL");
                });

                it("shouldn't destroy NFT called from not categoryOwner", async () => {
                    
                    await expect(GoldNFT.burn( goldToken1)).to.be.revertedWith("NCO");
                    // await expect( tnft.ownerOf(tokenId1)).to.be.revertedWith("ERC721: owner query for nonexistent token");
                });
        
                it("shouldn't destroy NFT called from not owner", async () => {
                    
                    await expect(GoldNFT.connect(tangibleLabs).burn( goldToken1)).to.be.revertedWith("NOW");
                    // await expect( tnft.ownerOf(tokenId1)).to.be.revertedWith("ERC721: owner query for nonexistent token");
                });
        
        
                it("should not destroy NFT called from admin -  2 year has passed, storage hasn't been paid", async () => {
                    await hre.timeAndMine.increaseTime("2y");
                    await hre.timeAndMine.increaseTime("1w");
                    await expect(GoldNFT.connect(tangibleLabs).burn( goldToken1)).to.be.revertedWith("NOW");
                    // await expect( tnft.ownerOf(tokenId1)).to.be.revertedWith("ERC721: owner query for nonexistent token");
                });
        
                it("should seize TNFT more than 1y 6m has passed", async () => {
                    await hre.timeAndMine.increaseTime("2y");
                    await hre.timeAndMine.increaseTime("200 days");
                    await factoryContract.connect(tangibleLabs).seizeTnft(goldTnft, [goldToken1]);
                    await expect( await GoldNFT.ownerOf(goldToken1)).to.be.eq(tangibleLabs.address)
                });

                it("should seize TNFT more than 1y 6m has passed and burn", async () => {
                    await hre.timeAndMine.increaseTime("2y");
                    await hre.timeAndMine.increaseTime("200 days");
                    await factoryContract.connect(tangibleLabs).seizeTnft(goldTnft, [goldToken1]);
                    expect( await GoldNFT.ownerOf(goldToken1)).to.be.eq(tangibleLabs.address);
                    expect(await GoldNFT.connect(tangibleLabs).burn( goldToken1)).to.be.ok;
                });
        
                describe("Uri testing", () => {
                    it("should show proper uri for each minted token", async () => {
                        const uri1 = await GoldNFT["tokenURI(uint256)"](goldToken1);
                        const uri2 = await GoldNFT["tokenURI(uint256)"](goldToken2);
                        const uri3 = await GoldNFT["tokenURI(uint256)"](goldToken3);
        
                        expect(uri1).equal("https://github.com/ethers-io/ethers.js/issues/TanXAU/1");
                        expect(uri2).equal("https://github.com/ethers-io/ethers.js/issues/TanXAU/2");
                        expect(uri3).equal("https://github.com/ethers-io/ethers.js/issues/TanXAU/3");
                    });
                });
            });

        })
    })

    describe("Rent manager tests", async () => {
        let realtyToken1, realtyToken2;
        const DAYS_10 =  864_000;
        const DAYS_30 =  2_592_000;
        const DAYS_31 =  2_678_400;
        const DAYS_29 =  2_505_600;
        const DAYS_28 =  2_419_200;
        const DAYS_5 =  432_000;
        const DAYS_1 =  86_400;
        const HOUR_1 =  3_600;
        beforeEach(async () =>{
            //mint 3 wines 1 fixed price, 2 from oracle
            let voucher = getNewEmptyVoucher();
            voucher.mintCount = 1;
            voucher.token = RealEstateNFT.target;
            voucher.price = 0;
            voucher.sendToVendor = false;
            voucher.vendor = tangibleLabs.address;
            voucher.fingerprint = 2323;

            let voucher1 = getNewEmptyVoucher();
            voucher1.mintCount = 1;
            voucher1.token = RealEstateNFT.target;
            voucher1.price = 0;
            voucher1.sendToVendor = false;
            voucher1.vendor = tangibleLabs.address;
            voucher1.fingerprint = 2326;

            const tx = await factoryContract.connect(tangibleLabs).mint(voucher);
            const result = await tx.wait();
                const [tokenIdsEvent] = await result.logs.filter(
                    (evt) => evt.eventName === "MintedTokens"
                );
            const tokennIds = tokenIdsEvent.args[1];
            const tx1 = await factoryContract.connect(tangibleLabs).mint(voucher1);
            const result1 = await tx1.wait();
                const [tokenIdsEvent1] = await result1.logs.filter(
                    (evt) => evt.eventName === "MintedTokens"
                );
            const tokennIds1 = tokenIdsEvent1.args[1];

            realtyToken1 = tokennIds[0];
            realtyToken2 = tokennIds1[0];

            await marketplace.connect(randomUser).buy(realEstate, realtyToken1, 0);
            await marketplace.connect(randomUser2).buy(realEstate, realtyToken2, 0);

            expect(await RealEstateNFT.ownerOf(realtyToken1)).to.be.equal(randomUser.address);
            expect(await RealEstateNFT.ownerOf(realtyToken2)).to.be.equal(randomUser2.address);

        })

        it("should update depositor", async () =>{
            await RentManager.connect(tangibleLabs).updateDepositor(randomUser.address);
            const newDepositor = await RentManager.depositor();
            expect(newDepositor).eq(randomUser.address);
            await expect( RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                1, // 30 days
                0,
                false
            )).to.be.revertedWith("Only the rent depositor can call this function");
            expect( await RentManager.connect(randomUser).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                1, // 30 days
                0,
                false
            )).to.be.ok;
        })

        it("should deposit rent 30days",async () => {
            const tx = await RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                1, // 30 days
                0,
                false
            );
            const result = await tx.wait();
            await expect(RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1, {blockTag: result.blockNumber})).to.be.revertedWith("No rent to claim");
            const rentInfo = await RentManager.rentInfo(realtyToken1);
            const claimable = await RentManager.claimableRentForToken(realtyToken1, {blockTag:result.blockNumber});
            expect(rentInfo.depositAmount).to.be.eq(600_000000);
            expect(rentInfo.claimedAmount).to.be.eq(0);
            expect(rentInfo.unclaimedAmount).to.be.eq(0);
            expect(rentInfo.endTime - rentInfo.depositTime).to.be.eq(DAYS_30);
            expect(rentInfo.rentToken).to.be.eq(usdc.target);
            expect(rentInfo.distributionRunning).to.be.eq(true);
            expect(claimable).eq(0);
        })

        it("should deposit rent 31 days",async () => {
            const tx = await RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                0, // 31 days
                0,
                false
            );
            const result = await tx.wait();
            await expect(RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1, {blockTag: result.blockNumber})).to.be.revertedWith("No rent to claim");
            const rentInfo = await RentManager.rentInfo(realtyToken1);
            const claimable = await RentManager.claimableRentForToken(realtyToken1, {blockTag:result.blockNumber});
            expect(rentInfo.depositAmount).to.be.eq(600_000000);
            expect(rentInfo.claimedAmount).to.be.eq(0);
            expect(rentInfo.unclaimedAmount).to.be.eq(0);
            expect(rentInfo.endTime - rentInfo.depositTime).to.be.eq(DAYS_31);
            expect(rentInfo.rentToken).to.be.eq(usdc.target);
            expect(rentInfo.distributionRunning).to.be.eq(true);
            expect(claimable).eq(0);
        })

        it("should deposit rent 29 days",async () => {
            const tx = await RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                3, // 29 days
                0,
                false
            );
            const result = await tx.wait();
            await expect(RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1, {blockTag: result.blockNumber})).to.be.revertedWith("No rent to claim");
            const rentInfo = await RentManager.rentInfo(realtyToken1);
            const claimable = await RentManager.claimableRentForToken(realtyToken1, {blockTag:result.blockNumber});
            expect(rentInfo.depositAmount).to.be.eq(600_000000);
            expect(rentInfo.claimedAmount).to.be.eq(0);
            expect(rentInfo.unclaimedAmount).to.be.eq(0);
            expect(rentInfo.endTime - rentInfo.depositTime).to.be.eq(DAYS_29);
            expect(rentInfo.rentToken).to.be.eq(usdc.target);
            expect(rentInfo.distributionRunning).to.be.eq(true);
            expect(claimable).eq(0);
        })

        it("should deposit rent 28 days",async () => {
            const tx = await RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                2, // 28 days
                0,
                false
            );
            const result = await tx.wait();
            await expect(RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1, {blockTag: result.blockNumber})).to.be.revertedWith("No rent to claim");
            const rentInfo = await RentManager.rentInfo(realtyToken1);
            const claimable = await RentManager.claimableRentForToken(realtyToken1, {blockTag:result.blockNumber});
            expect(rentInfo.depositAmount).to.be.eq(600_000000);
            expect(rentInfo.claimedAmount).to.be.eq(0);
            expect(rentInfo.unclaimedAmount).to.be.eq(0);
            expect(rentInfo.endTime - rentInfo.depositTime).to.be.eq(DAYS_28);
            expect(rentInfo.rentToken).to.be.eq(usdc.target);
            expect(rentInfo.distributionRunning).to.be.eq(true);
            expect(claimable).eq(0);
        })

        it("should deposit rent custom endTime",async () => {
            const endTime = await time.latest() + DAYS_30 + DAYS_10 + DAYS_5;
            const tx = await RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                2, // 28 days
                endTime,
                false
            );
            const result = await tx.wait();
            await expect(RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1, {blockTag: result.blockNumber})).to.be.revertedWith("No rent to claim");
            const rentInfo = await RentManager.rentInfo(realtyToken1);
            const claimable = await RentManager.claimableRentForToken(realtyToken1, {blockTag:result.blockNumber});
            expect(rentInfo.depositAmount).to.be.eq(600_000000);
            expect(rentInfo.claimedAmount).to.be.eq(0);
            expect(rentInfo.unclaimedAmount).to.be.eq(0);
            expect(rentInfo.endTime - rentInfo.depositTime).to.be.eq(DAYS_30 + DAYS_10 + DAYS_5 - 1);
            expect(rentInfo.rentToken).to.be.eq(usdc.target);
            expect(rentInfo.distributionRunning).to.be.eq(true);
            expect(claimable).eq(0);
        })

        it("should deposit rent custom endTime limit",async () => {
            const endTime = await time.latest() + DAYS_31 + DAYS_31;
            const tx = await RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                2, // 28 days
                endTime,
                false
            );
            const result = await tx.wait();
            await expect(RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1, {blockTag: result.blockNumber})).to.be.revertedWith("No rent to claim");
            const rentInfo = await RentManager.rentInfo(realtyToken1);
            const claimable = await RentManager.claimableRentForToken(realtyToken1, {blockTag:result.blockNumber});
            expect(rentInfo.depositAmount).to.be.eq(600_000000);
            expect(rentInfo.claimedAmount).to.be.eq(0);
            expect(rentInfo.unclaimedAmount).to.be.eq(0);
            expect(rentInfo.endTime - rentInfo.depositTime).to.be.eq(DAYS_31 + DAYS_31 - 1);
            expect(rentInfo.rentToken).to.be.eq(usdc.target);
            expect(rentInfo.distributionRunning).to.be.eq(true);
            expect(claimable).eq(0);
        })

        it("should fail if endTime larger than 2 months",async () => {
            const endTime = await time.latest() + DAYS_31 + DAYS_31 + DAYS_1;
             await expect(RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                2, // 28 days
                endTime,
                false
            )).to.be.revertedWith("End time must be in 2 months tops");
        })

        it("shouldn't deposit rent when previous is not done",async () => {
            const tx = await RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                1, // 30 days
                0,
                false
            );
            const result = await tx.wait();
            await expect( RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                1, // 30 days
                0,
                false
            )).to.be.revertedWith("Not completely vested");
        })

        it("should be able to deposit again after vest period and again",async () => {
            let tx = await RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                1, // 30 days
                0,
                false
            );
            let result = await tx.wait();
            await time.increase(DAYS_31);
            expect(await RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                1, // 30 days
                0,
                false
            )).to.be.ok;

            let rentInfo = await RentManager.rentInfo(realtyToken1);
            expect(rentInfo.depositAmount).to.be.eq(600_000000);
            expect(rentInfo.claimedAmount).to.be.eq(0);
            expect(rentInfo.unclaimedAmount).to.be.eq(600_000000);

            await time.increase(DAYS_31);
            tx = await RentManager.connect(tangibleLabs).deposit(
                realtyToken1,
                usdc.target,
                600_000000,
                1, // 30 days
                0,
                false
            );
            result = await tx.wait();
            rentInfo = await RentManager.rentInfo(realtyToken1);
            expect(rentInfo.depositAmount).to.be.eq(600_000000);
            expect(rentInfo.claimedAmount).to.be.eq(0);
            expect(rentInfo.unclaimedAmount).to.be.eq(1200_000000);
            const claimable = await RentManager.claimableRentForToken(realtyToken1, {blockTag:result.blockNumber});
            expect(claimable).equal(1240_000462) // 40 from 2 days of backpayment
            expect(await usdc.balanceOf(RentManager.target)).to.be.equal(1800_000000)
        })

        describe("With deposited rent", async () => {
            let blockNumber;
            beforeEach(async () =>{
                //mint 3 wines 1 fixed price, 2 from oracle
                const tx = await RentManager.connect(tangibleLabs).deposit(
                    realtyToken1,
                    usdc.target,
                    600_000000,
                    1, // 30 days
                    0,
                    false
                );
                const result = await tx.wait();
                blockNumber = result.blockNumber;
            });

            it("should claim after 10 days of vesting", async () => {
                await time.increase(DAYS_10);
                const claimable = await RentManager.claimableRentForToken(realtyToken1);
                expect(Number(claimable)).eq(200_000000);
                const rentInfo = await RentManager.rentInfo(realtyToken1);
                const claimed = await RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1);
                expect(claimed).to.be.equal(200_000000);
                const tx = await RentManager.connect(randomUser).claimRentForToken(realtyToken1);
                const res = await tx.wait()

                const rentInfo1 = await RentManager.rentInfo(realtyToken1, {blockTag:res.blockNumber});
                expect(rentInfo.depositAmount).to.be.eq(600_000000);
                expect(rentInfo.claimedAmount).to.be.eq(0);
                expect(rentInfo.unclaimedAmount).to.be.eq(0);

                expect(rentInfo1.depositAmount).to.be.eq(600_000000);
                expect(rentInfo1.claimedAmount).to.be.eq(200_000231); //231 from next block  in which claims
                expect(rentInfo1.unclaimedAmount).to.be.eq(0);
            })

            it("should claim after 10 days of vesting and again after 5 days", async () => {
                await time.increase(DAYS_10);
                let claimable = await RentManager.claimableRentForToken(realtyToken1);
                expect(Number(claimable)).eq(200_000000);
                let claimed = await RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1);
                expect(claimed).to.be.equal(200_000000);
                expect(await RentManager.connect(randomUser).claimRentForToken(realtyToken1)).to.be.ok;
                // now increase to 5 days more 
                await time.increase(DAYS_5);
                claimable = await RentManager.claimableRentForToken(realtyToken1);
                expect(Number(claimable)).eq(100_000000);
                claimed = await RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1);
                expect(claimed).to.be.equal(100_000000);
                const tx = await RentManager.connect(randomUser).claimRentForToken(realtyToken1);
                const res = await tx.wait();
                const rentInfo1 = await RentManager.rentInfo(realtyToken1, {blockTag:res.blockNumber});

                expect(rentInfo1.depositAmount).to.be.eq(600_000000);
                expect(rentInfo1.claimedAmount).to.be.eq(300_000462); //231 from next block  in which claims, plus previous 231
                expect(rentInfo1.unclaimedAmount).to.be.eq(0);
            })

            it("should claim after 10 days of vesting and again rest after vest period", async () => {
                const balanceBefore = await usdc.balanceOf(randomUser.address);
                await time.increase(DAYS_10);

                let claimable = await RentManager.claimableRentForToken(realtyToken1);
                expect(Number(claimable)).eq(200_000000);
                let claimed = await RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1);
                expect(claimed).to.be.equal(200_000000);
                expect(await RentManager.connect(randomUser).claimRentForToken(realtyToken1)).to.be.ok;
                // now increase to 21 days more 
                await time.increase(DAYS_10 + DAYS_10 + DAYS_1);

                claimable = await RentManager.claimableRentForToken(realtyToken1);
                expect(Number(claimable)).eq(399999769); // because on claim we got with 231
                claimed = await RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1);
                expect(claimed).to.be.equal(399999769);
                const tx = await RentManager.connect(randomUser).claimRentForToken(realtyToken1);
                const res = await tx.wait();
                const rentInfo1 = await RentManager.rentInfo(realtyToken1, {blockTag:res.blockNumber});

                const balanceAfter = await usdc.balanceOf(randomUser.address);
                expect(rentInfo1.depositAmount).to.be.eq(600_000000);
                expect(rentInfo1.claimedAmount).to.be.eq(600_000000);
                expect(rentInfo1.unclaimedAmount).to.be.eq(0);
                expect(balanceAfter - balanceBefore).to.be.equal(600_000000);
                await expect( RentManager.connect(randomUser).claimRentForToken(realtyToken1))
                    .to.be.revertedWith("No rent to claim")
            })

            it("should claim after 10 days then new deposit after vest is over", async () => {
                await time.increase(DAYS_10);
                let claimable = await RentManager.claimableRentForToken(realtyToken1);
                expect(Number(claimable)).eq(200_000000);
                let claimed = await RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1);
                expect(claimed).to.be.equal(200_000000);
                expect(await RentManager.connect(randomUser).claimRentForToken(realtyToken1)).to.be.ok;
                // now increase to 5 days more 
                await time.increase(DAYS_10 + DAYS_10 + DAYS_1);
                claimable = await RentManager.claimableRentForToken(realtyToken1);
                expect(Number(claimable)).eq(399999769); // because on claim we got with 231
                claimed = await RentManager.connect(randomUser).claimRentForToken.staticCall(realtyToken1);
                expect(claimed).to.be.equal(399999769);
                const tx = await RentManager.connect(randomUser).claimRentForToken(realtyToken1);
                const res = await tx.wait();
                const rentInfo1 = await RentManager.rentInfo(realtyToken1, {blockTag:res.blockNumber});

                expect(rentInfo1.depositAmount).to.be.eq(600_000000);
                expect(rentInfo1.claimedAmount).to.be.eq(600_000000);
                expect(rentInfo1.unclaimedAmount).to.be.eq(0);
            })

            it("should call pause and claim back, and claim for owner", async () => {
                await time.increase(DAYS_10);
                const balanceBeforeUser = await usdc.balanceOf(randomUser.address);
                const balanceBeforeTngbl = await usdc.balanceOf(tangibleLabs.address);
                const claimable = await RentManager.claimableRentForToken(realtyToken1);
                expect(Number(claimable)).eq(200_000000);
                const rentInfo = await RentManager.rentInfo(realtyToken1);
                const claimedBack = await RentManager.connect(tangibleLabs).pauseAndClaimBackDistribution.staticCall(realtyToken1);
                expect(claimedBack).to.be.equal(400_000000);
                const tx = await RentManager.connect(tangibleLabs).pauseAndClaimBackDistribution(realtyToken1);
                const res = await tx.wait()

                const rentInfo1 = await RentManager.rentInfo(realtyToken1, {blockTag:res.blockNumber});
                const balanceAfterUser = await usdc.balanceOf(randomUser.address);
                const balanceAfterTngbl = await usdc.balanceOf(tangibleLabs.address);

                expect(rentInfo.depositAmount).to.be.eq(600_000000);
                expect(rentInfo.claimedAmount).to.be.eq(0);
                expect(rentInfo.unclaimedAmount).to.be.eq(0);

                expect(rentInfo1.depositAmount).to.be.eq(0);
                expect(rentInfo1.claimedAmountTotal).to.be.eq(200_000231); //231 from next block  in which claims
                expect(rentInfo1.unclaimedAmount).to.be.eq(0);

                expect(balanceAfterUser - balanceBeforeUser).to.be.equal(200_000231);
                expect(balanceAfterTngbl - balanceBeforeTngbl).to.be.equal(399999769);
            })

            it("should call pause and claim back, and claim for owner and deposit again", async () => {
                await time.increase(DAYS_10);
                const balanceBeforeUser = await usdc.balanceOf(randomUser.address);
                const balanceBeforeTngbl = await usdc.balanceOf(tangibleLabs.address);
                let claimable = await RentManager.claimableRentForToken(realtyToken1);
                expect(Number(claimable)).eq(200_000000);
                let rentInfo = await RentManager.rentInfo(realtyToken1);
                const claimedBack = await RentManager.connect(tangibleLabs).pauseAndClaimBackDistribution.staticCall(realtyToken1);
                expect(claimedBack).to.be.equal(400_000000);
                let tx = await RentManager.connect(tangibleLabs).pauseAndClaimBackDistribution(realtyToken1);
                let res = await tx.wait()

                const rentInfo1 = await RentManager.rentInfo(realtyToken1, {blockTag:res.blockNumber});
                const balanceAfterUser = await usdc.balanceOf(randomUser.address);
                const balanceAfterTngbl = await usdc.balanceOf(tangibleLabs.address);

                expect(rentInfo.depositAmount).to.be.eq(600_000000);
                expect(rentInfo.claimedAmount).to.be.eq(0);
                expect(rentInfo.unclaimedAmount).to.be.eq(0);

                expect(rentInfo1.depositAmount).to.be.eq(0);
                expect(rentInfo1.claimedAmountTotal).to.be.eq(200_000231); //231 from next block  in which claims
                expect(rentInfo1.unclaimedAmount).to.be.eq(0);

                expect(balanceAfterUser - balanceBeforeUser).to.be.equal(200_000231);
                expect(balanceAfterTngbl - balanceBeforeTngbl).to.be.equal(399999769);

                //deposit again
                tx = await RentManager.connect(tangibleLabs).deposit(
                    realtyToken1,
                    usdc.target,
                    600_000000,
                    0, // 31 days
                    0,
                    false
                );
                res = await tx.wait();

                rentInfo = await RentManager.rentInfo(realtyToken1);
                claimable = await RentManager.claimableRentForToken(realtyToken1, {blockTag:res.blockNumber});
                expect(rentInfo.depositAmount).to.be.eq(600_000000);
                expect(rentInfo.claimedAmount).to.be.eq(0);
                expect(rentInfo.unclaimedAmount).to.be.eq(0);
                expect(rentInfo.claimedAmountTotal).to.be.eq(200_000231);
                expect(rentInfo.endTime - rentInfo.depositTime).to.be.eq(DAYS_31);
                expect(rentInfo.rentToken).to.be.eq(usdc.target);
                expect(rentInfo.distributionRunning).to.be.eq(true);
                expect(claimable).eq(0);
            })

            it("should auto claim for seller on purchase after 10day vesting", async () => {
                await time.increase(DAYS_10);
                
                const rentInfo = await RentManager.rentInfo(realtyToken1);
                const claimable = await RentManager.claimableRentForToken(realtyToken1);
                expect(Number(claimable)).eq(200_000000);
                expect(rentInfo.depositAmount).to.be.eq(600_000000);
                expect(rentInfo.claimedAmount).to.be.eq(0);
                expect(rentInfo.unclaimedAmount).to.be.eq(0);
                // put on sale
                await RealEstateNFT.connect(randomUser).approve(marketplace.target, realtyToken1);
                await marketplace.connect(randomUser).sellBatch(realEstate, usdr.target, [realtyToken1], [50_000_000000],ethers.ZeroAddress);
                // purchase 
                const balanceBefore = await usdc.balanceOf(randomUser.address);
                await marketplace.connect(randomUser2).buy(realEstate, realtyToken1, 0);
                
                const balanceAfter = await usdc.balanceOf(randomUser.address);
                const rentInfo1 = await RentManager.rentInfo(realtyToken1);

                expect(rentInfo1.depositAmount).to.be.eq(600_000000);
                expect(rentInfo1.claimedAmount).to.be.eq(200_000694); 
                expect(rentInfo1.unclaimedAmount).to.be.eq(0);
                expect(balanceAfter - balanceBefore).to.be.eq(200_000694);
            })
        });


    });
});