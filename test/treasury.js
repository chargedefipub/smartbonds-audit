const { ethers } = require('hardhat');
const { expect, assert, should, eventually } = require('chai');
const { smockit } = require('@eth-optimism/smock');
const { intToBuffer } = require('ethjs-util');
const { BigNumber } = require('@ethersproject/bignumber');
const { smoddit } = require('@eth-optimism/smock');
const chai = require('chai');
var chaiAsPromised = require('chai-as-promised');

chai.use(chaiAsPromised);

describe('treasury', function () {
	var pulse;
	var bts;
	var dollar;
	var treasury;
	var boardroom;
	var oracle;
	var boardroomAllocation;
	var busd;
	var smartBondPool;

	const onePointTen = BigNumber.from('1100000000000000000');
	const one = BigNumber.from('1000000000000000000');
	const ten = BigNumber.from('10000000000000000000');
	const oneHundred = BigNumber.from('100000000000000000000');
	const oneTenth = BigNumber.from('100000000000000000');
	const oneHundredth = BigNumber.from('10000000000000000');
	const zero = BigNumber.from('0');
	const oneBillion = BigNumber.from('1000000000000000000000000000');
	const dollarPriceCeiling = BigNumber.from('1010000000000000000');
	const period = 8 * 60 * 60;

	beforeEach(async () => {
		[owner, user2, user3] = await ethers.getSigners();

		const dollarFactory = await ethers.getContractFactory('Static');
		dollar = await dollarFactory.deploy('Static', 'Static');

		const btsFactory = await smoddit('Charge');
		bts = await btsFactory.deploy(ethers.utils.parseEther('10000000000'));

		const pulseFactory = await ethers.getContractFactory('Pulse');
		pulse = await pulseFactory.deploy();

		const busdFactory = await ethers.getContractFactory('BUSD');
		busd = await busdFactory.deploy('BUSD', 'BUSD');

		const oracleFactory = await ethers.getContractFactory('MockOracle');
		oracle = await oracleFactory.deploy();

		const boardroomFactory = await ethers.getContractFactory(
			'MockBoardroom'
		);
		boardroom = await boardroomFactory.deploy(dollar.address, bts.address);

		const boardroomAllocationFactory = await ethers.getContractFactory(
			'BoardroomAllocation'
		);
		boardroomAllocation = await boardroomAllocationFactory.deploy();
		await boardroomAllocation.addBoardroom(boardroom.address, 1000, 1000);

		const routerFactory = await ethers.getContractFactory('PancakeRouter');
		const router = await routerFactory.deploy(busd.address, busd.address);

		const smartBondPoolFactory = await ethers.getContractFactory(
			'SmartBondPool'
		);
		smartBondPool = await smartBondPoolFactory.deploy(
			pulse.address,
			busd.address,
			dollar.address,
			router.address
		);

		const treasuryFactory = await smoddit('Treasury');
		treasury = await treasuryFactory.deploy();

		await treasury.deployed();

		await treasury.initialize(
			period,
			dollar.address,
			pulse.address,
			bts.address,
			BigNumber.from(Math.round(new Date().getTime() / 1000), 0),
			user3.address,
			boardroomAllocation.address,
			oracle.address,
			smartBondPool.address
		);
		await treasury.setDollarPriceCeiling(dollarPriceCeiling);
		await treasury.setSharesMintedPerEpoch(one);

		await dollar.grantRole(await dollar.rebaserRole(), owner.address);
		await dollar.grantRole(await dollar.minterRole(), owner.address);
		await dollar.grantRole(await dollar.rebaserRole(), user2.address);
		await dollar.grantRole(await dollar.minterRole(), user2.address);
		await dollar.grantRole(await dollar.minterRole(), treasury.address);
		await dollar.grantRole(await dollar.rebaserRole(), treasury.address);
		await treasury.grantRole(await treasury.allocatorRole(), owner.address);

		await bts.registerMinter(
			treasury.address,
			ethers.utils.parseEther('10000000000000')
		);

		await pulse.grantRole(await pulse.minterRole(), treasury.address);
	});

	describe('bonds', () => {
		it("Can't buy when above 0", async () => {
			var price = onePointTen;

			await oracle.setPrice(price);
			await dollar.mint(owner.address, one);
			await dollar.approve(treasury.address, one);
			var buyBonds = treasury.buyBonds(one);

			expect(buyBonds).eventually.to.rejectedWith(
				Error,
				"VM Exception while processing transaction: reverted with reason string 'DollarPrice not eligible for bond purchase'"
			);
		});

		it("Can't buy when below 0 and all bonds bought for epoch", async () => {
			var price = ethers.utils.parseEther('0.1');
			const numBonds1 = ethers.utils.parseEther('0.2');
			const numBonds2 = ethers.utils.parseEther('0.1');

			await oracle.setPrice(price);
			await dollar.mint(owner.address, ethers.utils.parseEther('1'));
			await dollar.approve(
				treasury.address,
				ethers.utils.parseEther('1')
			);

			await treasury.setContractionIndex(0);
			await treasury.setMaxSupplyContractionPercent(2000); // 20% percent
			await treasury.setMaxDebtRatioPercent(10000); // 100%

			await treasury.allocateSeigniorage();
			await treasury.buyBonds(numBonds1);

			await expect(treasury.buyBonds(numBonds2)).to.be.revertedWith(
				'Not enough bond left to purchase this epoch'
			);

			var btdBalance = await dollar.balanceOf(owner.address);
			var btbBalance = await pulse.balanceOf(owner.address);

			assert.equal(btdBalance.toString(), one.sub(numBonds1).toString());
			assert.equal(btbBalance.toString(), numBonds1.toString());
		});

		it("Can't buy when below 0, bonds available for epoch and max debt hit", async () => {
			var price = ethers.utils.parseEther('0.1');
			const numBonds1 = ethers.utils.parseEther('0.2');
			const numBonds2 = ethers.utils.parseEther('0.1');

			await oracle.setPrice(price);
			await dollar.mint(owner.address, ethers.utils.parseEther('1'));
			await dollar.approve(
				treasury.address,
				ethers.utils.parseEther('1')
			);

			await treasury.setContractionIndex(0);
			await treasury.setMaxSupplyContractionPercent(2000); // 20% percent
			await treasury.setMaxDebtRatioPercent(2000); // 20% percent

			await treasury.allocateSeigniorage();
			await treasury.buyBonds(numBonds1);

			await network.provider.send('evm_increaseTime', [
				(await treasury.PERIOD()).toNumber(),
			]);
			await network.provider.send('evm_mine');
			await treasury.allocateSeigniorage();

			await expect(treasury.buyBonds(numBonds2)).to.be.revertedWith(
				'over max debt ratio'
			);

			var btdBalance = await dollar.balanceOf(owner.address);
			var btbBalance = await pulse.balanceOf(owner.address);

			assert.equal(btdBalance.toString(), one.sub(numBonds1).toString());
			assert.equal(btbBalance.toString(), numBonds1.toString());
		});

		it('Can buy when below 0, bonds available for epoch and max debt not hit', async () => {
			var price = ethers.utils.parseEther('0.1');
			const numBonds1 = ethers.utils.parseEther('0.1');
			const numBonds2 = ethers.utils.parseEther('0.1');

			await oracle.setPrice(price);
			await dollar.mint(owner.address, ethers.utils.parseEther('1'));
			await dollar.approve(
				treasury.address,
				ethers.utils.parseEther('1')
			);

			await treasury.setContractionIndex(0);
			await treasury.setMaxSupplyContractionPercent(2000); // 20% percent
			await treasury.setMaxDebtRatioPercent(3000); // 30% percent

			await treasury.allocateSeigniorage();
			await treasury.buyBonds(numBonds1);
			await treasury.buyBonds(numBonds2);

			var btdBalance = await dollar.balanceOf(owner.address);
			var btbBalance = await pulse.balanceOf(owner.address);

			assert.equal(
				btdBalance.toString(),
				one.sub(numBonds1).sub(numBonds2).toString()
			);
			assert.equal(
				btbBalance.toString(),
				numBonds1.add(numBonds2).toString()
			);
		});

		it("Can't buy more btb than I have btd", async () => {
			var price = oneTenth;

			await oracle.setPrice(price);
			await dollar.mint(owner.address, one);
			await dollar.mint(user2.address, one);

			await treasury.setContractionIndex(0);
			await treasury.setMaxSupplyContractionPercent(10000); // 100% percent
			await treasury.setMaxDebtRatioPercent(10000); // 100% percent

			await treasury.allocateSeigniorage();

			await dollar.approve(treasury.address, one.add(one));
			await expect(treasury.buyBonds(one.add(one))).to.be.revertedWith(
				'Not enough BTD to buy bond'
			);
		});

		it('Can redeem when above $1.01 and BTD allocated', async () => {
			await pulse.mint(owner.address, one);
			await dollar.mint(treasury.address, one);
			await oracle.setPrice(onePointTen);

			await pulse.approve(treasury.address, one);
			await treasury.smodify.put({
				seigniorageSaved: one.toString(),
			});

			await treasury.redeemBonds(one);

			var btdBalance = await dollar.balanceOf(owner.address);
			var btbBalance = await pulse.balanceOf(owner.address);

			assert.equal(btbBalance.toString(), zero);
			assert.equal(btdBalance.toString(), one);
		});

		it("Can't redeem when above $1.01 and BTD not allocated", async () => {
			await pulse.mint(owner.address, one);
			await dollar.mint(treasury.address, one);
			await oracle.setPrice(onePointTen);

			await pulse.approve(treasury.address, one);

			var redeemBonds = treasury.redeemBonds(one);

			expect(redeemBonds).eventually.to.rejectedWith(
				Error,
				"VM Exception while processing transaction: reverted with reason string 'Treasury hasn't saved any dollar'"
			);
		});

		it("Can't redeem when above $1.01 and treasury has no BTD", async () => {
			await pulse.mint(owner.address, one);

			await oracle.setPrice(onePointTen);

			await pulse.approve(treasury.address, one);
			await treasury.smodify.put({
				seigniorageSaved: one.toString(),
			});
			var redeemBonds = treasury.redeemBonds(one);

			expect(redeemBonds).eventually.to.rejectedWith(
				Error,
				"VM Exception while processing transaction: reverted with reason string 'Treasury has no more budget'"
			);
		});

		it("Can't redeem when equal $1.01 and BTD allocated", async () => {
			await pulse.mint(owner.address, one);
			await dollar.mint(treasury.address, one);
			await oracle.setPrice(dollarPriceCeiling);

			await pulse.approve(treasury.address, one);
			await treasury.smodify.put({
				seigniorageSaved: one.toString(),
			});

			var redeemBonds = treasury.redeemBonds(one);

			expect(redeemBonds).eventually.to.rejectedWith(
				Error,
				"VM Exception while processing transaction: reverted with reason string 'DollarPrice not eligible for bond purchase'"
			);
		});

		it("Can't redeem when below $1.01 and BTD allocated", async () => {
			await pulse.mint(owner.address, one);
			await dollar.mint(treasury.address, one);
			await oracle.setPrice(one);

			await pulse.approve(treasury.address, one);
			await treasury.smodify.put({
				seigniorageSaved: one.toString(),
			});

			var redeemBonds = treasury.redeemBonds(one);

			expect(redeemBonds).eventually.to.rejectedWith(
				Error,
				"VM Exception while processing transaction: reverted with reason string 'DollarPrice not eligible for bond purchase'"
			);
		});
	});

	describe('allocateSeigniorage', () => {
		it('allocateSeigniorage does nothing to dollar when price at $1.01; sends shares to boardroom', async function () {
			var user2Balance = oneTenth;
			await dollar.mint(user2.address, user2Balance);
			await oracle.setPrice(dollarPriceCeiling);
			await treasury.allocateSeigniorage();
			var btdBoardroomBalance = await dollar.balanceOf(boardroom.address);
			var btsBoardroomBalance = await bts.balanceOf(boardroom.address);
			var btdBalanceAfterSeig = await dollar.balanceOf(user2.address);
			const epochsUnderOne = await treasury.epochsUnderOne();

			assert.equal(
				user2Balance.toString(),
				btdBalanceAfterSeig.toString()
			);
			assert.equal(btdBoardroomBalance, 0);
			expect(btsBoardroomBalance).to.equal(one);
			expect(epochsUnderOne).to.equal(BigNumber.from(0));
		});

		it('allocateSeigniorage does nothing to dollar when price at $1.00; sends shares to boardroom', async function () {
			var user2Balance = oneTenth;
			await dollar.mint(user2.address, user2Balance);
			await oracle.setPrice(one);
			await treasury.allocateSeigniorage();
			var boardroomBalance = await dollar.balanceOf(boardroom.address);
			var btsBoardroomBalance = await bts.balanceOf(boardroom.address);
			var btdBalanceAfterSeig = await dollar.balanceOf(user2.address);
			const epochsUnderOne = await treasury.epochsUnderOne();

			assert.equal(
				user2Balance.toString(),
				btdBalanceAfterSeig.toString()
			);
			assert.equal(boardroomBalance, 0);
			expect(btsBoardroomBalance).to.equal(one);
			expect(epochsUnderOne).to.equal(BigNumber.from(0));
		});

		it('allocateSeigniorage prints over $1.01 with no debt; sends shares to boardroom', async function () {
			var user2Balance = oneTenth;
			await dollar.mint(user2.address, user2Balance);
			await oracle.setPrice(onePointTen);
			await treasury.allocateSeigniorage();
			var boardroomBalance = await dollar.balanceOf(boardroom.address);
			var btsBoardroomBalance = await bts.balanceOf(boardroom.address);
			var btdBalanceAfterSeig = await dollar.balanceOf(user2.address);
			var totalSupply = await dollar.totalSupply();
			const epochsUnderOne = await treasury.epochsUnderOne();

			assert.equal(totalSupply.toString(), '101000000000000000');
			expect(epochsUnderOne).to.equal(BigNumber.from(0));
			expect(btsBoardroomBalance).to.equal(one);
		});

		it('allocateSeigniorage prints over $1.01 and pays all debt when able; sends shares to boardroom', async function () {
			var debt = BigNumber.from('10000000000');
			var user2Balance = ten;
			await dollar.mint(user2.address, user2Balance);
			await pulse.mint(user2.address, debt);
			await oracle.setPrice(onePointTen);
			await treasury.allocateSeigniorage();
			const epochsUnderOne = await treasury.epochsUnderOne();

			var btsBoardroomBalance = await bts.balanceOf(boardroom.address);
			var boardroomBalance = await dollar.balanceOf(boardroom.address);
			var btdBalanceAfterSeig = await dollar.balanceOf(user2.address);
			var totalSupply = await dollar.totalSupply();

			var forBonds = await treasury.getReserve();

			assert.equal(debt.toString(), forBonds.toString());
			expect(epochsUnderOne).to.equal(BigNumber.from(0));
			expect(btsBoardroomBalance).to.equal(one);
		});

		it('allocateSeigniorage prints over $1.01 and pays down partial debt when able; sends shares to boardroom', async function () {
			var twap = onePointTen;
			var user2Balance = ten;

			await dollar.mint(user2.address, user2Balance);
			await pulse.mint(user2.address, oneBillion);
			await oracle.setPrice(twap);
			var expansionIndex = 2000;
			await treasury.setExpansionIndex(expansionIndex);
			var bondRepayPercent = await treasury.bondRepayPercent();

			await treasury.allocateSeigniorage();

			var boardroomBalance = await dollar.balanceOf(boardroom.address);
			var btsBoardroomBalance = await bts.balanceOf(boardroom.address);
			var btdBalanceAfterSeig = await dollar.balanceOf(user2.address);
			var totalSupply = await dollar.totalSupply();
			var forBonds = await treasury.getReserve();
			const epochsUnderOne = await treasury.epochsUnderOne();

			assert.equal(forBonds.toString(), oneHundredth.mul(2).toString());

			var printAmount = user2Balance
				.mul(twap.sub(one))
				.div(one)
				.mul(expansionIndex)
				.div(10000);

			assert.equal(
				printAmount.mul(bondRepayPercent).div(10000).toString(),
				forBonds.toString()
			);
			expect(epochsUnderOne).to.equal(BigNumber.from(0));
			expect(btsBoardroomBalance).to.equal(one);
		});

		it('allocateSeigniorage resets epochsUnderOne at $1.00', async () => {
			await treasury.smodify.put({
				epochsUnderOne: 5,
			});
			var user2Balance = oneTenth;
			await dollar.mint(user2.address, user2Balance);
			await oracle.setPrice(one);
			await treasury.allocateSeigniorage();

			const epochsUnderOne = await treasury.epochsUnderOne();

			expect(epochsUnderOne).to.equal(BigNumber.from(0));
		});

		it('allocateSeigniorage resets epochsUnderOne above $1.00', async () => {
			await treasury.smodify.put({
				epochsUnderOne: 5,
			});
			var user2Balance = oneTenth;
			await dollar.mint(user2.address, user2Balance);
			await oracle.setPrice(ethers.utils.parseEther('1.1'));
			await treasury.allocateSeigniorage();

			const epochsUnderOne = await treasury.epochsUnderOne();

			expect(epochsUnderOne).to.equal(BigNumber.from(0));
		});

		it('allocateSeigniorage increments epochsUnderOne below $1.00', async () => {
			await treasury.smodify.put({
				epochsUnderOne: 3,
			});
			var user2Balance = oneTenth;
			await dollar.mint(user2.address, user2Balance);
			await oracle.setPrice(ethers.utils.parseEther('0.99'));
			await treasury.allocateSeigniorage();

			const epochsUnderOne = await treasury.epochsUnderOne();

			expect(epochsUnderOne).to.equal(BigNumber.from(4));
		});

		it('allocateSeigniorage does not mint shares when max shares to mint is 0', async () => {
			await bts.removeMinter(treasury.address);
			var user2Balance = one;
			await dollar.mint(user2.address, user2Balance);
			await oracle.setPrice(ethers.utils.parseEther('1.02'));

			const treasuryBtsBalanceBefore = await bts.balanceOf(
				treasury.address
			);
			const boardroomBtsBalanceBefore = await bts.balanceOf(
				boardroom.address
			);

			await treasury.allocateSeigniorage();

			const treasuryBtsBalanceAfter = await bts.balanceOf(
				treasury.address
			);
			const boardroomBtsBalanceAfter = await bts.balanceOf(
				boardroom.address
			);

			const epochsUnderOne = await treasury.epochsUnderOne();

			expect(treasuryBtsBalanceAfter).to.equal(treasuryBtsBalanceBefore);
			expect(boardroomBtsBalanceAfter).to.equal(
				boardroomBtsBalanceBefore
			);
		});

		it('allocateSeigniorage does not mint shares when all shares minted', async () => {
			await bts.updateMinter(treasury.address, one.mul(101));

			await bts.smodify.put({
				_mintedAmount: {
					[treasury.address]: one.mul(101).toString(),
				},
			});

			var user2Balance = one;
			await dollar.mint(user2.address, user2Balance);
			await oracle.setPrice(ethers.utils.parseEther('1.02'));

			const treasuryBtsBalanceBefore = await bts.balanceOf(
				treasury.address
			);
			const boardroomBtsBalanceBefore = await bts.balanceOf(
				boardroom.address
			);

			await treasury.allocateSeigniorage();

			const treasuryBtsBalanceAfter = await bts.balanceOf(
				treasury.address
			);
			const boardroomBtsBalanceAfter = await bts.balanceOf(
				boardroom.address
			);

			const epochsUnderOne = await treasury.epochsUnderOne();

			expect(treasuryBtsBalanceAfter).to.equal(treasuryBtsBalanceBefore);
			expect(boardroomBtsBalanceAfter).to.equal(
				boardroomBtsBalanceBefore
			);
		});

		context('when below $1.00', () => {
			var user2Balance, price, contractionIndex, epochPeriod;
			beforeEach(async () => {
				user2Balance = one;
				price = ethers.utils.parseEther('0.95');
				await dollar.mint(user2.address, user2Balance);
				await oracle.setPrice(price);
				contractionIndex = await treasury.contractionIndex();
				epochPeriod = (await treasury.PERIOD()).toNumber();
			});
			context('when price is below rebaseCeiling', () => {
				beforeEach(async () => {
					await treasury.setTriggerRebasePriceCeiling(
						ethers.utils.parseEther('0.99')
					);
				});
				context('when triggerRebaseNumEpochFloor is 0', () => {
					beforeEach(async () => {
						await treasury.setTriggerRebaseNumEpochFloor(0);
						await treasury.allocateSeigniorage();
					});

					it('should rebase', async () => {
						const supplyDelta = user2Balance
							.sub(price)
							.mul(contractionIndex)
							.div(10000);
						const btdBalanceAfterSeig = await dollar.balanceOf(
							user2.address
						);
						expect(user2Balance.sub(supplyDelta)).to.equal(
							btdBalanceAfterSeig
						);
					});

					it('boardroom balance should not increase', async () => {
						const boardroomBalance = await dollar.balanceOf(
							boardroom.address
						);
						expect(boardroomBalance).to.equal(BigNumber.from('0'));
					});

					it('boardroom shares should be funded', async () => {
						const boardroomBalance = await bts.balanceOf(
							boardroom.address
						);
						expect(boardroomBalance).to.equal(one);
					});

					it('epochsUnderOne should be 1', async () => {
						const epochsUnderOne = await treasury.epochsUnderOne();
						expect(epochsUnderOne).to.equal(BigNumber.from(1));
					});
				});

				context('when triggerRebaseNumEpochFloor is 1', () => {
					beforeEach(async () => {
						await treasury.setTriggerRebaseNumEpochFloor(1);
						await treasury.allocateSeigniorage();
					});

					it('should rebase', async () => {
						const supplyDelta = user2Balance
							.sub(price)
							.mul(contractionIndex)
							.div(10000);
						const btdBalanceAfterSeig = await dollar.balanceOf(
							user2.address
						);
						expect(user2Balance.sub(supplyDelta)).to.equal(
							btdBalanceAfterSeig
						);
					});

					it('boardroom balance should not increase', async () => {
						const boardroomBalance = await dollar.balanceOf(
							boardroom.address
						);
						expect(boardroomBalance).to.equal(BigNumber.from('0'));
					});

					it('boardroom shares should be funded', async () => {
						const boardroomBalance = await bts.balanceOf(
							boardroom.address
						);
						expect(boardroomBalance).to.equal(one);
					});

					it('epochsUnderOne should be 1', async () => {
						const epochsUnderOne = await treasury.epochsUnderOne();
						expect(epochsUnderOne).to.equal(BigNumber.from(1));
					});
				});

				context('when triggerRebaseNumEpochFloor is 2', () => {
					beforeEach(async () => {
						await treasury.setTriggerRebaseNumEpochFloor(2);
						await treasury.allocateSeigniorage();
					});

					it('should rebase', async () => {
						const supplyDelta = user2Balance
							.sub(price)
							.mul(contractionIndex)
							.div(10000);
						const btdBalanceAfterSeig = await dollar.balanceOf(
							user2.address
						);
						expect(user2Balance.sub(supplyDelta)).to.equal(
							btdBalanceAfterSeig
						);
					});

					it('boardroom balance should not increase', async () => {
						const boardroomBalance = await dollar.balanceOf(
							boardroom.address
						);
						expect(boardroomBalance).to.equal(BigNumber.from('0'));
					});

					it('boardroom shares should be funded', async () => {
						const boardroomBalance = await bts.balanceOf(
							boardroom.address
						);
						expect(boardroomBalance).to.equal(one);
					});

					it('epochsUnderOne should be 1', async () => {
						const epochsUnderOne = await treasury.epochsUnderOne();
						expect(epochsUnderOne).to.equal(BigNumber.from(1));
					});
				});

				context('when triggerRebaseNumEpochFloor is 3', () => {
					beforeEach(async () => {
						await treasury.setTriggerRebaseNumEpochFloor(3);
						await treasury.allocateSeigniorage();
					});

					it('should rebase', async () => {
						const supplyDelta = user2Balance
							.sub(price)
							.mul(contractionIndex)
							.div(10000);
						const btdBalanceAfterSeig = await dollar.balanceOf(
							user2.address
						);
						expect(user2Balance.sub(supplyDelta)).to.equal(
							btdBalanceAfterSeig
						);
					});

					it('boardroom balance should not increase', async () => {
						const boardroomBalance = await dollar.balanceOf(
							boardroom.address
						);
						expect(boardroomBalance).to.equal(BigNumber.from('0'));
					});

					it('boardroom shares should be funded', async () => {
						const boardroomBalance = await bts.balanceOf(
							boardroom.address
						);
						expect(boardroomBalance).to.equal(one);
					});

					it('epochsUnderOne should be 1', async () => {
						const epochsUnderOne = await treasury.epochsUnderOne();
						expect(epochsUnderOne).to.equal(BigNumber.from(1));
					});
				});
			});

			context('when price is above rebaseCeiling', () => {
				beforeEach(async () => {
					await treasury.setTriggerRebasePriceCeiling(
						ethers.utils.parseEther('0.90')
					);
				});
				context('when triggerRebaseNumEpochFloor is 0', () => {
					beforeEach(async () => {
						await treasury.setTriggerRebaseNumEpochFloor(0);
						await treasury.allocateSeigniorage();
					});

					it('should rebase', async () => {
						const supplyDelta = user2Balance
							.sub(price)
							.mul(contractionIndex)
							.div(10000);
						const btdBalanceAfterSeig = await dollar.balanceOf(
							user2.address
						);
						expect(user2Balance.sub(supplyDelta)).to.equal(
							btdBalanceAfterSeig
						);
					});

					it('boardroom balance should not increase', async () => {
						const boardroomBalance = await dollar.balanceOf(
							boardroom.address
						);
						expect(boardroomBalance).to.equal(BigNumber.from('0'));
					});

					it('boardroom shares should be funded', async () => {
						const boardroomBalance = await bts.balanceOf(
							boardroom.address
						);
						expect(boardroomBalance).to.equal(one);
					});

					it('epochsUnderOne should be 1', async () => {
						const epochsUnderOne = await treasury.epochsUnderOne();
						expect(epochsUnderOne).to.equal(BigNumber.from(1));
					});
				});

				context('when triggerRebaseNumEpochFloor is 1', () => {
					beforeEach(async () => {
						await treasury.setTriggerRebaseNumEpochFloor(1);
						await treasury.allocateSeigniorage();
					});

					context('epoch 1', () => {
						it('should not rebase', async () => {
							const btdBalanceAfterSeig = await dollar.balanceOf(
								user2.address
							);
							expect(user2Balance).to.equal(btdBalanceAfterSeig);
						});

						it('boardroom balance should not increase', async () => {
							const boardroomBalance = await dollar.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								BigNumber.from('0')
							);
						});

						it('boardroom shares should be funded', async () => {
							const boardroomBalance = await bts.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(one);
						});

						it('epochsUnderOne should be 1', async () => {
							const epochsUnderOne =
								await treasury.epochsUnderOne();
							expect(epochsUnderOne).to.equal(BigNumber.from(1));
						});
					});

					context('epoch 2', () => {
						var boardroomBtsBefore;
						beforeEach(async () => {
							await network.provider.send('evm_increaseTime', [
								epochPeriod,
							]);
							await network.provider.send('evm_mine');
							boardroomBtsBefore = await bts.balanceOf(
								boardroom.address
							);
							await treasury.allocateSeigniorage();
						});

						it('should rebase', async () => {
							const supplyDelta = user2Balance
								.sub(price)
								.mul(contractionIndex)
								.div(10000);
							const btdBalanceAfterSeig = await dollar.balanceOf(
								user2.address
							);
							expect(user2Balance.sub(supplyDelta)).to.equal(
								btdBalanceAfterSeig
							);
						});

						it('boardroom balance should not increase', async () => {
							const boardroomBalance = await dollar.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								BigNumber.from('0')
							);
						});

						it('boardroom shares should be funded', async () => {
							const boardroomBalance = await bts.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								boardroomBtsBefore.add(one)
							);
						});

						it('epochsUnderOne should be 2', async () => {
							const epochsUnderOne =
								await treasury.epochsUnderOne();
							expect(epochsUnderOne).to.equal(BigNumber.from(2));
						});
					});

					context('epoch 3', () => {
						var boardroomBtsBefore;
						beforeEach(async () => {
							await network.provider.send('evm_increaseTime', [
								epochPeriod,
							]);
							await network.provider.send('evm_mine');
							await treasury.allocateSeigniorage();

							user2Balance = await dollar.balanceOf(
								user2.address
							);
							await network.provider.send('evm_increaseTime', [
								epochPeriod,
							]);
							await network.provider.send('evm_mine');
							boardroomBtsBefore = await bts.balanceOf(
								boardroom.address
							);
							await treasury.allocateSeigniorage();
						});

						it('should rebase', async () => {
							const supplyDelta = user2Balance
								.mul(one.sub(price))
								.div(one)
								.mul(contractionIndex)
								.div(10000);
							const btdBalanceAfterSeig = await dollar.balanceOf(
								user2.address
							);

							expect(user2Balance.sub(supplyDelta)).to.equal(
								btdBalanceAfterSeig
							);
						});

						it('boardroom balance should not increase', async () => {
							const boardroomBalance = await dollar.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								BigNumber.from('0')
							);
						});

						it('boardroom shares should be funded', async () => {
							const boardroomBalance = await bts.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								boardroomBtsBefore.add(one)
							);
						});

						it('epochsUnderOne should be 3', async () => {
							const epochsUnderOne =
								await treasury.epochsUnderOne();
							expect(epochsUnderOne).to.equal(BigNumber.from(3));
						});
					});
				});

				context('when triggerRebaseNumEpochFloor is 2', () => {
					beforeEach(async () => {
						await treasury.setTriggerRebaseNumEpochFloor(2);
						await treasury.allocateSeigniorage();
					});

					context('epoch 1', () => {
						it('should not rebase', async () => {
							const btdBalanceAfterSeig = await dollar.balanceOf(
								user2.address
							);
							expect(user2Balance).to.equal(btdBalanceAfterSeig);
						});

						it('boardroom balance should not increase', async () => {
							const boardroomBalance = await dollar.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								BigNumber.from('0')
							);
						});

						it('boardroom shares should be funded', async () => {
							const boardroomBalance = await bts.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(one);
						});

						it('epochsUnderOne should be 1', async () => {
							const epochsUnderOne =
								await treasury.epochsUnderOne();
							expect(epochsUnderOne).to.equal(BigNumber.from(1));
						});
					});

					context('epoch 2', () => {
						var boardroomBtsBefore;
						beforeEach(async () => {
							await network.provider.send('evm_increaseTime', [
								epochPeriod,
							]);
							await network.provider.send('evm_mine');
							boardroomBtsBefore = await bts.balanceOf(
								boardroom.address
							);
							await treasury.allocateSeigniorage();
						});

						it('should not rebase', async () => {
							const btdBalanceAfterSeig = await dollar.balanceOf(
								user2.address
							);
							expect(user2Balance).to.equal(btdBalanceAfterSeig);
						});

						it('boardroom balance should not increase', async () => {
							const boardroomBalance = await dollar.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								BigNumber.from('0')
							);
						});

						it('boardroom shares should be funded', async () => {
							const boardroomBalance = await bts.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								boardroomBtsBefore.add(one)
							);
						});

						it('epochsUnderOne should be 2', async () => {
							const epochsUnderOne =
								await treasury.epochsUnderOne();
							expect(epochsUnderOne).to.equal(BigNumber.from(2));
						});
					});

					context('epoch 3', () => {
						var boardroomBtsBefore;
						beforeEach(async () => {
							await network.provider.send('evm_increaseTime', [
								epochPeriod,
							]);
							await network.provider.send('evm_mine');
							await treasury.allocateSeigniorage();

							user2Balance = await dollar.balanceOf(
								user2.address
							);
							await network.provider.send('evm_increaseTime', [
								epochPeriod,
							]);
							await network.provider.send('evm_mine');
							boardroomBtsBefore = await bts.balanceOf(
								boardroom.address
							);
							await treasury.allocateSeigniorage();
						});

						it('should rebase', async () => {
							const supplyDelta = user2Balance
								.mul(one.sub(price))
								.div(one)
								.mul(contractionIndex)
								.div(10000);
							const btdBalanceAfterSeig = await dollar.balanceOf(
								user2.address
							);

							expect(user2Balance.sub(supplyDelta)).to.equal(
								btdBalanceAfterSeig
							);
						});

						it('boardroom balance should not increase', async () => {
							const boardroomBalance = await dollar.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								BigNumber.from('0')
							);
						});

						it('boardroom shares should be funded', async () => {
							const boardroomBalance = await bts.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								boardroomBtsBefore.add(one)
							);
						});

						it('epochsUnderOne should be 3', async () => {
							const epochsUnderOne =
								await treasury.epochsUnderOne();
							expect(epochsUnderOne).to.equal(BigNumber.from(3));
						});
					});

					context('epoch 4', () => {
						var boardroomBtsBefore;
						beforeEach(async () => {
							await network.provider.send('evm_increaseTime', [
								epochPeriod,
							]);
							await network.provider.send('evm_mine');
							await treasury.allocateSeigniorage();

							await network.provider.send('evm_increaseTime', [
								epochPeriod,
							]);
							await network.provider.send('evm_mine');
							await treasury.allocateSeigniorage();

							user2Balance = await dollar.balanceOf(
								user2.address
							);
							await network.provider.send('evm_increaseTime', [
								epochPeriod,
							]);
							await network.provider.send('evm_mine');
							boardroomBtsBefore = await bts.balanceOf(
								boardroom.address
							);
							await treasury.allocateSeigniorage();
						});

						it('should rebase', async () => {
							const supplyDelta = user2Balance
								.mul(one.sub(price))
								.div(one)
								.mul(contractionIndex)
								.div(10000);
							const btdBalanceAfterSeig = await dollar.balanceOf(
								user2.address
							);

							expect(user2Balance.sub(supplyDelta)).to.equal(
								btdBalanceAfterSeig
							);
						});

						it('boardroom balance should not increase', async () => {
							const boardroomBalance = await dollar.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								BigNumber.from('0')
							);
						});

						it('boardroom shares should be funded', async () => {
							const boardroomBalance = await bts.balanceOf(
								boardroom.address
							);
							expect(boardroomBalance).to.equal(
								boardroomBtsBefore.add(one)
							);
						});

						it('epochsUnderOne should be 4', async () => {
							const epochsUnderOne =
								await treasury.epochsUnderOne();
							expect(epochsUnderOne).to.equal(BigNumber.from(4));
						});
					});
				});
			});
		});
	});
});
