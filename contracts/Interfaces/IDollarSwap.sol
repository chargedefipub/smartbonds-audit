// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface IDollarSwap {
	function canSwap(uint256 _dollarAmount) external view returns (bool);

	function rewardExpected(uint256 _dollarAmount)
		external
		view
		returns (uint256);

	function swap(uint256 _dollarAmount) external;
}
