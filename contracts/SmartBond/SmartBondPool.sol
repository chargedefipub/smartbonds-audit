// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '../Interfaces/ISmartBondPool.sol';
import 'hardhat/console.sol';
import '../Interfaces/IBasisAsset.sol';
import './StrategyManager.sol';
import './BalanceRebaser.sol';

contract SmartBondPool is
	BalanceRebaser,
	StrategyManager,
	Pausable,
	ReentrancyGuard,
	ISmartBondPool
{
	using SafeMath for uint256;
	using SafeERC20 for IERC20;
	using SafeERC20 for IERC20Metadata;
	using SafeERC20 for IBasisAsset;

	// Accrued token per share (bond token)
	uint256 public accTokenPerShare;

	// The precision factor
	uint256 public PRECISION_FACTOR;

	// The staked token
	IBasisAsset public bondToken;

	// The token bonds are redeemed for
	IERC20Metadata public dollarToken;

	// Info of each user that stakes tokens (bondToken)
	mapping(address => UserInfo) internal userInfo;

	struct UserInfo {
		uint256 deposit; // How many staked tokens the user has provided
		uint256 rewardDebt; // Reward debt
	}

	event Deposit(address indexed user, uint256 amount);
	event Withdraw(address indexed user, uint256 amount);
	event EmergencyWithdraw(address indexed user, uint256 amount);

	constructor(
		IBasisAsset _bondToken,
		IERC20Metadata _rewardToken,
		IERC20Metadata _dollarToken,
		IPancakeRouter02 _router
	) StrategyManager(_rewardToken, _router) {
		bondToken = _bondToken;
		dollarToken = _dollarToken;

		uint256 decimalsRewardToken = uint256(_rewardToken.decimals());
		require(decimalsRewardToken < 30, 'Must be inferior to 30');

		PRECISION_FACTOR = uint256(10**(uint256(30).sub(decimalsRewardToken)));
	}

	function allocateSeigniorage(uint256 amount_) external override {
		require(amount_ > 0, "amount can't be zero");
		require(totalBalance() > 0, 'No money deposited');
		require(totalBalance() > amount_, 'Too many dollars for bonds');

		// we treat allocateSeigniorage as a global bond conversion in the pool
		// all user bond balances get decreased proportionately via a rebase mechanic
		// dollars to be redeemed for a user is tracked by the difference between between user.deposit and bond balance
		// the next user mutation automatically redeems these dollars and sets user.deposit to current bond balance
		uint256 oldBondSupply = totalBalance();
		uint256 newBondSupply = _reduceTotalBalance(amount_);

		// we have reduced bond supply, but we need to ensure unclaimed rewards is not affected
		// Total Unclaimed Rewards before rebase = oldBondSupply * accTokenPerShare - totalUserDebt (ignore precision)
		// Total Unclaimed Rewards after rebase = newBondSupply * accTokenPerShare - totalUserDebt
		// totalUserDebt can't be adjusted as its essentially a summation of the debt at each users last mutation (accTokenPerShare can be different for each user debt),
		// the only thing we can adjust is the current accTokenPerShare
		// this is straightforward to calculate, since totalUserDebt is a constant
		// and Total Unclaimed Rewards before and after rebase should be the same
		accTokenPerShare = accTokenPerShare.mul(oldBondSupply).div(
			newBondSupply
		);

		dollarToken.safeTransferFrom(msg.sender, address(this), amount_);
		bondToken.burn(amount_);
	}

	/*
	 * @notice Deposit bond tokens and collect dollar and reward tokens (if any)
	 * @param _amount: amount to deposit (in bondToken)
	 */
	function deposit(uint256 _amount) external nonReentrant {
		UserInfo storage user = userInfo[msg.sender];

		_updatePool();
		_redeem(msg.sender);

		if (_amount > 0) {
			// keeps track of initial deposit, not affected by allocateSeigniorage
			user.deposit = user.deposit.add(_amount);
			// keeps track of actual bond amount, rebases during allocateSeigniorage
			_increaseBalance(msg.sender, _amount);
			bondToken.safeTransferFrom(
				address(msg.sender),
				address(this),
				_amount
			);
		}

		user.rewardDebt = balanceOf(msg.sender).mul(accTokenPerShare).div(
			PRECISION_FACTOR
		);

		emit Deposit(msg.sender, _amount);
	}

	/*
	 * @notice Withdraw bonds tokens and collect dollar and reward tokens
	 * @param _amount: amount to withdraw (in bondToken)
	 */
	function withdraw(uint256 _amount) external nonReentrant {
		require(
			balanceOf(msg.sender) >= _amount,
			'Amount to withdraw too high'
		);

		UserInfo storage user = userInfo[msg.sender];

		_updatePool();
		_redeem(msg.sender);

		if (_amount > 0) {
			user.deposit = user.deposit.sub(_amount);
			_reduceBalance(msg.sender, _amount);
			bondToken.safeTransfer(address(msg.sender), _amount);
		}

		user.rewardDebt = balanceOf(msg.sender).mul(accTokenPerShare).div(
			PRECISION_FACTOR
		);

		emit Withdraw(msg.sender, _amount);
	}

	/*
	 * @notice Withdraw bond tokens without caring about rewards
	 * @dev Needs to be for emergency.
	 */
	function emergencyWithdraw() external nonReentrant {
		UserInfo storage user = userInfo[msg.sender];
		uint256 userBondBalance = balanceOf(msg.sender);

		// redeem dollars
		if (user.deposit > userBondBalance) {
			uint256 pendingDollars = user.deposit.sub(userBondBalance);
			dollarToken.safeTransfer(msg.sender, pendingDollars);
		}

		uint256 amountToTransfer = balanceOf(msg.sender);
		user.deposit = 0;
		user.rewardDebt = 0;
		_reduceBalance(msg.sender, amountToTransfer);

		if (amountToTransfer > 0) {
			bondToken.safeTransfer(address(msg.sender), amountToTransfer);
		}

		emit EmergencyWithdraw(msg.sender, user.deposit);
	}

	/*
	 * @notice View function to see pending dollars on frontend.
	 * @param _user: user address
	 * @return Pending dollar for a given user
	 */
	function pendingDollar(address _user) external view returns (uint256) {
		return userInfo[_user].deposit.sub(balanceOf(_user));
	}

	/*
	 * @notice View function to see pending reward on frontend.
	 * @param _user: user address
	 * @return Pending reward for a given user
	 */
	function pendingReward(address _user) external view returns (uint256) {
		UserInfo storage user = userInfo[_user];

		uint256 stakedTokenSupply = totalBalance();
		if (stakedTokenSupply == 0) return 0;
		uint256 userBondBalance = balanceOf(_user);
		uint256 reward = _unharvestedRewards();
		uint256 adjustedTokenPerShare = accTokenPerShare.add(
			reward.mul(PRECISION_FACTOR).div(stakedTokenSupply)
		);
		return
			userBondBalance
				.mul(adjustedTokenPerShare)
				.div(PRECISION_FACTOR)
				.sub(user.rewardDebt);
	}

	/*
	 * @notice Redeems users dollars and rewards
	 * @param _user: user address
	 */
	function _redeem(address _user) internal {
		UserInfo storage user = userInfo[_user];
		uint256 userBondBalance = balanceOf(_user);

		// redeem dollars
		if (user.deposit > userBondBalance) {
			uint256 pendingDollars = user.deposit.sub(userBondBalance);

			user.deposit = userBondBalance;
			dollarToken.safeTransfer(_user, pendingDollars);
		}

		// redeem rewards
		uint256 pendingRewards = userBondBalance
			.mul(accTokenPerShare)
			.div(PRECISION_FACTOR)
			.sub(user.rewardDebt);

		if (pendingRewards > 0) {
			rewardToken.safeTransfer(_user, pendingRewards);
		}
	}

	/*
	 * @notice Update reward variables of the given pool to be up-to-date.
	 */
	function _updatePool() internal {
		uint256 stakedTokenSupply = totalBalance();

		if (stakedTokenSupply > 0) {
			uint256 reward = _earnReward();
			accTokenPerShare = accTokenPerShare.add(
				reward.mul(PRECISION_FACTOR).div(stakedTokenSupply)
			);
		}
	}
}
