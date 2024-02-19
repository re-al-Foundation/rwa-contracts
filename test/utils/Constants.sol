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

address constant UNREAL_LZ_ENDPOINT_V1 = 0x2cA20802fd1Fd9649bA8Aa7E50F0C82b479f35fe;
uint16 constant UNREAL_CHAINID = 10252;

// ~ Unreal Addresses ~

address constant UNREAL_USTB = 0xd856A706eF29a9170F624907f576f60f432131Ae;
address constant UNREAL_DAI  = 0x665D4921fe931C0eA1390Ca4e0C422ba34d26169;
address constant UNREAL_USDC = 0xabAa4C39cf3dF55480292BBDd471E88de8Cc3C97;

address constant UNREAL_UNIV2_ROUTER = 0xc4330B6fb035F75107F29bf741B945167f2f5330;
address constant UNREAL_UNIVERSAL_ROUTER = 0x5056c7bc25488d45a2C50e927484a2DF4B18096A;
address constant UNREAL_SWAP_ROUTER = 0x906B62A0C2ef082408A9DEBb0FC09027B351A04c;
address constant UNREAL_QUOTERV2 = 0xc2b4dE8146b87bF522d55ECD1Bf581dFbB1b7ab6;
address constant UNREAL_MULTICALL = 0x92D676A4917aF4c19fF0450c90471D454Ac423fc;

address constant UNREAL_DAI_USDC_1000 = 0x4b6b44551b6762AA5825A4e81892a0A1bF6b75b9;
address constant UNREAL_DAI_WETH_1000 = 0x5D7f42AAEca9984b9eEe0846b31584258161e52c;

address constant UNREAL_PEARLV2_FACTORY = 0xC46cDB77FF184562A834Ff684f0393b0cA57b5E5;