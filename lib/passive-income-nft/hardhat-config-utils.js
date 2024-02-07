require("dotenv").config();

const networkConfig = {
  localhost: {
    addresses: {
      // GURU: "0x28701a232B566729381C53E47a3f53b08F50eb4C",
      SGURU: "0x7F244A5DA32D3C1727e604Cb16554bFae89579A8",
      Staking: "0xf7552ecff8f6D58d3762876d886A581c0f275968",
      NidhiNFT: "0xb7bB6098779A47d1Ea8e568E35381696D9d781C9",
      router: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
    },
    imageBaseURI:
      "https://bs0z4u8hj4.execute-api.us-east-1.amazonaws.com/dev/generate/nftImage?tokenId=",
  },
  mumbai: {
    addresses: {
      GURU: "0x28701a232B566729381C53E47a3f53b08F50eb4C",
      SGURU: "0x7F244A5DA32D3C1727e604Cb16554bFae89579A8",
      Staking: "0xf7552ecff8f6D58d3762876d886A581c0f275968",
      NidhiNFT: "0xb7bB6098779A47d1Ea8e568E35381696D9d781C9",
      USDC: "0xA0fB0349526B7213b6be0F1D9A62f952A9179D96",
      router: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
      GELATO_EXECUTOR: "0x25aD59adbe00C2d80c86d01e2E05e1294DA84823",
      GELATO_OPS: "0xB3f5503f93d5Ef84b06993a1975B9D21B962892F",
      TANGIBLE_DEPLOYER: "0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7",
      OldPassiveIncomeNFT: "0xdA438b4628aC69516F127f9b2e86D23dB0e8B644",
      OldMarketplace: "0x0B0c702805E96d7dbC02A6E50e87119822FF7050",
    },
    startTimestamp: 1649203200, // April 6th, 2022
    imageBaseURI:
      "https://bs0z4u8hj4.execute-api.us-east-1.amazonaws.com/dev/generate/nft-image?tokenId=",
  },
  polygon: {
    addresses: {
      GURU: "0x057E0bd9B797f9Eeeb8307B35DbC8c12E534c41E",
      SGURU: "0x04568467f0AAe5fb85Bf0e031ee66FF2C200a6Fb",
      Staking: "0x4Eef9cb4D2DA4AB2A76a4477E9d2b07f403f0675",
      NidhiNFT: "0x11Ba138F7B6Bf72e84fC052302859fd7d3ee6725",
      USDC: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
      router: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
      GELATO_EXECUTOR: "0x7598e84B2E114AB62CAB288CE5f7d5f6bad35BbA",
      GELATO_OPS: "0x527a819db1eb0e34426297b03bae11F2f8B3A19E",
      TANGIBLE_DEPLOYER: "0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7",
      OldPassiveIncomeNFT: "0xd71b43474Da7f77A567925F107f5fa611a22cb40",
      OldMarketplace: "0xea70889f09f766bfFA3a6b55684b0193e80caCc3",
    },
    //startTimestamp: 1651503600, // May 2nd, 2022 :: 3 PM UTC
    startTimestamp: 1651683600, // May 4th, 2022 :: 5 PM UTC
    imageBaseURI:
      "https://wssudnikn2.execute-api.us-east-1.amazonaws.com/prod/generate/nft-image?tokenId=",
  },
};

const developmentChains = ["hardhat", "localhost"];

module.exports = {
  networkConfig,
  developmentChains,
};
