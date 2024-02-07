const hre = require("hardhat");

const { ethers } = hre;

const { developmentChains, networkConfig } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { execute, deploy, log, read, get } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const revenueTokenContractAddress =
    developmentChains.includes(network.name) &&
    !networkConfig[network.name].addresses.USDC
      ? (await get("MockUSDC")).address
      : networkConfig[network.name].addresses.USDC;

  const args = [
    revenueTokenContractAddress,
    networkConfig[network.name].addresses.GELATO_OPS,
  ];

  const RentShare = await deploy("RentShare", {
    from: deployer,
    args: args,
    log: true,
    contract: "TangibleRentShare",
  });
  log(`Rent Share deployed to ${RentShare.address}`);

  const adminRole = await read(
    "RentShare",
    { from: deployer, log: true },
    "DEFAULT_ADMIN_ROLE"
  );

  const shareManagerRole = await read(
    "RentShare",
    { from: deployer, log: true },
    "SHARE_MANAGER_ROLE"
  );

  const depositorRole = await read(
    "RentShare",
    { from: deployer, log: true },
    "DEPOSITOR_ROLE"
  );

  await execute(
    "RentShare",
    { from: deployer, log: true },
    "grantRole",
    adminRole,
    networkConfig[network.name].addresses.TANGIBLE_DEPLOYER
  );

  await execute(
    "RentShare",
    { from: deployer, log: true },
    "grantRole",
    shareManagerRole,
    deployer
  );

  await execute(
    "RentShare",
    { from: deployer, log: true },
    "grantRole",
    depositorRole,
    deployer
  );

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify Rent Share contract with:\n npx hardhat verify --network ${
        network.name
      } ${RentShare.address} ${args.toString().replace(/,/g, " ")}`
    );
  }
};

module.exports.tags = ["all", "rent"];
module.exports.dependencies = ["token"];
