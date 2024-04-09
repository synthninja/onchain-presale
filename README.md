
# Actual Readme 

This was created from `npx hardhat create`. With the 'viem' options. 

The Lock.sol contract and tests for that contract are just left in for reference. 

To run tests, you need forked (base) network running locally. (tests interact with uniswap). 

`npx hardhat node --fork https://base-mainnet.g.alchemy.com/v2/SGZbcGBiY4qLKbFGk5Xh8uZxbwU2FnED --fork-block-number 12893667`

NOTE: You may need to update the blocknumber to a more recent block from https://basescan.org 

In another window: 

`npx hardhat test --network localhost`. 

Contract logs will be output in from the forked mainnet runniner. 

You can also deploy to the local running forked mainnet with: 

`npx hardhat ignition deploy ignition/modules/PresaleAndToken.ts --network localhost`

This will create deployment record in `ignition/deployment/...` which will need to be wiped you want to redploy a new version (`npx hardhat ignition wipe` or rm -rf the relevant folder in `ignition/deployments`)


### Tooling docs

- https://hardhat.org/docs
- https://viem.sh/docs/


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
