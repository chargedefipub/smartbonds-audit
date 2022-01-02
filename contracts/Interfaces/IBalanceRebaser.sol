// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

// For interacting with our own strategy
interface IBalanceRebaser {
	function totalBalance() external view returns (uint256);
}
