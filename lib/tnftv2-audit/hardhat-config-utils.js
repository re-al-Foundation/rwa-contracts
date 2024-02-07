require('dotenv').config()


const networkConfig = {
    80001: {
        name: 'mumbai',
        usdcAddress: '0x4b64cCe8Af0f1983fb990B152fb2Ff637d26B636',
        usdrAddress: '0x8885a6E2f1F4BC383963eD848438A8bEC243886F',
        pearlRouter: "0xd61b7Ad7fA5F0dfeC5bED359cE51b58f1ccCAC18",
        chainLinkGoldOracle: '',
        chainLinkGBPOracle: '',
        wrappedMatic: "0x9c3c9283d3e44854697cd22d3faa240cfb032889",
        tangibleDao:"0xb99468CF65F43A2656280A749A3F092dF54AA58d", //rt deployer
        tangibleLabs:"0x23bfB039Fe7fE0764b830960a9d31697D154F2E4", //goerli test
        //sellFeeAddress: "0x0Ec2cf1bEa8ef02eecA91edD948AAe78ffFd75e8",
        tokenUrl:"https://onu50475eh.execute-api.us-east-1.amazonaws.com/tnfts",
        fetchExternal: "https://onu50475eh.execute-api.us-east-1.amazonaws.com",
        routerAddress: '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',
        tngblAddress:"0xC3Cd8cE66D0aa591a75686Ee99BAa7b8667d6EE0",
        daiAddress:"0xe08e7009C2c4ae13C45852876f45913c47eF07Cc",
        passiveNftAddress:"0xa0b08D6BBc11e798177D2E6BF838704c5fDe1401",
        passiveNftAbi: "../abis/mumbai/PassiveNFT.json",
        revenueShare:"0x74c03a9FBEEd64635468b8067A7Eb032ffD3ac25",
        rentShare:"0x8A2baC12fA52Cff055FAc75509bf7aB789089e10",
        revenueShareAbi: "../abis/mumbai/RevenueShare.json",
        uniswapFactory: "0xc35DADB65012eC5796536bD9864eD8773aBc74C4",
        instantTradeEnabled: true,
        chainlinkMatrixOracle: "0xbE2F59A77eb5D38FE4E14c8E5284e72E07f74cee",
        feeDistributor: "0x186661c459f89f3dc2515fcb4a12fa17aCA686A0" //revenue distributor
    }
}

const goldBars = [
    {
        gWeight: 100,
        fingerprint: 1,
    },
    {
        gWeight: 250,
        fingerprint: 2,
    },
    {
        gWeight: 500,
        fingerprint: 3,
    },
    {
        gWeight: 1000,
        fingerprint: 4,
    }
]

const gold = {
    name: "TangibleGoldBars",
    symbol: "TanXAU",
    fixedStorageFee: false,
    storageRequired: true,
    sellStock: 43,
    goldBars,
    symbolInUri: true, // means that uri is for example example.com/TanXAU/tokenId
    tnftType: 1, // 1 is for gold
    storagePercentage: 10 // 0.1% in 2 decimals as it is in tnft
}

const realEstate = {
    name: "TangibleREstate",
    symbol: "RLTY",
    //url: "https://mdata.tangible.store/tnfts",
    fixedStorageFee: false,
    storageRequired: false,
    paysRent: true,
    realtyFee: 100, // 1%
    symbolInUri: true, // means that uri is for example example.com/RLTY/tokenId
    tnftType: 2, // 1 is for gold
}

const tnftTypes = [
    {
        id: 1,
        description: "Gold bars",
        paysRent: false
    },
    {
        id: 2,
        description: "Real Estates",
        paysRent: true
    }
]

const gbpConversionFee = 1000000;

const developmentChains = ["hardhat", "localhost", "mumbai"]
const developmentChainsLocal = ["hardhat", "localhost"]

const getNetworkIdFromName = async (networkIdName) => {
    for (const id in networkConfig) {
        if (networkConfig[id]['name'] == networkIdName) {
            return id
        }
    }
    return null
}

module.exports = {
    networkConfig,
    getNetworkIdFromName,
    developmentChains,
    developmentChainsLocal,
    gold,
    realEstate,
    gbpConversionFee,
    tnftTypes
}