const { ethers, upgrades } = require("hardhat");

const PROXY = "0xf12dA725562413727f033004181621d55435Fc5e";

async function main() {
    const BitCoinDashStakingV2 = await ethers.getContractFactory("BitCoinDashStakingV2");
  
    console.log("Upgrading BitCoinDashStaking...");
    await upgrades.upgradeProxy(PROXY, BitCoinDashStakingV2);
    console.log("BitCoinDashStaking upgraded.....");
}

main();
