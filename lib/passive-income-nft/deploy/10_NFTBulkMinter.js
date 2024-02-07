const hre = require("hardhat");

const { ethers } = hre;

const { developmentChains, networkConfig } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { execute, deploy, log, read, get } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const TNGBL = await get("TangibleERC20");
  const NFT = await get("PassiveIncomeNFT");

  const args = [TNGBL.address, NFT.address];

  const BulkMinter = await deploy("NFTBulkMinter", {
    from: deployer,
    args: args,
    log: true,
  });
  log(`NFT Bulk Minter deployed to ${BulkMinter.address}`);

  await execute(
    "NFTBulkMinter",
    { from: deployer, log: true },
    "initialize"
  );

  const nft = await ethers.getContractAt("PassiveIncomeNFT", NFT.address);
  const earlyMinter = await nft.EARLY_MINTER_ROLE();

  const tngbl = await ethers.getContractAt("TangibleERC20", TNGBL.address);
  const minter = await tngbl.MINTER_ROLE();

  await execute(
    "PassiveIncomeNFT",
    { from: deployer, log: true },
    "grantRole",
    earlyMinter,
    BulkMinter.address
  );

  await execute(
    "TangibleERC20",
    { from: deployer, log: true },
    "grantRole",
    minter,
    BulkMinter.address
  );

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${
        BulkMinter.address
      } ${args.toString().replace(/,/g, " ")}`
    );
  }
};

module.exports.tags = ["all", "bulk"];
module.exports.dependencies = ["token", "nft"];
