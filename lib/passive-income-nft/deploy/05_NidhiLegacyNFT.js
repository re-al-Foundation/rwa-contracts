const { developmentChains } = require("../hardhat-config-utils");

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  log("----------------------------------------------------");

  const NFT = await deploy("NidhiLegacyNFT", {
    from: deployer,
    log: true,
  });
  log(`Nidhi Legacy NFT deployed to ${NFT.address}`);

  if (!developmentChains.includes(network.name)) {
    log(
      `Verify with:\n npx hardhat verify --network ${network.name} ${NFT.address}`
    );
  }
};

module.exports.tags = ["all", "legacy"];
