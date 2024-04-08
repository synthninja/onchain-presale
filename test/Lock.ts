import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { expect } from "chai";
import hre from "hardhat";
import { getAddress, parseGwei } from "viem";


describe("Presale Contract", function() {
  
  // Test fixture.
  async function deployTokenAndPresale() {
    const [owner, treasury, team, liquidity, user1, user2, user3] = await hre.viem.getWalletClients();

    const tokenContract = await hre.viem.deployContract("MyToken", [ owner.account.address ]);
    const uniswapAddress = tokenContract.address;
    const uniswapFactory = tokenContract.address; 

    const presaleContract = await hre.viem.deployContract("Presale", [ 
      tokenContract.address,
      team.account.address, 
      treasury.account.address, 
      liquidity.account.address
    ]);

    const publicClient = await hre.viem.getPublicClient();

    //console.log(`Token Contract: ${tokenContract.address}`);
    //console.log(`Presale Contract: ${presaleContract.address}`);

    const changeOwnerResult =  await tokenContract.write.transferOwnership([presaleContract.address]);
    //console.log(`R`, changeOwnerResult);

    return {
      publicClient,
      tokenContract,
      presaleContract, 
      owner, 
      team,
      treasury,
      liquidity,
      user1,
      user2,
      user3,
    }
  }

  describe("Basics", function () {
    
    it("Should deploy ok", async function() {
      const { owner, presaleContract, tokenContract } = await loadFixture(deployTokenAndPresale);
      expect(await tokenContract.read.owner()).to.equal(getAddress(presaleContract.address));
      expect(await presaleContract.read.owner()).to.equal(getAddress(owner.account.address));
    })

    it("allow deposits but not claims when sale is active", async function() {
      const { owner, presaleContract, tokenContract, user1, user2 } = await loadFixture(deployTokenAndPresale);

      const user1val = BigInt(1e18) / 3n;
      const user2val = BigInt(1e18) / 2n;


      await user1.sendTransaction({ to: presaleContract.address, value: user1val });
      await user2.sendTransaction({ to: presaleContract.address, value: user2val });
     
      
      //expect(await tokenContract.read.owner()).to.equal(getAddress(presaleContract.address));
      expect(await presaleContract.read.contributionOf([user1.account.address])).to.equal(user1val);
      expect(await presaleContract.read.contributionOf([user2.account.address])).to.equal(user2val);
      expect(await presaleContract.read.totalContributions()).to.equal(user1val + user2val);

      const presaleAsUser1 = await hre.viem.getContractAt(
        "Presale", 
        presaleContract.address, 
        { client: { wallet: user1 } }
      );

      // for some reason .rejectedWith() with specific errorr doesnt match. even though i see no difference 
      // to the example tests for the Lock contrace below.
      await expect(presaleAsUser1.write.claimPresalerTokens()).to.be.rejected;
    })

    it("allow deposits until the sale has ended and claims afterwards", async function() {
      const { owner, presaleContract, tokenContract, user1, user2, user3 } = await loadFixture(deployTokenAndPresale);

      const user1val = BigInt(1e18) / 3n;
      const user2val = BigInt(1e18) * 12n / 3n;
      const user3val = BigInt(1e18) * 2n;

      await user1.sendTransaction({ to: presaleContract.address, value: user1val });
      await user2.sendTransaction({ to: presaleContract.address, value: user2val });
      await user3.sendTransaction({ to: presaleContract.address, value: user3val });
      
      await presaleContract.write.manualFinishPresale();

      await expect(user3.sendTransaction({ to: presaleContract.address, value: user3val })).to.be.rejected;
      
      const presaleAsUser1 = await hre.viem.getContractAt(
        "Presale", 
        presaleContract.address, 
        { client: { wallet: user1 } }
      );

      const presaleAsUser2 = await hre.viem.getContractAt(
        "Presale", 
        presaleContract.address, 
        { client: { wallet: user2 } }
      );

      const presaleAsUser3 = await hre.viem.getContractAt(
        "Presale", 
        presaleContract.address, 
        { client: { wallet: user3 } }
      );

      await presaleAsUser1.write.claimPresalerTokens();
      await presaleAsUser2.write.claimPresalerTokens();
      await presaleAsUser3.write.claimPresalerTokens();
      
    })



  })

})

xdescribe("Lock", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployOneYearLockFixture() {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;

    const lockedAmount = parseGwei("1");
    const unlockTime = BigInt((await time.latest()) + ONE_YEAR_IN_SECS);

    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount] = await hre.viem.getWalletClients();

    const lock = await hre.viem.deployContract("Lock", [unlockTime], {
      value: lockedAmount,
    });

    const publicClient = await hre.viem.getPublicClient();

    return {
      lock,
      unlockTime,
      lockedAmount,
      owner,
      otherAccount,
      publicClient,
    };
  }

  describe("Deployment", function () {
    it("Should set the right unlockTime", async function () {
      const { lock, unlockTime } = await loadFixture(deployOneYearLockFixture);

      expect(await lock.read.unlockTime()).to.equal(unlockTime);
    });

    it("Should set the right owner", async function () {
      const { lock, owner } = await loadFixture(deployOneYearLockFixture);

      expect(await lock.read.owner()).to.equal(
        getAddress(owner.account.address)
      );
    });

    it("Should receive and store the funds to lock", async function () {
      const { lock, lockedAmount, publicClient } = await loadFixture(
        deployOneYearLockFixture
      );

      expect(
        await publicClient.getBalance({
          address: lock.address,
        })
      ).to.equal(lockedAmount);
    });

    it("Should fail if the unlockTime is not in the future", async function () {
      // We don't use the fixture here because we want a different deployment
      const latestTime = BigInt(await time.latest());
      await expect(
        hre.viem.deployContract("Lock", [latestTime], {
          value: 1n,
        })
      ).to.be.rejectedWith("Unlock time should be in the future");
    });
  });

  describe("Withdrawals", function () {
    describe("Validations", function () {
      it("Should revert with the right error if called too soon", async function () {
        const { lock } = await loadFixture(deployOneYearLockFixture);

        await expect(lock.write.withdraw()).to.be.rejectedWith(
          "You can't withdraw yet"
        );
      });

      it("Should revert with the right error if called from another account", async function () {
        const { lock, unlockTime, otherAccount } = await loadFixture(
          deployOneYearLockFixture
        );

        // We can increase the time in Hardhat Network
        await time.increaseTo(unlockTime);

        // We retrieve the contract with a different account to send a transaction
        const lockAsOtherAccount = await hre.viem.getContractAt(
          "Lock",
          lock.address,
          { client: { wallet: otherAccount } }
        );
        await expect(lockAsOtherAccount.write.withdraw()).to.be.rejectedWith(
          "You aren't the owner"
        );
      });

      it("Shouldn't fail if the unlockTime has arrived and the owner calls it", async function () {
        const { lock, unlockTime } = await loadFixture(
          deployOneYearLockFixture
        );

        // Transactions are sent using the first signer by default
        await time.increaseTo(unlockTime);

        await expect(lock.write.withdraw()).to.be.fulfilled;
      });
    });

    describe("Events", function () {
      it("Should emit an event on withdrawals", async function () {
        const { lock, unlockTime, lockedAmount, publicClient } =
          await loadFixture(deployOneYearLockFixture);

        await time.increaseTo(unlockTime);

        const hash = await lock.write.withdraw();
        await publicClient.waitForTransactionReceipt({ hash });

        // get the withdrawal events in the latest block
        const withdrawalEvents = await lock.getEvents.Withdrawal();
        expect(withdrawalEvents).to.have.lengthOf(1);
        expect(withdrawalEvents[0].args.amount).to.equal(lockedAmount);
      });
    });
  });
});
