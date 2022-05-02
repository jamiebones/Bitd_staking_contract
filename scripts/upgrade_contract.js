const { ethers, upgrades } = require("hardhat");

const PROXY = "0xaf03a6F46Eea7386F3E5481a4756efC678a624e6";

async function main() {
    const CalculatorV2 = await ethers.getContractFactory("CalculatorV2");
    console.log("Upgrading Calculator...");
    await upgrades.upgradeProxy(PROXY, CalculatorV2);
    console.log("Calculator upgraded");
}

main();
