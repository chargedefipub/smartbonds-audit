// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import './Boardroom.sol';
import '../Interfaces/IZapper.sol';

contract LPTokenBoardroom is Boardroom {
	using SafeERC20 for IERC20;

	IZapper public zapper;
	address[] public shareToCashPath;
	bool public compoundEnabled;

	event BoardroomCompound(
		address indexed user,
		uint256 cashRewards,
		uint256 shareRewards,
		uint256 amount
	);
	event NewZapper(address indexed oldZapper, address indexed newZapper);
	event NewCompoundEnabled(bool enabled);

	constructor(
		IERC20 _cash,
		IERC20 _share,
		IERC20 _wantToken,
		ITreasury _treasury,
		IPancakeRouter02 _router,
		IZapper _zapper,
		address[] memory _cashToStablePath,
		address[] memory _shareToStablePath,
		address[] memory _shareToCashPath
	)
		Boardroom(
			_cash,
			_share,
			_wantToken,
			_treasury,
			_router,
			_cashToStablePath,
			_shareToStablePath
		)
	{
		zapper = _zapper;
		shareToCashPath = _shareToCashPath;
		compoundEnabled = false;

		share.safeApprove(address(router), type(uint256).max);
		_approveZapper();
	}

	function compound() external onlyOneBlock updateReward(msg.sender) {
		require(compoundEnabled, 'Compound is not enabled');

		uint256 cashReward = directors[msg.sender].cashRewardEarned;
		uint256 shareReward = directors[msg.sender].shareRewardEarned;

		require(cashReward > 0 || shareReward > 0, 'No rewards to compound');

		directors[msg.sender].cashRewardEarned = 0;
		directors[msg.sender].shareRewardEarned = 0;

		uint256 totalCashRewards = cashReward;
		if (shareReward > 0) {
			totalCashRewards = cashReward + _swapShareToCash(shareReward);
		}

		uint256 wantToDeposit = _zapCashToWant(totalCashRewards);
		// transfer zapped lp to sender so stake can pull from sender
		wantToken.safeTransfer(msg.sender, wantToDeposit);
		_stake(wantToDeposit);

		emit BoardroomCompound(
			msg.sender,
			cashReward,
			shareReward,
			wantToDeposit
		);
	}

	function setZapper(IZapper _zapper) external onlyRole(DEFAULT_ADMIN_ROLE) {
		emit NewZapper(address(zapper), address(_zapper));
		cash.safeApprove(address(zapper), 0);
		zapper = _zapper;
		_approveZapper();
	}

	function setCompoundEnabled(bool _enabled)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(compoundEnabled != _enabled, 'Enable value must be different');
		emit NewCompoundEnabled(_enabled);
		compoundEnabled = _enabled;
	}

	function _swapShareToCash(uint256 amount) private returns (uint256) {
		uint256 balanceBefore = cash.balanceOf(address(this));
		router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
			amount,
			0,
			shareToCashPath,
			address(this),
			block.timestamp + 600
		);
		return cash.balanceOf(address(this)) - balanceBefore;
	}

	function _zapCashToWant(uint256 amount) private returns (uint256) {
		uint256 balanceBefore = wantToken.balanceOf(address(this));
		zapper.zapTokenToLP(address(cash), amount, address(wantToken));
		return wantToken.balanceOf(address(this)) - balanceBefore;
	}

	function _approveZapper() private {
		cash.safeApprove(address(zapper), type(uint256).max);
	}
}
