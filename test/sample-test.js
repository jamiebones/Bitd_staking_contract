const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BitCoinDashStaking", function () {
  it("Should return the new greeting once it's changed", async function () {
    const BITD = await ethers.getContractFactory("BitCoinDashStaking");
    const bitd = await Greeter.deploy("Hello, world!");
    await bitd.deployed();

    expect(await greeter.greet()).to.equal("Hello, world!");

    const setGreetingTx = await greeter.setGreeting("Hola, mundo!");

    // wait until the transaction is mined
    await setGreetingTx.wait();

    expect(await greeter.greet()).to.equal("Hola, mundo!");
  });
});
