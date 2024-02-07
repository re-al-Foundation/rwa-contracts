const hre = require("hardhat");

const { ethers } = hre;
const { developmentChains, networkConfig } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { execute, deploy, get, log, read } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const usdcAddress =
    developmentChains.includes(network.name) &&
    !networkConfig[network.name].addresses.USDC
      ? (await get("MockUSDC")).address
      : networkConfig[network.name].addresses.USDC;

  const routerAddress =
    developmentChains.includes(network.name) &&
    !networkConfig[network.name].addresses.router
      ? (await get("MockRouter")).address
      : networkConfig[network.name].addresses.router;

  const NFT = await get("PassiveIncomeNFT");
  const SafeCollectionLib = await deploy("SafeCollection", {
    from: deployer,
    log: true,
  });

  const RevenueDistributor = await get("RevenueDistributor");

  if (!developmentChains.includes(network.name)) {
    // await hre.run("verify:verify", {address: SafeCollectionLib.address})
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${SafeCollectionLib.address}`
    );
  }

  log("----------------------------------------------------");

  const args = [usdcAddress, NFT.address, routerAddress];

  const Marketplace = await deploy("Marketplace", {
    from: deployer,
    args: args,
    libraries: {
      SafeCollection: SafeCollectionLib.address,
    },
    log: true,
  });
  log(`Marketplace deployed to ${Marketplace.address}`);

  await execute(
    "PassiveIncomeNFT",
    { from: deployer, log: true },
    "setMarketplaceContract",
    Marketplace.address
  );

  await execute(
    "Marketplace",
    { from: deployer, log: true },
    "setFeeCollector",
    RevenueDistributor.address
  );

  await execute("Marketplace", { from: deployer, log: true }, "setFee", 250);

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${
        Marketplace.address
      } ${args.toString().replace(/,/g, " ")}`
    );
  }
};

module.exports.tags = ["all", "marketplace"];
module.exports.dependencies = ["nft"];
