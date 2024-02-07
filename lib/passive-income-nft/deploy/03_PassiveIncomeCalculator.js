const { developmentChains } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const Calculator = await deploy("PassiveIncomeCalculator", {
    from: deployer,
    log: true,
  });
  log(`Passive Income Calculator deployed to ${Calculator.address}`);

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${Calculator.address}`
    );
  }
};

module.exports.tags = ["all", "calculator"];
