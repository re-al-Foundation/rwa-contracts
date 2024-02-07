const hre = require("hardhat");

const { ethers } = hre;

const { developmentChains, networkConfig } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { execute, deploy, log, read, get } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const RevenueShare = await get("RevenueShare");

  const args = [
    RevenueShare.address,
  ];

  const RevenueShareCleanup = await deploy("RevenueShareCleanup", {
    from: deployer,
    args: args,
    log: true,
  });
  log(`Revenue Share Cleanup deployed to ${RevenueShareCleanup.address}`);

  const shareManager = await read(
    "RevenueShare",
    { from: deployer, log: true },
    "SHARE_MANAGER_ROLE"
  );

  await execute(
    "RevenueShare",
    { from: deployer, log: true },
    "grantRole",
    shareManager,
    RevenueShareCleanup.address
  );

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${
        RevenueShareCleanup.address
      } ${args.toString().replace(/,/g, " ")}`
    );
  }
};

module.exports.tags = ["all", "cleanup"];
module.exports.dependencies = ["revenue"];
