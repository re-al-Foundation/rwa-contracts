// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// ~ Roles ~

bytes32 constant DISTRIBUTOR_ROLE   = keccak256("DISTRIBUTOR");
bytes32 constant MINTER_ROLE        = keccak256("MINTER");
bytes32 constant BURNER_ROLE        = keccak256("BURNER");
bytes32 constant CLAIMER_ROLE       = keccak256("CLAIMER");
bytes32 constant DEPOSITOR_ROLE     = keccak256("DEPOSITOR");
bytes32 constant SHARE_MANAGER_ROLE = keccak256("SHARE_MANAGER");

// ~ V1 Addresses ~

address constant POLYGON_PI_NFT = 0xDc7ee66c43f35aC8C1d12Df90e61f05fbc2cD2c1;
address constant POLYGON_PI_CALC = 0xC419568E7673bDc0d65aB3b56986CCEc7776D7f2;
address constant POLYGON_TNGBL_TOKEN = 0x49e6A20f1BBdfEeC2a8222E052000BbB14EE6007;

address constant MUMBAI_PI_NFT = 0xa0b08D6BBc11e798177D2E6BF838704c5fDe1401;
address constant MUMBAI_PI_CALC = 0xB5eE6cca5C792d738388DFc57cf6FAcB93B6bd02;
address constant MUMBAI_TNGBL_TOKEN = 0xC3Cd8cE66D0aa591a75686Ee99BAa7b8667d6EE0;

address constant MUMBAI_UNIV2_ROUTER = 0x8954AfA98594b838bda56FE4C12a09D7739D179b;

// ~ LayerZero ~

address constant POLYGON_LZ_ENDPOINT_V1 = 0x3c2269811836af69497E5F486A85D7316753cf62;
uint16 constant POLYGON_CHAINID = 109;

address constant MUMBAI_LZ_ENDPOINT_V1 = 0xf69186dfBa60DdB133E91E9A4B5673624293d8F8;
uint16 constant MUMBAI_CHAINID = 10109;

address constant GEORLI_LZ_ENDPOINT_V1 = 0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23;
uint16 constant GEORLI_CHAINID = 10121;

address constant BSCTESTNET_LZ_ENDPOINT_V1 = 0x6Fcb97553D41516Cb228ac03FdC8B9a0a9df04A1;
uint16 constant BSCTESTNET_CHAINID = 10102;

address constant SEPOLIA_LZ_ENDPOINT_V1 = 0xae92d5aD7583AD66E49A0c67BAd18F6ba52dDDc1;
uint16 constant SEPOLIA_CHAINID = 10161;

address constant UNREAL_LZ_ENDPOINT_V1 = 0x83c73Da98cf733B03315aFa8758834b36a195b87;
uint16 constant UNREAL_CHAINID = 10262;

// ~ Unreal Addresses ~

address constant UNREAL_USTB = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
address constant UNREAL_DAI  = 0x3F93beBAd7BA4d7A5129eA8159A5829Eacb06497;
address constant UNREAL_USDC = 0x922Af5e40d54BF866588C9251A974422C20c7CB9;
address constant UNREAL_WETH = 0x0C68a3C11FB3550e50a4ed8403e873D367A8E361;
address constant UNREAL_PEARL = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;
address constant UNREAL_MORE = 0x3CD7AB62b0A96CC5c23490d0893084b58A98A1Dc;
// pearl AMM
address constant UNREAL_PEARLV2_FACTORY = 0x579485AC5737c0A729908d5EA19D1054d275393F;
address constant UNREAL_NFTMANAGER = 0xfF9B296b0f6194153c80315fd9929f2BF34641b6;
address constant UNREAL_SWAP_ROUTER = 0xa752C9Cd89FE0F9D07c8dC79A7564b45F904b344;
address constant UNREAL_QUOTERV2 = 0x97Fdf90f153628b74aA9EB19BD617adB32987caF;
address constant UNREAL_UNIV2_ROUTER = 0xc4330B6fb035F75107F29bf741B945167f2f5330; // TODO - outdated
address constant UNREAL_UNIVERSAL_ROUTER = 0x5056c7bc25488d45a2C50e927484a2DF4B18096A; // TODO - outdated
address constant UNREAL_MULTICALL = 0x92D676A4917aF4c19fF0450c90471D454Ac423fc; // TODO - outdated
// pearl ALM
address constant UNREAL_BOX_FACTORY = 0xE7376D7ADd1edD2b2cC65951485D51a88Bb7c0CD;
address constant UNREAL_BOX_MANAGER = 0xd41C6ED6C8663613Ec186A115FA109dEd55bA2B2;
address constant UNREAL_BOX_FAC_MANAGER = 0x95e3664633A8650CaCD2c80A0F04fb56F65DF300; // TODO - outdated
address constant UNREAL_GAUGEV2ALM = 0x67e7a9c3F58Df293fCC871BE3160482176d47Ed6;
address constant UNREAL_GAUGEV2_FACTORY = 0xBF1FE96e882d501823EF65d01EEA194064372f00;
address constant UNREAL_VOTER = 0x5e59A09Ca7e109b76B968cdb830a233Ee2b54962;
// tngbl
address constant UNREAL_TNGBLV3ORACLE = 0x21AD6dF9ba78778306166BA42Ac06d966119fCE1;

// ~ RWA Deployment ~

// TODO Remove
address constant UNREAL_RWA_TOKEN = 0xdb2664cc9C9a16a8e0608f6867bD67158AF59397;
address constant UNREAL_ROYALTY_HANDLER = 0x138A0c41f9a8b99a07cA3B4cABc711422B7d8EAB;
address constant UNREAL_VESTING = 0x0f3be26c5eF6451823BD816B68E9106C8B65A5DA;
address constant UNREAL_VE_RWA = 0x2afD4dC7649c2545Ab1c97ABBD98487B6006f7Ae;
address constant UNREAL_REV_DISTRIBUTOR = 0x56843df02d5A230929B3A572ACEf5048d5dB76db;
address constant UNREAL_REV_STREAM = 0x5d79976Be5814FDC8d5199f0ba7fC3764082D635;
address constant UNREAL_DELEGATE_FACTORY = 0xe988F47f227c7118aeB0E2954Ce6eed8822303d0;
address constant UNREAL_RWA_API = 0xEE08C27028409669534d2D7c990D3b9B13DF03c5;
address constant UNREAL_EXACTINPUTWRAPPER = 0x75520079Ed7ad8151dFE46Db2bfBC5Cb1ad089c5;