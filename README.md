
# Actual Readme 

This was created from `npx hardhat create`. With the 'viem' options The Lock.sol contract and tests for that contract are just left in for reference. 

To run tests, you need something resembling base mainnet, since they interact with uniswap. You can fork the base mainnet to run as a local node with: 

`npx hardhat node --fork https://base-mainnet.g.alchemy.com/v2/SGZbcGBiY4qLKbFGk5Xh8uZxbwU2FnED --fork-block-number 12893667`

Leave that running and in another window run 

`npx hardhat test --network localhost`. 

Contract logs will be output in from the forked mainnet runniner. 

https://hardhat.org/docs
https://viem.sh/docs/



# Boilerplate Readme

## Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a Hardhat Ignition module that deploys that contract.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.ts
```
