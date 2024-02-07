const { developmentChains } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  console.log("Deployer:", deployer);
  if (developmentChains.includes(network.name)) {
    log("----------------------------------------------------");

    const GURU = await deploy("MockGURU", {
      from: deployer,
      log: true,
    });
    log(`Mock GURU deployed to ${GURU.address}`);
  }
};

module.exports.tags = ["all", "mocks"];
