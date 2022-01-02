const { ethers } = require('hardhat');
const { expect, assert } = require('chai');
const { intToBuffer } = require('ethjs-util');
const { BigNumber } = require('@ethersproject/bignumber');

describe('btd', function () {
	var dollar;

	const onePointTen = BigNumber.from('1100000000000000000');
	const one = BigNumber.from('1000000000000000000');
	const ten = BigNumber.from('10000000000000000000');
	const oneHundred = BigNumber.from('100000000000000000000');
	const oneTenth = BigNumber.from('100000000000000000');
	const oneHundredth = BigNumber.from('10000000000000000');
	const zero = BigNumber.from('0');

	beforeEach(async () => {
		[owner, user2, user3, excluder] = await ethers.getSigners();

		const dollarFactory = await ethers.getContractFactory('Static');
		dollar = await dollarFactory.deploy('Static', 'Static');

		await dollar.grantRole(await dollar.rebaserRole(), owner.address);
		await dollar.grantRole(await dollar.minterRole(), owner.address);
		await dollar.grantRole(await dollar.rebaserRole(), user2.address);
		await dollar.grantRole(await dollar.minterRole(), user2.address);
		await dollar.grantRole(await dollar.excluderRole(), excluder.address);
	});

	it('0 inital balance', async function () {
		var amountToAdd = BigNumber.from('1000000000000000000');
		var totalSuppy = await dollar.totalSupply();
		assert.equal(totalSuppy.toString(), BigNumber.from(0).toString());
	});

	it('total balance increases with one mint', async function () {
		var amountToAdd = BigNumber.from('1000000000000000000');

		await dollar.mint(user2.address, amountToAdd);
		var totalSupply = await dollar.totalSupply();
		assert.equal(totalSupply.toString(), amountToAdd.toString());
	});

	it('total balance increases with two mints', async function () {
		var amountToAdd = BigNumber.from('1000000000000000000');

		await dollar.mint(user2.address, amountToAdd);
		await dollar.mint(owner.address, amountToAdd);
		var totalSupply = await dollar.totalSupply();
		assert.equal(totalSupply.toString(), amountToAdd.mul(2).toString());
	});

	it('User balance correct after mint', async function () {
		var amountToAdd = BigNumber.from(one);

		await dollar.mint(user2.address, amountToAdd);

		var userBalance = await dollar.balanceOf(user2.address);

		assert.equal(userBalance.toString(), amountToAdd.toString());
	});

	it('User balance correct after two mints', async function () {
		var amountToAdd = BigNumber.from('1000000090000000003');

		await dollar.mint(user2.address, amountToAdd);
		await dollar.mint(owner.address, amountToAdd);

		var userBalance = await dollar.balanceOf(user2.address);
		var ownerBalance = await dollar.balanceOf(owner.address);

		assert.equal(userBalance.toString(), amountToAdd.toString());
		assert.equal(ownerBalance.toString(), amountToAdd.toString());
	});

	it('User balance correct after rebase down one user', async function () {
		var amountToAdd = BigNumber.from('1000000000000000000');

		await dollar.mint(user2.address, amountToAdd);

		await dollar.rebase(1, amountToAdd.div(5).mul(-1));

		var userBalance = await dollar.balanceOf(user2.address);
		assert.equal(
			userBalance.toString(),
			amountToAdd.sub(amountToAdd.div(5))
		);
	});

	it('User balance correct after rebase down two users', async function () {
		var amountToAdd = BigNumber.from('1000000000000000000');

		await dollar.mint(user2.address, amountToAdd);
		await dollar.mint(owner.address, amountToAdd);

		await dollar.rebase(1, amountToAdd.div(5).mul(-1));

		var userBalance = await dollar.balanceOf(user2.address);
		var ownerBalance = await dollar.balanceOf(owner.address);
		assert.equal(
			userBalance.toString(),
			amountToAdd.sub(amountToAdd.div(10))
		);
		assert.equal(
			ownerBalance.toString(),
			amountToAdd.sub(amountToAdd.div(10))
		);
	});

	it('User balance correct after rebase down two users, then mint', async function () {
		var amountToAdd = BigNumber.from('1000000000000000000');

		await dollar.mint(user2.address, amountToAdd);
		await dollar.mint(owner.address, amountToAdd);

		await dollar.rebase(1, amountToAdd.div(5).mul(-1));

		await dollar.mint(user3.address, amountToAdd);
		var userBalance = await dollar.balanceOf(user2.address);
		var ownerBalance = await dollar.balanceOf(owner.address);
		var user3Balance = await dollar.balanceOf(user3.address);

		assert.equal(
			userBalance.toString(),
			amountToAdd.sub(amountToAdd.div(10))
		);
		assert.equal(
			ownerBalance.toString(),
			amountToAdd.sub(amountToAdd.div(10))
		);
		assert.equal(user3Balance.toString(), amountToAdd.toString());
	});

	it('User balance correct after transfer', async function () {
		var amountToAdd = BigNumber.from('1000000000000000000');

		await dollar.mint(user2.address, amountToAdd);
		await dollar.mint(owner.address, amountToAdd);

		await dollar.transfer(user2.address, amountToAdd);

		var user2Balance = await dollar.balanceOf(user2.address);
		var ownerBalance = await dollar.balanceOf(owner.address);

		assert.equal(user2Balance.toString(), amountToAdd.mul(2));
		assert.equal(ownerBalance.toString(), BigNumber.from(0));
	});

	it('User balance correct after rebase, transfer', async function () {
		var amountToAdd = BigNumber.from('1000000000000000000');

		await dollar.mint(user2.address, amountToAdd);
		await dollar.mint(owner.address, amountToAdd);

		await dollar.rebase(1, amountToAdd.div(5).mul(-1));
		await dollar.transfer(
			user2.address,
			amountToAdd.sub(amountToAdd.div(10))
		);

		var user2Balance = await dollar.balanceOf(user2.address);
		var ownerBalance = await dollar.balanceOf(owner.address);

		assert.equal(
			user2Balance.toString(),
			amountToAdd.sub(amountToAdd.div(10)).mul(2)
		);
		assert.equal(ownerBalance.toString(), BigNumber.from(0));
	});

	it('User balance correct after burnFrom', async function () {
		var amountToAdd = BigNumber.from(one);
		var ownerBalance = await dollar.balanceOf(owner.address);

		await dollar.mint(owner.address, amountToAdd);
		await dollar.approve(owner.address, amountToAdd);
		await dollar.burnFrom(owner.address, amountToAdd);

		ownerBalance = await dollar.balanceOf(owner.address);

		assert.equal(ownerBalance.toString(), zero.toString());
	});

	describe('Exclusion List', function () {
		describe('#grantRebaseExclusion()', function () {
			it('user cannot grant exclusion', async function () {
				const isExcludedBefore = await dollar.isExcluded(user3.address);

				await expect(dollar.connect(user2).grantRebaseExclusion(user3))
					.to.be.reverted;

				const isExcludedAfter = await dollar.isExcluded(user3.address);

				expect(isExcludedBefore).false;
				expect(isExcludedAfter).false;
			});

			it('excluder can grant exclusion', async function () {
				const isExcludedBefore = await dollar.isExcluded(user3.address);

				await expect(
					dollar.connect(excluder).grantRebaseExclusion(user3.address)
				).to.not.be.reverted;

				const isExcludedAfter = await dollar.isExcluded(user3.address);

				expect(isExcludedBefore).false;
				expect(isExcludedAfter).true;
			});

			it('existing account cannot be added again', async function () {
				await dollar
					.connect(excluder)
					.grantRebaseExclusion(user3.address);
				const isExcludedBefore = await dollar.isExcluded(user3.address);

				await expect(
					dollar.connect(excluder).grantRebaseExclusion(user3.address)
				).to.be.reverted;

				const isExcludedAfter = await dollar.isExcluded(user3.address);

				expect(isExcludedBefore).true;
				expect(isExcludedAfter).true;
			});
		});

		describe('#revokeRebaseExclusion()', function () {
			it('user cannot revoke exclusion', async function () {
				await dollar
					.connect(excluder)
					.grantRebaseExclusion(user3.address);

				const isExcludedBefore = await dollar.isExcluded(user3.address);

				await expect(dollar.connect(user2).revokeRebaseExclusion(user3))
					.to.be.reverted;

				const isExcludedAfter = await dollar.isExcluded(user3.address);

				expect(isExcludedBefore).true;
				expect(isExcludedAfter).true;
			});

			it('excluder can revoke exclusion', async function () {
				await dollar
					.connect(excluder)
					.grantRebaseExclusion(user3.address);

				const isExcludedBefore = await dollar.isExcluded(user3.address);

				await expect(
					dollar
						.connect(excluder)
						.revokeRebaseExclusion(user3.address)
				).to.not.be.reverted;

				const isExcludedAfter = await dollar.isExcluded(user3.address);

				expect(isExcludedBefore).true;
				expect(isExcludedAfter).false;
			});

			it('missing account cannot be revoked', async function () {
				const isExcludedBefore = await dollar.isExcluded(user3.address);

				await expect(
					dollar
						.connect(excluder)
						.revokeRebaseExclusion(user3.address)
				).to.be.reverted;

				const isExcludedAfter = await dollar.isExcluded(user3.address);

				expect(isExcludedBefore).false;
				expect(isExcludedAfter).false;
			});

			context('2 existing excluded accounts', () => {
				beforeEach(async () => {
					await dollar
						.connect(excluder)
						.grantRebaseExclusion(user3.address);
					await dollar
						.connect(excluder)
						.grantRebaseExclusion(user2.address);
				});

				it('account 1 can be revoked', async () => {
					const account1ExcludedBefore = await dollar.isExcluded(
						user3.address
					);
					const account2ExcludedBefore = await dollar.isExcluded(
						user2.address
					);
					const numExcluded = await dollar.numExcluded();

					await dollar
						.connect(excluder)
						.revokeRebaseExclusion(user3.address);

					const account1ExcludedAfter = await dollar.isExcluded(
						user3.address
					);
					const account2ExcludedAfter = await dollar.isExcluded(
						user2.address
					);
					const numExcludedAfter = await dollar.numExcluded();

					await expect(await dollar.excluded(0)).to.be.equal(
						user2.address
					);

					expect(account1ExcludedBefore).true;
					expect(account2ExcludedBefore).true;
					expect(numExcluded).equal(2);
					expect(account1ExcludedAfter).false;
					expect(account2ExcludedAfter).true;
					expect(numExcludedAfter).equal(1);
				});

				it('account 2 can be revoked', async () => {
					const account1ExcludedBefore = await dollar.isExcluded(
						user3.address
					);
					const account2ExcludedBefore = await dollar.isExcluded(
						user2.address
					);
					const numExcluded = await dollar.numExcluded();

					await dollar
						.connect(excluder)
						.revokeRebaseExclusion(user2.address);

					const account1ExcludedAfter = await dollar.isExcluded(
						user3.address
					);
					const account2ExcludedAfter = await dollar.isExcluded(
						user2.address
					);
					const numExcludedAfter = await dollar.numExcluded();

					expect(await dollar.excluded(0)).to.be.equal(user3.address);

					expect(account1ExcludedBefore).true;
					expect(account2ExcludedBefore).true;
					expect(numExcluded).equal(2);
					expect(account1ExcludedAfter).true;
					expect(account2ExcludedAfter).false;
					expect(numExcludedAfter).equal(1);
				});
			});
		});

		describe('#rebase()', function () {
			const amountToAdd = ethers.utils.parseEther('1');
			const rebaseAmount = ethers.utils.parseEther('0.2');

			context(
				'with one excluded account and no other accounts',
				function () {
					beforeEach(async () => {
						await dollar.mint(user3.address, amountToAdd);
						await dollar
							.connect(excluder)
							.grantRebaseExclusion(user3.address);
					});

					it('excluded account balance should not change', async () => {
						const balanceBefore = await dollar.balanceOf(
							user3.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user3.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(balanceBefore);
					});

					it('total supply should not change', async () => {
						const totalSupplyBefore = await dollar.totalSupply();

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const totalSupplyAfter = await dollar.totalSupply();

						expect(totalSupplyBefore).to.equal(amountToAdd);
						expect(totalSupplyAfter).to.equal(totalSupplyBefore);
					});

					it('rebase supply should not change', async () => {
						const rebaseSupplyBefore = await dollar.rebaseSupply();

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const rebaseSupplyAfter = await dollar.rebaseSupply();

						expect(rebaseSupplyBefore).to.equal(BigNumber.from(0));
						expect(rebaseSupplyAfter).to.equal(rebaseSupplyBefore);
					});
				}
			);

			context(
				'with two excluded account and no other accounts',
				function () {
					beforeEach(async () => {
						await dollar.mint(user3.address, amountToAdd);
						await dollar.mint(excluder.address, amountToAdd);
						await dollar
							.connect(excluder)
							.grantRebaseExclusion(user3.address);
						await dollar
							.connect(excluder)
							.grantRebaseExclusion(excluder.address);
					});

					it('excluded account balance 1 should not change', async () => {
						const balanceBefore = await dollar.balanceOf(
							user3.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user3.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(balanceBefore);
					});

					it('excluded account balance 2 should not change', async () => {
						const balanceBefore = await dollar.balanceOf(
							user3.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user3.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(balanceBefore);
					});

					it('total supply should not change', async () => {
						const totalSupplyBefore = await dollar.totalSupply();

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const totalSupplyAfter = await dollar.totalSupply();

						expect(totalSupplyBefore).to.equal(amountToAdd.mul(2));
						expect(totalSupplyAfter).to.equal(totalSupplyBefore);
					});

					it('rebase supply should not change', async () => {
						const rebaseSupplyBefore = await dollar.rebaseSupply();

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const rebaseSupplyAfter = await dollar.rebaseSupply();

						expect(rebaseSupplyBefore).to.equal(BigNumber.from(0));
						expect(rebaseSupplyAfter).to.equal(rebaseSupplyBefore);
					});
				}
			);

			context(
				'with one excluded account and one normal account',
				function () {
					beforeEach(async () => {
						await dollar.mint(user2.address, amountToAdd);
						await dollar.mint(user3.address, amountToAdd);
						await dollar
							.connect(excluder)
							.grantRebaseExclusion(user3.address);
					});

					it('excluded account balance should not change', async () => {
						const balanceBefore = await dollar.balanceOf(
							user3.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user3.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(balanceBefore);
					});

					it('normal account balance should reduce by rebase amount', async () => {
						const balanceBefore = await dollar.balanceOf(
							user2.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user2.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(
							balanceBefore.sub(rebaseAmount)
						);
					});

					it('total supply should reduce by rebase amount', async () => {
						const totalSupplyBefore = await dollar.totalSupply();

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const totalSupplyAfter = await dollar.totalSupply();

						expect(totalSupplyBefore).to.equal(amountToAdd.mul(2));
						expect(totalSupplyAfter).to.equal(
							totalSupplyBefore.sub(rebaseAmount)
						);
					});

					it('rebase supply should reduce by rebase amount', async () => {
						const rebaseSupplyBefore = await dollar.rebaseSupply();

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const rebaseSupplyAfter = await dollar.rebaseSupply();

						expect(rebaseSupplyBefore).to.equal(amountToAdd);
						expect(rebaseSupplyAfter).to.equal(
							rebaseSupplyBefore.sub(rebaseAmount)
						);
					});
				}
			);

			context(
				'with one excluded account and two normal account',
				function () {
					beforeEach(async () => {
						await dollar.mint(user2.address, amountToAdd);
						await dollar.mint(owner.address, amountToAdd);
						await dollar.mint(user3.address, amountToAdd);
						await dollar
							.connect(excluder)
							.grantRebaseExclusion(user3.address);
					});

					it('excluded account balance should not change', async () => {
						const balanceBefore = await dollar.balanceOf(
							user3.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user3.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(balanceBefore);
					});

					it('normal account 1 balance should reduce by half rebase amount', async () => {
						const balanceBefore = await dollar.balanceOf(
							user2.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user2.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(
							balanceBefore.sub(rebaseAmount.div(2))
						);
					});

					it('normal account 2 balance should reduce by half rebase amount', async () => {
						const balanceBefore = await dollar.balanceOf(
							user2.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user2.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(
							balanceBefore.sub(rebaseAmount.div(2))
						);
					});

					it('total supply should reduce by rebase amount', async () => {
						const totalSupplyBefore = await dollar.totalSupply();

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const totalSupplyAfter = await dollar.totalSupply();

						expect(totalSupplyBefore).to.equal(amountToAdd.mul(3));
						expect(totalSupplyAfter).to.equal(
							totalSupplyBefore.sub(rebaseAmount)
						);
					});

					it('rebase supply should reduce by rebase amount', async () => {
						const rebaseSupplyBefore = await dollar.rebaseSupply();

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const rebaseSupplyAfter = await dollar.rebaseSupply();

						expect(rebaseSupplyBefore).to.equal(amountToAdd.mul(2));
						expect(rebaseSupplyAfter).to.equal(
							rebaseSupplyBefore.sub(rebaseAmount)
						);
					});
				}
			);

			context(
				'with two excluded account and two normal account',
				function () {
					beforeEach(async () => {
						await dollar.mint(user2.address, amountToAdd);
						await dollar.mint(owner.address, amountToAdd);
						await dollar.mint(user3.address, amountToAdd);
						await dollar.mint(excluder.address, amountToAdd);
						await dollar
							.connect(excluder)
							.grantRebaseExclusion(user3.address);
						await dollar
							.connect(excluder)
							.grantRebaseExclusion(excluder.address);
					});

					it('excluded account 1 balance should not change', async () => {
						const balanceBefore = await dollar.balanceOf(
							user3.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user3.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(balanceBefore);
					});

					it('excluded account 2 balance should not change', async () => {
						const balanceBefore = await dollar.balanceOf(
							excluder.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user3.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(balanceBefore);
					});

					it('normal account 1 balance should reduce by half rebase amount', async () => {
						const balanceBefore = await dollar.balanceOf(
							user2.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user2.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(
							balanceBefore.sub(rebaseAmount.div(2))
						);
					});

					it('normal account 2 balance should reduce by half rebase amount', async () => {
						const balanceBefore = await dollar.balanceOf(
							user2.address
						);

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const balanceAfter = await dollar.balanceOf(
							user2.address
						);

						expect(balanceBefore).to.equal(amountToAdd);
						expect(balanceAfter).to.equal(
							balanceBefore.sub(rebaseAmount.div(2))
						);
					});

					it('total supply should reduce by rebase amount', async () => {
						const totalSupplyBefore = await dollar.totalSupply();

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const totalSupplyAfter = await dollar.totalSupply();

						expect(totalSupplyBefore).to.equal(amountToAdd.mul(4));
						expect(totalSupplyAfter).to.equal(
							totalSupplyBefore.sub(rebaseAmount)
						);
					});

					it('rebase supply should reduce by rebase amount', async () => {
						const rebaseSupplyBefore = await dollar.rebaseSupply();

						await dollar.rebase(1, rebaseAmount.mul(-1));

						const rebaseSupplyAfter = await dollar.rebaseSupply();

						expect(rebaseSupplyBefore).to.equal(amountToAdd.mul(2));
						expect(rebaseSupplyAfter).to.equal(
							rebaseSupplyBefore.sub(rebaseAmount)
						);
					});
				}
			);
		});
	});
});
