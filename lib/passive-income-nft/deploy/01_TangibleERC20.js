const { developmentChains } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const TNGBL = await deploy("TangibleERC20", {
    from: deployer,
    log: true,
  });
  log(`TGNBL deployed to ${TNGBL.address}`);

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${TNGBL.address}`
    );
  }
};

module.exports.tags = ["all", "token"];
