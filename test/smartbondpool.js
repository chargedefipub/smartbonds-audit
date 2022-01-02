const { ethers } = require('hardhat');
const { expect, assert } = require('chai');
const { smockit } = require('@eth-optimism/smock');
const { BigNumber } = require('@ethersproject/bignumber');

const one = ethers.utils.parseEther('1');
const oneHundred = ethers.utils.parseEther('100');
const fifty = ethers.utils.parseEther('50');
const twentyFive = ethers.utils.parseEther('25');
const seventyFive = ethers.utils.parseEther('75');
const zero = BigNumber.from('0');
const deltaClose = ethers.utils.parseEther('0.0000000005');

describe('smartbondpool', function () {
	let pulse;
	let bondpool;
	let busd;
	let dollar;
	let router;
	let strategy;

	beforeEach(async () => {
		[owner, user2] = await ethers.getSigners();

		const pulseFactory = await ethers.getContractFactory('Pulse');
		pulse = await pulseFactory.deploy();

		const dollarFactory = await ethers.getContractFactory('Static');
		dollar = await dollarFactory.deploy('Static', 'Static');

		const busdFactory = await ethers.getContractFactory('BUSD');
		busd = await busdFactory.deploy('BUSD', 'BUSD');

		const pcsRouterFactory = await ethers.getContractFactory(
			'PancakeRouter'
		);
		router = await (
			await pcsRouterFactory.deploy(busd.address, busd.address)
		).deployed();

		const boltMasterFactory = await ethers.getContractFactory(
			'SmartBondPool'
		);
		bondpool = await boltMasterFactory.deploy(
			pulse.address,
			busd.address,
			dollar.address,
			router.address
		);

		await bondpool.grantRole(
			await bondpool.strategiestRole(),
			owner.address
		);

		const strategyFactory = await ethers.getContractFactory(
			'MockSmartBondPoolStrategy'
		);
		strategy = await strategyFactory.deploy(
			busd.address,
			oneHundred,
			bondpool.address
		);
		await bondpool.addStrategy(strategy.address, [busd.address]);

		await pulse.mint(owner.address, oneHundred);
		await pulse.approve(bondpool.address, oneHundred);
	});

	it('can deposit', async () => {
		await bondpool.deposit(oneHundred);

		let userAmount = await bondpool.balanceOf(owner.address);
		let totalDeposit = await bondpool.totalBalance();

		expect(totalDeposit).to.equal(oneHundred);
		expect(userAmount).to.equal(oneHundred);
	});

	it('can withdraw', async () => {
		await bondpool.deposit(oneHundred);
		await bondpool.withdraw(oneHundred);

		let userAmounts = await bondpool.balanceOf(owner.address);
		let totalDeposit = await bondpool.totalBalance();

		expect(totalDeposit).to.equal(zero);
		expect(userAmounts).to.equal(zero);
		expect(await pulse.balanceOf(owner.address)).to.equal(oneHundred);
	});

	it('can claim reward', async () => {
		await bondpool.deposit(oneHundred);
		await bondpool.withdraw(0);
		expect(await busd.balanceOf(owner.address)).to.equal(oneHundred);
	});

	describe('After Allocate', function () {
		describe('One User', function () {
			beforeEach(async () => {
				await dollar.grantRole(
					await dollar.minterRole(),
					owner.address
				);
				await dollar.mint(owner.address, twentyFive);
				await dollar.approve(bondpool.address, twentyFive);
				await bondpool.deposit(oneHundred);

				await bondpool.allocateSeigniorage(twentyFive);
			});

			it('Transfers BTD', async () => {
				let bondPoolBTDBalance = await dollar.balanceOf(
					bondpool.address
				);

				expect(bondPoolBTDBalance).to.equal(twentyFive);
			});

			it('User Bond Balance updates', async () => {
				let bondBalance = await bondpool.balanceOf(owner.address);

				expect(bondBalance).to.equal(seventyFive);
			});

			context('withdraw 0', () => {
				beforeEach(async () => {
					await bondpool.withdraw(0);
				});

				it('bond balance reduces by dollar', async () => {
					expect(await bondpool.balanceOf(owner.address)).to.equal(
						seventyFive
					);
				});

				it('dollars redeemed', async () => {
					let btdBalance = await dollar.balanceOf(owner.address);
					expect(btdBalance).to.equal(twentyFive);
				});

				it('reward claimed', async () => {
					let busdBalance = await busd.balanceOf(owner.address);
					expect(busdBalance).to.be.closeTo(oneHundred, deltaClose);
				});
			});

			context('partial withdraw', () => {
				beforeEach(async () => {
					await bondpool.withdraw(fifty);
				});

				it('bond balance reduces by dollar plus withdraw', async () => {
					expect(await bondpool.balanceOf(owner.address)).to.equal(
						twentyFive
					);
				});

				it('user receives bonds', async () => {
					let userBondBalance = await pulse.balanceOf(owner.address);
					expect(userBondBalance).to.equal(fifty);
				});

				it('dollars redeemed', async () => {
					let btdBalance = await dollar.balanceOf(owner.address);
					expect(btdBalance).to.equal(twentyFive);
				});

				it('reward claimed', async () => {
					let busdBalance = await busd.balanceOf(owner.address);
					expect(busdBalance).to.be.closeTo(oneHundred, deltaClose);
				});
			});

			// 	it("Can't withdraw more than balance", async ()  => {
			// 		expect(true).to.equal(false);
			// 	});

			// 	it("Bonds burn", async ()  => {
			// 		expect(true).to.equal(false);
			// 	});
		});

		describe('Two Users', function () {
			beforeEach(async () => {
				await dollar.grantRole(
					await dollar.minterRole(),
					owner.address
				);
				await dollar.mint(owner.address, seventyFive);
				await dollar.approve(bondpool.address, seventyFive);
				await bondpool.deposit(oneHundred);

				await pulse.mint(user2.address, oneHundred);
				await pulse
					.connect(user2)
					.approve(bondpool.address, oneHundred);
				await bondpool.connect(user2).deposit(oneHundred);

				await bondpool.allocateSeigniorage(fifty);
			});

			it('Users can withdraw', async () => {
				await bondpool.connect(user2).withdraw(seventyFive);
				await bondpool.withdraw(seventyFive);

				var ownerBondPoolBalance = await bondpool.balanceOf(
					owner.address
				);
				var user2BondPoolBalance = await bondpool.balanceOf(
					user2.address
				);
				var ownerBondBalance = await pulse.balanceOf(owner.address);
				var user2BondBalance = await pulse.balanceOf(user2.address);

				expect(ownerBondPoolBalance).to.equal(BigNumber.from(0));
				expect(user2BondPoolBalance).to.equal(BigNumber.from(0));
				expect(ownerBondBalance).to.equal(seventyFive);
				expect(user2BondBalance).to.equal(seventyFive);
			});

			it('Users get reward on withdraw', async () => {
				await bondpool.connect(user2).withdraw(seventyFive);
				await bondpool.withdraw(seventyFive);

				var ownerBusdBalance = await busd.balanceOf(owner.address);
				var user2BusdBalance = await busd.balanceOf(user2.address);

				expect(ownerBusdBalance).to.closeTo(
					oneHundred.add(fifty).add(oneHundred),
					deltaClose
				);
				expect(user2BusdBalance).to.closeTo(fifty, deltaClose);
			});

			it('Two allocate, partial withdraw in middle', async () => {
				// both users deposited 100.
				// allocate called, 50.  Each user has 75 bonds left.
				// one user withdrew 25, leaving him with 50.
				// allocate called, 25.  Total of 125 bonds left in pool.  One user has 50/125= 40%.  Other user has 75/125 = 60%.
				// of 25 allocated, one user gets 25*0.40= 10 and the other 25*0.6 = 15.
				// One user has 40 left, other has 60, leaving total of 100 in pool

				await bondpool.withdraw(twentyFive);
				await bondpool.allocateSeigniorage(twentyFive);

				var ownerBondPoolBalance = await bondpool.balanceOf(
					owner.address
				);
				var user2BondPoolBalance = await bondpool.balanceOf(
					user2.address
				);
				var ownerBusdBalance = await busd.balanceOf(owner.address);

				expect(ownerBusdBalance).to.closeTo(
					oneHundred.add(fifty),
					deltaClose
				);
				expect(ownerBondPoolBalance).to.equal(
					ethers.utils.parseEther('40')
				);
				expect(user2BondPoolBalance).to.equal(
					ethers.utils.parseEther('60')
				);
			});
		});
	});
});
