// scripts/deploy_upgradeable_box.js
const { ethers, upgrades } = require("hardhat");

async function main() {
    const BitCoinDashStaking = await ethers.getContractFactory("BitCoinDashStaking");
    console.log("Deploying BitCoinDashStaking...");
    const bitCoinDashStaking = await upgrades.deployProxy(BitCoinDashStaking, [
        "0x57229A8b475ce8E1aEe2C0cC81dd3700BCdF5DB8",
        "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
        "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
        "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
        "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
       "0x9e10b50833504655b4671F21900602E3C569C83C",
      [  
       "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8", 
       "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8", 
       "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
       "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
       "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
       "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
       "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
       "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
       "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8",
       "0x0A0Cfbf38Ca51F39bD6947a0708E1965E6E0f6B8"
    ]

    ], {
        initializer: "initialize",
    });
    await bitCoinDashStaking.deployed();
    console.log("Contract deployed to:", bitCoinDashStaking.address);
}

main();

//_tokenAddress, 
//_treasuryWallet,
//_marketingWallet,
//_charityWallet,
//_chimneyWallet,
//_adminWallet,
//_leaders address 
           
//Contract deployed to: 0x6508643f624689398bcf9Ce55B766a9BC95e2802







