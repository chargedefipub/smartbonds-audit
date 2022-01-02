// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

// For interacting with the pancake smart chef syrup pools
interface IMasterChef {
	function leaveStaking(uint256 _amount) external;

	function enterStaking(uint256 _amount) external;

	function pendingCake(uint256 _pid, address _user)
		external
		view
		returns (uint256);

	function deposit(uint256 _pid, uint256 _amount) external;

	function withdraw(uint256 _pid, uint256 _amount) external;
}
