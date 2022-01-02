// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '../Interfaces/IBoardroomAllocation.sol';

contract BoardroomAllocation is AccessControlEnumerable, IBoardroomAllocation {
	using SafeMath for uint256;

	struct BoardroomInfo {
		address boardroom;
		bool isActive;
		uint256 cashAllocationPoints;
		uint256 shareAllocationPoints;
	}

	BoardroomInfo[] public override boardrooms;
	uint256 public override totalCashAllocationPoints = 0;
	uint256 public override totalShareAllocationPoints = 0;

	event BoardroomDeactivated(address indexed boardroom);
	event BoardroomAdded(
		address indexed boardroom,
		uint256 cashAllocationPoints,
		uint256 shareAllocationPoints
	);
	event BoardroomUpdated(
		address indexed boardroom,
		uint256 cashAllocationPoints,
		uint256 shareAllocationPoints
	);

	constructor() {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
	}

	function deactivateBoardRoom(uint256 index)
		external
		override
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		BoardroomInfo storage boardroom = boardrooms[index];
		require(boardroom.isActive, 'Boardroom has been deactivated');
		boardroom.isActive = false;
		totalCashAllocationPoints = totalCashAllocationPoints.sub(
			boardroom.cashAllocationPoints
		);
		totalShareAllocationPoints = totalShareAllocationPoints.sub(
			boardroom.shareAllocationPoints
		);

		emit BoardroomDeactivated(boardroom.boardroom);
	}

	function addBoardroom(
		address boardroom_,
		uint256 cashAllocationPoints_,
		uint256 shareAllocationPoints_
	) external override onlyRole(DEFAULT_ADMIN_ROLE) {
		totalCashAllocationPoints = totalCashAllocationPoints.add(
			cashAllocationPoints_
		);
		totalShareAllocationPoints = totalShareAllocationPoints.add(
			shareAllocationPoints_
		);

		boardrooms.push(
			BoardroomInfo({
				cashAllocationPoints: cashAllocationPoints_,
				shareAllocationPoints: shareAllocationPoints_,
				isActive: true,
				boardroom: boardroom_
			})
		);

		emit BoardroomAdded(
			boardroom_,
			cashAllocationPoints_,
			shareAllocationPoints_
		);
	}

	function updateBoardroom(
		uint256 index,
		uint256 cashAllocationPoints_,
		uint256 shareAllocationPoints_
	) external override onlyRole(DEFAULT_ADMIN_ROLE) {
		BoardroomInfo storage br = boardrooms[index];

		totalCashAllocationPoints = totalCashAllocationPoints
			.sub(br.cashAllocationPoints)
			.add(cashAllocationPoints_);
		br.cashAllocationPoints = cashAllocationPoints_;

		totalShareAllocationPoints = totalShareAllocationPoints
			.sub(br.shareAllocationPoints)
			.add(shareAllocationPoints_);
		br.shareAllocationPoints = shareAllocationPoints_;

		emit BoardroomUpdated(
			br.boardroom,
			cashAllocationPoints_,
			shareAllocationPoints_
		);
	}

	function boardroomInfoLength() external view override returns (uint256) {
		return boardrooms.length;
	}
}
