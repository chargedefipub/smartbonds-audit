pragma solidity 0.8.4;
import '../Interfaces/IBoardroom.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import 'hardhat/console.sol';

contract MockBoardroom is IBoardroom {
	IERC20 public cash;
	IERC20 public share;
	uint256 public rewardAmount;

	constructor(IERC20 _cash, IERC20 _share) {
		cash = _cash;
		share = _share;
	}

	function balanceOf(address _director)
		external
		view
		override
		returns (uint256)
	{
		return 0;
	}

	function earned(address _director)
		external
		view
		override
		returns (uint256, uint256)
	{
		return (0, 0);
	}

	function canWithdraw(address _director)
		external
		view
		override
		returns (bool)
	{
		return true;
	}

	function canClaimReward(address _director)
		external
		view
		override
		returns (bool)
	{
		return true;
	}

	function setOperator(address _operator) external override {}

	function setLockUp(
		uint256 _withdrawLockupEpochs,
		uint256 _rewardLockupEpochs
	) external override {}

	function stake(uint256 _amount) external override {}

	function withdraw(uint256 _amount) external override {}

	function exit() external override {}

	function claimReward() external override {
		cash.transfer(msg.sender, rewardAmount);
	}

	function allocateSeigniorage(uint256 _cashAmount, uint256 _shareAmount)
		external
		override
	{
		cash.transferFrom(msg.sender, address(this), _cashAmount);
		share.transferFrom(msg.sender, address(this), _shareAmount);
	}

	function governanceRecoverUnsupported(
		address _token,
		uint256 _amount,
		address _to
	) external override {}

	function APR() external pure override returns (uint256) {
		return 1e18;
	}

	function setRewardAmount(uint256 _rewardAmount) external {
		rewardAmount = _rewardAmount;
	}
}
