pragma solidity 0.8.4;

interface IBoardroomAllocation {
	function totalCashAllocationPoints() external view returns (uint256);

	function totalShareAllocationPoints() external view returns (uint256);

	function boardrooms(uint256 index)
		external
		view
		returns (
			address,
			bool,
			uint256,
			uint256
		);

	function deactivateBoardRoom(uint256 index) external;

	function addBoardroom(
		address boardroom_,
		uint256 cashAllocationPoints_,
		uint256 shareAllocationPoints_
	) external;

	function updateBoardroom(
		uint256 index,
		uint256 cashAllocationPoints_,
		uint256 shareAllocationPoints_
	) external;

	function boardroomInfoLength() external view returns (uint256);
}
