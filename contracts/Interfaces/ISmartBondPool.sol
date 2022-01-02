// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

// For interacting with our own strategy
interface ISmartBondPool {
	// Transfer want tokens yetiFarm -> strategy
	function allocateSeigniorage(uint256 amount_) external;
}
