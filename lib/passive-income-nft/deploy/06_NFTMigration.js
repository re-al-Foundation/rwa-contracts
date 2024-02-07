const hre = require("hardhat");

const { ethers } = hre;

const { developmentChains, networkConfig } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { execute, deploy, log, read, get } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const LegacyNFT = await get("NidhiLegacyNFT");
  const NFT = await get("PassiveIncomeNFT");
  const TokenSwap = await get("TangibleTokenSwap");

  const nidhiNFTAddress =
    developmentChains.includes(network.name) &&
    !networkConfig[network.name].addresses.NidhiNFT
      ? (await get("MockNFT")).address
      : networkConfig[network.name].addresses.NidhiNFT;

  const stakingContractAddress =
    developmentChains.includes(network.name) &&
    !networkConfig[network.name].addresses.Staking
      ? (await get("MockStaking")).address
      : networkConfig[network.name].addresses.Staking;

  const stakingTokenContractAddress =
    developmentChains.includes(network.name) &&
    !networkConfig[network.name].addresses.SGURU
      ? (await get("MockSGURU")).address
      : networkConfig[network.name].addresses.SGURU;

  const args = [
    nidhiNFTAddress,
    LegacyNFT.address,
    NFT.address,
    TokenSwap.address,
    stakingContractAddress,
    stakingTokenContractAddress,
  ];

  const NFTSwap = await deploy("PassiveIncomeNFTSwap", {
    from: deployer,
    args: args,
    log: true,
  });
  log(`NFT Swap deployed to ${NFTSwap.address}`);

  // if (NFTSwap.newlyDeployed) {
  const legacyNFT = await ethers.getContractAt(
    "NidhiLegacyNFT",
    LegacyNFT.address
  );
  const minterRole = await legacyNFT.MINTER_ROLE();
  const hasRole = await read(
    "NidhiLegacyNFT",
    { from: deployer, log: true },
    "hasRole",
    minterRole,
    NFTSwap.address
  );
  if (!hasRole) {
    await execute(
      "NidhiLegacyNFT",
      { from: deployer, log: true },
      "grantRole",
      minterRole,
      NFTSwap.address
    );
  }

  await execute(
    "TangibleTokenSwap",
    { from: deployer, log: true },
    "initialize"
  );

  const swapperRole = await read(
    "TangibleTokenSwap",
    { from: deployer, log: true },
    "SWAPPER_ROLE"
  );

  await execute(
    "TangibleTokenSwap",
    { from: deployer, log: true },
    "grantRole",
    swapperRole,
    NFTSwap.address
  );

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${
        NFTSwap.address
      } ${args.toString().replace(/,/g, " ")}`
    );
  }
};

module.exports.tags = ["all", "nft-swap"];
module.exports.dependencies = ["token", "token-swap", "legacy", "nft", "mocks"];
