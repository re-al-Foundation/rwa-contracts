const hre = require("hardhat");

const { ethers } = hre;

const { developmentChains, networkConfig } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { execute, deploy, log, read, get } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const TNGBL = await get("TangibleERC20");
  const NFT = await get("PassiveIncomeNFT");

  const args = [
    TNGBL.address,
    networkConfig[network.name].addresses.OldPassiveIncomeNFT,
    NFT.address,
    networkConfig[network.name].addresses.OldMarketplace,
  ];

  const NFTMigrator = await deploy("NFTMigrator", {
    from: deployer,
    args: args,
    log: true,
  });
  log(`NFT Migrator deployed to ${NFTMigrator.address}`);

  const migrator = await read(
    "PassiveIncomeNFT",
    { from: deployer, log: true },
    "MIGRATOR_ROLE"
  );

  await execute(
    "PassiveIncomeNFT",
    { from: deployer, log: true },
    "grantRole",
    migrator,
    NFTMigrator.address
  );

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${
        NFTMigrator.address
      } ${args.toString().replace(/,/g, " ")}`
    );
  }
};

module.exports.tags = ["all", "migration"];
module.exports.dependencies = ["token", "nft", "marketplace"];
