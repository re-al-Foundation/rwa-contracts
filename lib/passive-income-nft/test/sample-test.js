const { expect } = require("chai");
const { ethers } = require("hardhat");

async function skipSeconds(seconds) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine");
}

describe("NFT", function () {
  it("should work", async function () {
    const namedAccounts = await getNamedAccounts();
    deployer = namedAccounts.deployer;

    const GURU = await ethers.getContractFactory("MockGURU");
    const guru = await GURU.deploy();
    await guru.deployed();

    const TNGBL = await ethers.getContractFactory("TangibleERC20");
    const tngbl = await TNGBL.deploy();
    await tngbl.deployed();

    const TokenSwap = await ethers.getContractFactory("TangibleTokenSwap");
    const tokenSwap = await TokenSwap.deploy(guru.address, tngbl.address);
    await tokenSwap.deployed();

    for (const role of [await tngbl.BURNER_ROLE(), await tngbl.MINTER_ROLE()]) {
      const grantRoleTx = await tngbl.grantRole(role, tokenSwap.address);
      await grantRoleTx.wait();
    }

    const initTx = await tokenSwap.initialize();
    await initTx.wait();

    const guruBalance = await guru.balanceOf(deployer);
    const approvalTx = await guru.approve(tokenSwap.address, guruBalance);
    await approvalTx.wait();
    const swapTx = await tokenSwap.swap(guruBalance);
    await swapTx.wait();

    const CALC = await ethers.getContractFactory("PassiveIncomeCalculator");
    const calc = await CALC.deploy();
    await calc.deployed();

    const NFT = await ethers.getContractFactory("PassiveIncomeNFT");
    const nft = await NFT.deploy(tngbl.address, calc.address);
    await nft.deployed();

    const RevenueShare = await ethers.getContractFactory(
      "TangibleRevenueShare"
    );
    const revenueShare = await RevenueShare.deploy(tngbl.address, nft.address); // todo: first arg should be USDC contract address
    await revenueShare.deployed();

    {
      const distributorRole = await revenueShare.DISTRIBUTOR_ROLE();
      const grantRoleTx = await revenueShare.grantRole(
        distributorRole,
        deployer
      );
      await grantRoleTx.wait();
    }

    for (const role of [await tngbl.BURNER_ROLE(), await tngbl.MINTER_ROLE()]) {
      const grantRoleTx = await tngbl.grantRole(role, nft.address);
      await grantRoleTx.wait();
    }

    const amount = ethers.utils.parseEther("10");

    const period = 24;
    for (let i = 1; i <= 10; i++) {
      for (let j = 0; j < 2; j++) {
        const approvalTX = await tngbl.approve(nft.address, amount);
        await approvalTX.wait();
        const mintTX = await nft["mint(address,uint256,uint8)"](
          deployer,
          amount,
          period
        );
        await mintTX.wait();
      }

      const lock = await nft.locks(i * 2);
      const { multiplier } = lock;
      const { timestamp } = await ethers.provider.getBlock("latest");
      console.log(
        "Multiplier for lock period of %s months at %s: %s",
        period,
        new Date(timestamp * 1000),
        multiplier.div(1000000000000000).toNumber() / 1000
      );

      await skipSeconds(60 * 60 * 24);
      const ci = await nft.claimableIncome(i);

      await nft.setNextSnapshot(timestamp);
      console.log(await nft.getShareAt(1, timestamp));

      // console.log("free: ", ethers.utils.formatEther(ci[0]));
      // console.log("total:", ethers.utils.formatEther(ci[1]));
    }
  });
});
