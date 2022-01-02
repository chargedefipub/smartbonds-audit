// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface IEpochListener {
	function epochUpdate(uint256 newEpoch) external;
}
