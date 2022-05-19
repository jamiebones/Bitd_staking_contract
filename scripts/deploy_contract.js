// scripts/deploy_upgradeable_box.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  const BitCoinDashStaking = await ethers.getContractFactory(
    "BitCoinDashStaking"
  );
  console.log("Deploying BitCoinDashStaking...");
  const bitCoinDashStaking = await upgrades.deployProxy(
    BitCoinDashStaking,
    [
      "0x33cF32D37C1a1209615bfFEaD30edEA8000F9849", //uniswap pair address
      "0x638406bba7f0ea45ee2c5ad766f76d9233eb44ae", //token address
      "0x6A5Adf0dc7945C4784f4f4Ecd1A46B7cd809c755", //treasury
      "0x032e7d1F084863F4FF4Fc52c34920f44AEAB15D1", //marketing
      "0xC47c0685559fa4aC308763ded7B89562022669D0", //charity
      "0xD06C794800C6d80F0f6ad54bdC4392Ec3C1B29B5", //chimney
      "0x7b0E884A5aC3D5e86178f78A77825d5A4C7940cC", //admin
      [
        "0x8ceD8de7c093e2C21566D50d7e7abE5c33359CAE",
        "0xeb303e3A046641059fFd20e69fBBA2e3635B79e1",
        "0x156AadC32Ef0E3A41bB3755f7376F8C1e30C032a", //leaders wallet
        "0x156AadC32Ef0E3A41bB3755f7376F8C1e30C032a",
        "0xA4509D475FE6571615F1d1319Eb4E17C13582E4b",
        "0xBFcc99B4dF1bD97A36912a38d638CfAAFC2937D6",
        "0xEeEeDB49835a11E740Ff86aef83AdE0e2aE49C08",
        "0x829aCDF45383563d0FD3Ba992847995F5d0aBf48",
        "0x5397457D0244BE84B16426F404E64fdb390FCb50",
        "0x0FCc8c66778c65aA9B65a582BCe77CdBBA15693D",
      ],
    ],
    {
      initializer: "initialize",
    }
  );
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

//Contract deployed to: 0xf12dA725562413727f033004181621d55435Fc5e


//mainnet: Contract deployed to: 0xE3987eA63Cc5Abc229891Df4aCf1624c51e08815

