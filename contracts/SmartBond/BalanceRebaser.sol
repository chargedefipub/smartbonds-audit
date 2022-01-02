// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import 'hardhat/console.sol';
import '../Interfaces/IBalanceRebaser.sol';

abstract contract BalanceRebaser is IBalanceRebaser {
	using SafeMath for uint256;

	uint256 internal _totalGons;
	uint256 internal _gonsPerFragment = 10**20;
	uint256 internal _totalBalance;

	mapping(address => uint256) internal _balances;

	function balanceOf(address account) public view returns (uint256) {
		if (_gonsPerFragment == 0) return 0;
		return _balances[account].div(_gonsPerFragment);
	}

	function totalBalance() public override view returns (uint256) {
		return _totalBalance;
	}

	/**
	 * @dev Notifies Fragments contract about a new rebase cycle.
	 * @param supplyDelta The number of new fragment tokens to add into circulation via expansion.
	 * Return The total number of fragments after the supply adjustment.
	 */
	function _reduceTotalBalance(uint256 supplyDelta)
		internal
		returns (uint256)
	{
		// if supply delta is 0 nothing to rebase
		// if rebaseSupply is 0 nothing can be rebased
		if (supplyDelta == 0) {
			return _totalBalance;
		}
		_totalBalance = _totalBalance.sub(supplyDelta);
		_gonsPerFragment = _totalGons.div(_totalBalance);
		return _totalBalance;
	}

	function _increaseBalance(address recipient_, uint256 amount_) internal {
		require(
			recipient_ != address(0),
			'ERC20: transfer to the zero address'
		);
		require(amount_ > 0, "ERC20: Can't mint 0 tokens");

		_totalGons = _totalGons.add(_gonsPerFragment.mul(amount_));
		_totalBalance = _totalBalance.add(amount_);
		_balances[recipient_] = _balances[recipient_].add(
			amount_.mul(_gonsPerFragment)
		);
	}

	function _reduceBalance(address account, uint256 amount_) internal {
		require(account != address(0), 'ERC20: burn from the zero address');

		uint256 accountBalance = _balances[account];
		require(
			accountBalance >= amount_,
			'ERC20: burn amount exceeds balance'
		);
		unchecked {
			_balances[account] = _balances[account].sub(
				amount_.mul(_gonsPerFragment)
			);
		}

		_totalGons = _totalGons.sub(_gonsPerFragment.mul(amount_));
		_totalBalance = _totalBalance.sub(amount_);
	}
}
