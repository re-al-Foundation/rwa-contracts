const hre = require("hardhat");

const { ethers } = hre;

const { developmentChains, networkConfig } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { execute, deploy, log, read, get } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const NFT = await get("PassiveIncomeNFT");

  const revenueTokenContractAddress =
    developmentChains.includes(network.name) &&
    !networkConfig[network.name].addresses.USDC
      ? (await get("MockUSDC")).address
      : networkConfig[network.name].addresses.USDC;

  const args = [revenueTokenContractAddress];

  const RevenueShare = await deploy("RevenueShare", {
    from: deployer,
    args: args,
    log: true,
    contract: "TangibleRevenueShare",
  });
  log(`Revenue Share deployed to ${RevenueShare.address}`);

  const RevenueDistributor = await deploy("RevenueDistributor", {
    from: deployer,
    args: args,
    log: true,
    contract: "RevenueDistributor",
  });
  log(`Revenue Distributor deployed to ${RevenueDistributor.address}`);

  const distributorRole = await read(
    "RevenueDistributor",
    { from: deployer, log: true },
    "DISTRIBUTOR_ROLE"
  );

  await execute(
    "RevenueDistributor",
    { from: deployer, log: true },
    "grantRole",
    distributorRole,
    deployer
  );

  await execute(
    "RevenueDistributor",
    { from: deployer, log: true },
    "grantRole",
    distributorRole,
    networkConfig[network.name].addresses.GELATO_OPS
  );

  await execute(
    "RevenueDistributor",
    { from: deployer, log: true },
    "setRevenueShareContract",
    RevenueShare.address
  );

  await execute(
    "RevenueDistributor",
    { from: deployer, log: true },
    "start",
    networkConfig[network.name].addresses.GELATO_OPS
  );

  await execute(
    "PassiveIncomeNFT",
    { from: deployer, log: true },
    "setRevenueShareContract",
    RevenueShare.address
  );

  const adminRole = await read(
    "RevenueShare",
    { from: deployer, log: true },
    "DEFAULT_ADMIN_ROLE"
  );

  const shareManagerRole = await read(
    "RevenueShare",
    { from: deployer, log: true },
    "SHARE_MANAGER_ROLE"
  );

  const depositorRole = await read(
    "RevenueShare",
    { from: deployer, log: true },
    "DEPOSITOR_ROLE"
  );

  await execute(
    "RevenueShare",
    { from: deployer, log: true },
    "grantRole",
    adminRole,
    networkConfig[network.name].addresses.TANGIBLE_DEPLOYER
  );

  await execute(
    "RevenueShare",
    { from: deployer, log: true },
    "grantRole",
    shareManagerRole,
    deployer
  );

  await execute(
    "RevenueShare",
    { from: deployer, log: true },
    "grantRole",
    depositorRole,
    RevenueDistributor.address
  );

  await execute(
    "RevenueShare",
    { from: deployer, log: true },
    "grantRole",
    shareManagerRole,
    NFT.address
  );

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify Revenue Share contract with:\n npx hardhat verify --network ${
        network.name
      } ${RevenueShare.address} ${args.toString().replace(/,/g, " ")}`
    );
    log(
      `Verify Revenue Distributor contract with:\n npx hardhat verify --network ${
        network.name
      } ${RevenueDistributor.address} ${args.toString().replace(/,/g, " ")}`
    );
  }
};

module.exports.tags = ["all", "revenue"];
module.exports.dependencies = ["token", "nft"];
