pragma solidity 0.8.4;

import '../Interfaces/ISmartBondPool.sol';

contract MockSmartBondPool is ISmartBondPool {
	constructor(
		address bond,
		address stable,
		address dollar
	) {}

	function allocateSeigniorage(uint256 amount_) external override {}
}
