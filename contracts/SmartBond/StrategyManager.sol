// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

import '../Interfaces/IMintableToken.sol';
import 'hardhat/console.sol';
import './ISmartBondStrategy.sol';
import '../Interfaces/IPancakeRouter02.sol';

/**
 * @notice Takes care of managing a list of strategies for smart bond pool.
 *
 **/
abstract contract StrategyManager is AccessControlEnumerable {
	using SafeMath for uint256;
	using SafeERC20 for IERC20Metadata;

	bytes32 public constant strategiestRole = keccak256('strategiest');

	// The reward token
	IERC20Metadata public rewardToken;

	// The router for swaps
	IPancakeRouter02 public router;

	// All Strategies to get yield from
	StrategyInfo[] public strategies;

	struct StrategyInfo {
		ISmartBondStrategy strategy; // The strategy to get yield from
		address[] earnToRewardPath; // Path from strategies earn token to reward token
	}

	constructor(IERC20Metadata _rewardToken, IPancakeRouter02 _router) {
		rewardToken = _rewardToken;
		router = _router;
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
	}

	/**
	 * @notice Adds a strategy for yield
	 * @param _strategy The strategy
	 * @param _earnToRewardPath Path to convert strategy earn token to reward token
	 */
	function addStrategy(
		ISmartBondStrategy _strategy,
		address[] memory _earnToRewardPath
	) external onlyRole(strategiestRole) {
		require(strategies.length <= 3, 'Too many strategies');
		require(
			address(_strategy.earnedToken()) == _earnToRewardPath[0],
			'Mismatch earn token'
		);

		for (uint256 i = 0; i < strategies.length; i++) {
			require(
				address(strategies[i].strategy) != address(_strategy),
				'Strategy exists'
			);
		}
		StrategyInfo memory strategy = StrategyInfo({
			strategy: _strategy,
			earnToRewardPath: _earnToRewardPath
		});
		strategies.push(strategy);
	}

	/**
	 * @notice Removes a strategy
	 * @param _strategy Strategy to remove
	 */
	function removeStrategy(ISmartBondStrategy _strategy)
		external
		onlyRole(strategiestRole)
	{
		for (uint256 i = 0; i < strategies.length; i++) {
			if (address(strategies[i].strategy) == address(_strategy)) {
				strategies[i] = strategies[strategies.length - 1];
				strategies.pop();
				return;
			}
		}

		revert('Strategy not found');
	}

	/**
	 * @return Number of strategies
	 */
	function strategiesSize() external view returns (uint256) {
		return strategies.length;
	}

	/*
	 * @notice Function to earn from all strategies
	 * @dev This will loop through all active strategies and gather rewards
	 * @return Total rewards earned from all strategies
	 */
	function _earnReward() internal returns (uint256) {
		uint256 rewardBefore = rewardToken.balanceOf(address(this));
		for (uint256 i = 0; i < strategies.length; i++) {
			// earn from strategy
			uint256 balanceBefore = strategies[i]
				.strategy
				.earnedToken()
				.balanceOf(address(this));
			strategies[i].strategy.earn();
			uint256 earnedAmount = strategies[i]
				.strategy
				.earnedToken()
				.balanceOf(address(this))
				.sub(balanceBefore);

			// convert earn to reward
			if (earnedAmount > 0 && strategies[i].earnToRewardPath.length > 1) {
				router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
					earnedAmount,
					0,
					strategies[i].earnToRewardPath,
					address(this),
					block.timestamp.add(600)
				);
			}
		}

		return rewardToken.balanceOf(address(this)).sub(rewardBefore);
	}

	/*
	 * @notice View function to aggregate all unharvested rewards
	 * @dev This will loop through all active strategies and aggregate unharvested rewards
	 * @return Total unharvested rewards to be earned from all strategies
	 */
	function _unharvestedRewards() internal view returns (uint256) {
		uint256 unharvested = 0;

		for (uint256 i = 0; i < strategies.length; i++) {
			StrategyInfo memory strategyInfo = strategies[i];
			uint256 pendingEarned = strategyInfo.strategy.pendingEarned();
			if (pendingEarned > 0) {
				if (strategyInfo.earnToRewardPath.length > 1) {
					uint256[] memory amounts = router.getAmountsOut(
						pendingEarned,
						strategyInfo.earnToRewardPath
					);
					pendingEarned = amounts[amounts.length - 1];
				}
				unharvested.add(pendingEarned);
			}
		}

		return unharvested;
	}
}
