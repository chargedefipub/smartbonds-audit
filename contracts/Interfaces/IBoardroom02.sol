pragma solidity 0.8.4;

import './IBoardroom.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IBoardroom02 is IBoardroom {
	struct BoardSnapshot {
		uint256 time;
		uint256 cashRewardReceived;
		uint256 cashRewardPerShare;
		uint256 shareRewardReceived;
		uint256 shareRewardPerShare;
	}

	function wantToken() external view returns (IERC20);

	function cash() external view returns (IERC20);

	function share() external view returns (IERC20);

	function totalSupply() external view returns (uint256);

	function latestSnapshotIndex() external view returns (uint256);

	function boardHistory(uint256 _index)
		external
		view
		returns (BoardSnapshot memory);
}
