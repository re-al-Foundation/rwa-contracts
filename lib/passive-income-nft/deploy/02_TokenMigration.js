const hre = require("hardhat");

const { ethers } = hre;
const { developmentChains, networkConfig } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { execute, deploy, log, get, read } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const TNGBL = await get("TangibleERC20");

  const guruAddress = developmentChains.includes(network.name)
    ? (await get("MockGURU")).address
    : networkConfig[network.name].addresses.GURU;

  const args = [guruAddress, TNGBL.address];

  const TokenSwap = await deploy("TangibleTokenSwap", {
    from: deployer,
    args: args,
    log: true,
  });
  log(`Token Swap deployed to ${TokenSwap.address}`);

  const tngbl = await ethers.getContractAt("TangibleERC20", TNGBL.address);
  const burnerRole = await tngbl.BURNER_ROLE();
  const minterRole = await tngbl.MINTER_ROLE();
  for (const role of [burnerRole, minterRole]) {
    const hasRole = await read(
      "TangibleERC20",
      { from: deployer, log: true },
      "hasRole",
      role,
      TokenSwap.address
    );
    if (!hasRole) {
      await execute(
        "TangibleERC20",
        { from: deployer, log: true },
        "grantRole",
        role,
        TokenSwap.address
      );
    }
  }

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${
        TokenSwap.address
      } ${args.toString().replace(/,/g, " ")}`
    );
  }
};

module.exports.tags = ["all", "token-swap"];
module.exports.dependencies = ["token", "mocks"];
