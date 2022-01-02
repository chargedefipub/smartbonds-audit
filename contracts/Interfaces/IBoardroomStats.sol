pragma solidity 0.8.4;

import './IBoardroom02.sol';

interface IBoardroomStats {
	function APR(IBoardroom02 _boardroom) external view returns (uint256);

	function TVL(IBoardroom02 _boardroom) external view returns (uint256);

	function stakedTokenPrice(IBoardroom02 _boardroom)
		external
		view
		returns (uint256);
}
