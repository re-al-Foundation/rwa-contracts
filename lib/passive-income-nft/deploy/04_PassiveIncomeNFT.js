const hre = require("hardhat");

const { ethers } = hre;
const { developmentChains, networkConfig } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { execute, deploy, get, log, read } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const TNGBL = await get("TangibleERC20");
  const Calculator = await get("PassiveIncomeCalculator");

  const args = [
    TNGBL.address,
    Calculator.address,
    networkConfig[network.name].startTimestamp,
  ];

  const NFT = await deploy("PassiveIncomeNFT", {
    from: deployer,
    args: args,
    log: true,
  });
  log(`Passive Income NFT deployed to ${NFT.address}`);

  // if (NFT.newlyDeployed) {
  const tngbl = await ethers.getContractAt("TangibleERC20", TNGBL.address);
  const burnerRole = await tngbl.BURNER_ROLE();
  const minterRole = await tngbl.MINTER_ROLE();
  for (const role of [burnerRole, minterRole]) {
    const hasRole = await read(
      "TangibleERC20",
      { from: deployer, log: true },
      "hasRole",
      role,
      NFT.address
    );
    if (!hasRole) {
      await execute(
        "TangibleERC20",
        { from: deployer, log: true },
        "grantRole",
        role,
        NFT.address
      );
    }
  }
  await execute(
    "PassiveIncomeNFT",
    { from: deployer, log: true },
    "setImageBaseURI",
    networkConfig[network.name].imageBaseURI || ""
  );
  const adminRole = await read(
    "PassiveIncomeNFT",
    { from: deployer, log: true },
    "DEFAULT_ADMIN_ROLE"
  );
  await execute(
    "PassiveIncomeNFT",
    { from: deployer, log: true },
    "grantRole",
    adminRole,
    networkConfig[network.name].addresses.TANGIBLE_DEPLOYER
  );
  // }

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${
        NFT.address
      } ${args.toString().replace(/,/g, " ")}`
    );
  }
};

module.exports.tags = ["all", "nft"];
module.exports.dependencies = ["token", "calculator"];
