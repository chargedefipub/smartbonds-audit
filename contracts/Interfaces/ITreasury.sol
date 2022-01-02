// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface ITreasury {
	function PERIOD() external view returns (uint256);

	function epoch() external view returns (uint256);

	function nextEpochPoint() external view returns (uint256);

	function getDollarPrice() external view returns (uint256);
}
