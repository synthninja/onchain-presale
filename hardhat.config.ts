import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";

const config: HardhatUserConfig = {
  solidity: "0.8.24",
  networks: {
    forkedbase: {
      url: 'https://base-mainnet.g.alchemy.com/v2/SGZbcGBiY4qLKbFGk5Xh8uZxbwU2FnED',
      forking: {
        url: 'https://base-mainnet.g.alchemy.com/v2/SGZbcGBiY4qLKbFGk5Xh8uZxbwU2FnED',
        blockNumber: 12893667,
      }
    }
  }
};

export default config;

task('closePresale', 'Closes the presale')
  .addPositionalParam('contract')
  .setAction(
    async ({ contract }, hre) => {    
      const Presale = await hre.viem.getContractAt('Presale', contract);
      await Presale.write.manualFinishPresale();
  });
