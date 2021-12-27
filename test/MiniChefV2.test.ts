import { expect, assert } from "chai";
import { advanceTime, advanceTimeAndBlock, advanceBlockTo, advanceBlock, prepare, deploy, getBigNumber, ADDRESS_ZERO } from "./utilities"
const { BigNumber } = require("ethers")
import {ethers} from "hardhat"

describe("MiniChefV2", function () {
  before(async function () {
    await prepare(this, ['MiniChefV2', 'LqdrToken', 'ERC20Mock', 'RewarderMock', 'RewarderBrokenMock', 'LiquidDepositor'])
    await deploy(this, [
      ["brokenRewarder", this.RewarderBrokenMock]
    ])
  })

  beforeEach(async function () {
    await deploy(this, [
      ["lqdr", this.LqdrToken],
    ])

    await deploy(this,
      [["lp", this.ERC20Mock, ["LP Token", "LPT", getBigNumber(10)]],
      ["dummy", this.ERC20Mock, ["Dummy", "DummyT", getBigNumber(10)]],
      ['chef', this.MiniChefV2, [this.lqdr.address, this.dev.address]],
      ["rlp", this.ERC20Mock, ["LP", "rLPT", getBigNumber(10)]],
      ["r", this.ERC20Mock, ["Reward", "RewardT", getBigNumber(100000)]],
    ])

    await deploy(this, [
      ['depositor', this.LiquidDepositor, [this.chef.address]],
    ])
    await deploy(this, [["rewarder", this.RewarderMock, [getBigNumber(1), this.r.address, this.chef.address]]])

    await this.lqdr.mint(this.chef.address, getBigNumber(10000))
    await this.lp.approve(this.chef.address, getBigNumber(10))
    await this.chef.setLqdrPerSecond("10000000000000000")
    await this.rlp.transfer(this.bob.address, getBigNumber(1))
  })

  describe("PoolLength", function () {
    it("PoolLength should execute", async function () {
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
      expect((await this.chef.poolLength())).to.be.equal(1);
    })
  })

  describe("Set", function() {
    it("Should emit event LogSetPool", async function () {
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
      await expect(this.chef.set(0, 10, this.dummy.address, 0, false))
            .to.emit(this.chef, "LogSetPool")
            .withArgs(0, 10, this.rewarder.address, false)
      await expect(this.chef.set(0, 10, this.dummy.address, 0, true))
            .to.emit(this.chef, "LogSetPool")
            .withArgs(0, 10, this.dummy.address, true)
      })

    it("Should revert if invalid pool", async function () {
      let err;
      try {
        await this.chef.set(0, 10, this.rewarder.address, 0, false)
      } catch (e) {
        err = e;
      }

      assert.equal(err.toString(), "Error: VM Exception while processing transaction: invalid opcode")
    })
  })

  describe("PendingLqdr", function() {
    it("PendingLqdr should equal ExpectedLqdr", async function () {
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
      await this.rlp.approve(this.chef.address, getBigNumber(10))
      let log = await this.chef.deposit(0, getBigNumber(1), this.alice.address)
      await advanceTime(86400)
      let log2 = await this.chef.updatePool(0)
      let timestamp2 = (await ethers.provider.getBlock(log2.blockNumber)).timestamp
      let timestamp = (await ethers.provider.getBlock(log.blockNumber)).timestamp
      let expectedLqdr = BigNumber.from("10000000000000000").mul(timestamp2 - timestamp)
      let pendingLqdr = await this.chef.pendingLqdr(0, this.alice.address)
      expect(pendingLqdr).to.be.equal(expectedLqdr)
    })
    it("When time is lastRewardTime", async function () {
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
      await this.rlp.approve(this.chef.address, getBigNumber(10))
      let log = await this.chef.deposit(0, getBigNumber(1), this.alice.address)
      await advanceBlockTo(3)
      let log2 = await this.chef.updatePool(0)
      let timestamp2 = (await ethers.provider.getBlock(log2.blockNumber)).timestamp
      let timestamp = (await ethers.provider.getBlock(log.blockNumber)).timestamp
      let expectedLqdr = BigNumber.from("10000000000000000").mul(timestamp2 - timestamp)
      let pendingLqdr = await this.chef.pendingLqdr(0, this.alice.address)
      expect(pendingLqdr).to.be.equal(expectedLqdr)
    })
  })

  describe("MassUpdatePools", function () {
    it("Should call updatePool", async function () {
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
      await advanceBlockTo(1)
      await this.chef.massUpdatePools([0])
      //expect('updatePool').to.be.calledOnContract(); //not suported by heardhat
      //expect('updatePool').to.be.calledOnContractWith(0); //not suported by heardhat

    })

    it("Updating invalid pools should fail", async function () {
      let err;
      try {
        await this.chef.massUpdatePools([0, 10000, 100000])
      } catch (e) {
        err = e;
      }

      assert.equal(err.toString(), "Error: VM Exception while processing transaction: invalid opcode")
    })
})

  describe("Add", function () {
    it("Should add pool with reward token multiplier", async function () {
      await expect(this.chef.add(10, this.rlp.address, this.rewarder.address, 0),)
            .to.emit(this.chef, "LogPoolAddition")
            .withArgs(0, 10, this.rlp.address, this.rewarder.address)
      })
  })

  describe("UpdatePool", function () {
    it("Should emit event LogUpdatePool", async function () {
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 100)
      await advanceBlockTo(1)
      await expect(this.chef.updatePool(0))
            .to.emit(this.chef, "LogUpdatePool")
            .withArgs(0, (await this.chef.poolInfo(0)).lastRewardTime,
              (await this.rlp.balanceOf(this.chef.address)),
              (await this.chef.poolInfo(0)).accLqdrPerShare)
    })

    it("Should take else path", async function () {
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
      await advanceBlockTo(1)
      await this.chef.batch(
          [
              this.chef.interface.encodeFunctionData("updatePool", [0]),
              this.chef.interface.encodeFunctionData("updatePool", [0]),
          ],
          true
      )
    })
  })

  describe("Deposit", function () {
    it("Depositing 0 amount", async function () {
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
      await this.rlp.approve(this.chef.address, getBigNumber(10))
      await expect(this.chef.deposit(0, getBigNumber(0), this.alice.address))
            .to.emit(this.chef, "Deposit")
            .withArgs(this.alice.address, 0, 0, this.alice.address)
    })

    it("Depositing into non-existent pool should fail", async function () {
      let err;
      try {
        await this.chef.deposit(1001, getBigNumber(0), this.alice.address)
      } catch (e) {
        err = e;
      }

      assert.equal(err.toString(), "Error: VM Exception while processing transaction: invalid opcode")
    })
  })

  describe("Withdraw", function () {
    it("Withdraw 0 amount", async function () {
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
      await expect(this.chef.withdraw(0, getBigNumber(0), this.alice.address))
            .to.emit(this.chef, "Withdraw")
            .withArgs(this.alice.address, 0, 0, this.alice.address)
    })
  })

  describe("Harvest", function () {
    it("Should give back the correct amount of LQDR and reward", async function () {
        await this.r.transfer(this.rewarder.address, getBigNumber(100000))
        await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
        await this.rlp.approve(this.chef.address, getBigNumber(10))
        expect(await this.chef.lpToken(0)).to.be.equal(this.rlp.address)
        let log = await this.chef.deposit(0, getBigNumber(1), this.alice.address)
        await advanceTime(86400)
        let log2 = await this.chef.withdraw(0, getBigNumber(1), this.alice.address)
        let timestamp2 = (await ethers.provider.getBlock(log2.blockNumber)).timestamp
        let timestamp = (await ethers.provider.getBlock(log.blockNumber)).timestamp
        let expectedLqdr = BigNumber.from("10000000000000000").mul(timestamp2 - timestamp)
        expect((await this.chef.userInfo(0, this.alice.address)).rewardDebt).to.be.equal("-"+expectedLqdr)
        await this.chef.harvest(0, this.alice.address)
        expect(await this.lqdr.balanceOf(this.alice.address)).to.be.equal(await this.r.balanceOf(this.alice.address)).to.be.equal(expectedLqdr)
    })
    it("Harvest with empty user balance", async function () {
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
      await this.chef.harvest(0, this.alice.address)
    })

    it("Harvest for LQDR-only pool", async function () {
      await this.chef.add(10, this.rlp.address, ADDRESS_ZERO, 0)
      await this.rlp.approve(this.chef.address, getBigNumber(10))
      expect(await this.chef.lpToken(0)).to.be.equal(this.rlp.address)
      let log = await this.chef.deposit(0, getBigNumber(1), this.alice.address)
      await advanceBlock()
      let log2 = await this.chef.withdraw(0, getBigNumber(1), this.alice.address)
      let timestamp2 = (await ethers.provider.getBlock(log2.blockNumber)).timestamp
      let timestamp = (await ethers.provider.getBlock(log.blockNumber)).timestamp
      let expectedLqdr = BigNumber.from("10000000000000000").mul(timestamp2 - timestamp)
      expect((await this.chef.userInfo(0, this.alice.address)).rewardDebt).to.be.equal("-"+expectedLqdr)
      await this.chef.harvest(0, this.alice.address)
      expect(await this.lqdr.balanceOf(this.alice.address)).to.be.equal(expectedLqdr)
    })
  })

  describe("Harvest with deposit fee", function () {
    it("Should give back the correct amount of LQDR and reward", async function () {
        await this.r.transfer(this.rewarder.address, getBigNumber(100000))
        await this.chef.add(10, this.rlp.address, this.rewarder.address, 1000)
        await this.rlp.approve(this.chef.address, getBigNumber(10))
        expect(await this.chef.lpToken(0)).to.be.equal(this.rlp.address)
        let log = await this.chef.deposit(0, getBigNumber(1), this.alice.address)
        await advanceTime(86400)
        let log2 = await this.chef.withdraw(0, "900000000000000000", this.alice.address)
        let timestamp2 = (await ethers.provider.getBlock(log2.blockNumber)).timestamp
        let timestamp = (await ethers.provider.getBlock(log.blockNumber)).timestamp
        let expectedLqdr = BigNumber.from("10000000000000000").mul(timestamp2 - timestamp)
        expect((await this.chef.userInfo(0, this.alice.address)).rewardDebt).to.be.equal("-"+expectedLqdr)
        await this.chef.harvest(0, this.alice.address)
        expect(await this.lqdr.balanceOf(this.alice.address)).to.be.equal(await this.r.balanceOf(this.alice.address)).to.be.equal(expectedLqdr)
    })
  })

  describe("EmergencyWithdraw", function() {
    it("Should emit event EmergencyWithdraw", async function () {
      await this.r.transfer(this.rewarder.address, getBigNumber(100000))
      await this.chef.add(10, this.rlp.address, this.rewarder.address, 0)
      await this.rlp.approve(this.chef.address, getBigNumber(10))
      await this.chef.deposit(0, getBigNumber(1), this.bob.address)
      //await this.chef.emergencyWithdraw(0, this.alice.address)
      await expect(this.chef.connect(this.bob).emergencyWithdraw(0, this.bob.address))
      .to.emit(this.chef, "EmergencyWithdraw")
      .withArgs(this.bob.address, 0, getBigNumber(1), this.bob.address)
    })
  })

  describe("SetLiquidDepositor", function() {
    it("Should set liquidDepositor", async function () {
      await this.chef.setLiquidDepositor(this.depositor.address)
      expect((await this.chef.liquidDepositor())).to.be.equal(this.depositor.address);
    })

    it("Should renounce liquidDepositor", async function () {
      await this.chef.setLiquidDepositor(this.depositor.address)
      expect((await this.chef.liquidDepositor())).to.be.equal(this.depositor.address);
      await this.chef.renounceLiquidDepositor()
      expect((await this.chef.liquidDepositor())).to.be.equal("0x0000000000000000000000000000000000000000");
    })
  })

  describe("Deposit to liquidDepositor", function() {
    it("Should deposit to liquidDepositor", async function () {
      await this.chef.setLiquidDepositor(this.depositor.address)
      expect((await this.chef.liquidDepositor())).to.be.equal(this.depositor.address);

      await this.chef.add(10, this.rlp.address, "0x0000000000000000000000000000000000000000", 0)

      await this.rlp.approve(this.chef.address, getBigNumber(10))
      expect(await this.chef.lpToken(0)).to.be.equal(this.rlp.address)
      await this.chef.deposit(0, getBigNumber(1), this.alice.address)
      expect(await this.rlp.balanceOf(this.alice.address)).to.be.equal(getBigNumber(8))

      await this.chef.massDepositAllToLiquidDepositor();
      expect(await this.depositor.balanceOf(this.rlp.address)).to.be.equal(getBigNumber(1))

      await this.chef.withdraw(0, getBigNumber(1), this.alice.address)
      expect(await this.rlp.balanceOf(this.alice.address)).to.be.equal(getBigNumber(9))
      expect(await this.rlp.balanceOf(this.depositor.address)).to.be.equal(0)
    })
  })
})
