// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../Interfaces/IStrategy.sol';

// For interacting with our own strategy
interface ISmartBondStrategy is IStrategy {
	function pendingEarned() external view returns (uint256);
}
