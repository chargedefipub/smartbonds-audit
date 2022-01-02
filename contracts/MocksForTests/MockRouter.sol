// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import 'hardhat/console.sol';

contract MockRouter {

	function getAmountsOut(uint256 amountIn, address[] calldata path)
		external
		view
		returns (uint256[] memory amounts)
	{
		amounts = new uint256[](1);
		
		amounts[0] = 1e18;
		return amounts;
	}
}