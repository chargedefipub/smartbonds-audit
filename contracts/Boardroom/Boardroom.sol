// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '../ContractGuard.sol';
import '../Interfaces/IBasisAsset.sol';
import '../Interfaces/ITreasury.sol';
import '../Interfaces/IPancakeRouter02.sol';

contract ShareWrapper {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	IERC20 public wantToken;

	uint256 private _totalSupply;
	mapping(address => uint256) private _balances;

	function totalSupply() public view returns (uint256) {
		return _totalSupply;
	}

	function balanceOf(address account) public view returns (uint256) {
		return _balances[account];
	}

	function stake(uint256 amount) public virtual {
		_totalSupply = _totalSupply.add(amount);
		_balances[msg.sender] = _balances[msg.sender].add(amount);
		wantToken.safeTransferFrom(msg.sender, address(this), amount);
	}

	function withdraw(uint256 amount) public virtual {
		uint256 directorShare = _balances[msg.sender];
		require(
			directorShare >= amount,
			'Boardroom: withdraw request greater than staked amount'
		);
		_totalSupply = _totalSupply.sub(amount);
		_balances[msg.sender] = directorShare.sub(amount);
		wantToken.safeTransfer(msg.sender, amount);
	}
}

abstract contract Boardroom is
	ShareWrapper,
	ContractGuard,
	AccessControlEnumerable
{
	using SafeERC20 for IERC20;
	using Address for address;
	using SafeMath for uint256;

	/* ========== DATA STRUCTURES ========== */

	struct Boardseat {
		uint256 lastSnapshotIndex;
		uint256 cashRewardEarned;
		uint256 shareRewardEarned;
		uint256 epochTimerStart;
	}

	struct BoardSnapshot {
		uint256 time;
		uint256 cashRewardReceived;
		uint256 cashRewardPerShare;
		uint256 shareRewardReceived;
		uint256 shareRewardPerShare;
	}

	/* ========== STATE VARIABLES ========== */

	// governance
	bytes32 public constant allocatorRole = keccak256('allocator');

	// flags
	bool public initialized = false;

	IERC20 public cash;
	IERC20 public share;
	ITreasury public treasury;
	IPancakeRouter02 public router;
	address[] public cashToStablePath;
	address[] public shareToStablePath;

	mapping(address => Boardseat) public directors;
	BoardSnapshot[] public boardHistory;

	// protocol parameters
	uint256 public withdrawLockupEpochs;
	uint256 public rewardLockupEpochs;

	/* ========== EVENTS ========== */

	event Initialized(address indexed executor, uint256 at);
	event Staked(address indexed user, uint256 amount);
	event Withdrawn(address indexed user, uint256 amount);
	event RewardPaid(
		address indexed user,
		uint256 cashReward,
		uint256 shareReward
	);
	event RewardAdded(
		address indexed user,
		uint256 cashReward,
		uint256 shareReward
	);
	event NewTreasury(address indexed oldTreasury, address indexed newTreasury);

	/* ========== Modifiers =============== */

	modifier directorExists() {
		require(
			balanceOf(msg.sender) > 0,
			'Boardroom: The director does not exist'
		);
		_;
	}

	modifier updateReward(address director) {
		if (director != address(0)) {
			Boardseat memory seat = directors[director];
			(uint256 cashRewardEarned, uint256 sharedRewardEarned) = earned(
				director
			);
			seat.cashRewardEarned = cashRewardEarned;
			seat.shareRewardEarned = sharedRewardEarned;
			seat.lastSnapshotIndex = latestSnapshotIndex();
			directors[director] = seat;
		}
		_;
	}

	modifier notInitialized() {
		require(!initialized, 'Boardroom: already initialized');
		_;
	}

	/* ========== GOVERNANCE ========== */

	constructor(
		IERC20 _cash,
		IERC20 _share,
		IERC20 _wantToken,
		ITreasury _treasury,
		IPancakeRouter02 _router,
		address[] memory _cashToStablePath,
		address[] memory _shareToStablePath
	) {
		cash = _cash;
		share = _share;
		wantToken = _wantToken;
		treasury = _treasury;
		cashToStablePath = _cashToStablePath;
		shareToStablePath = _shareToStablePath;
		router = _router;

		BoardSnapshot memory genesisSnapshot = BoardSnapshot({
			time: block.number,
			cashRewardReceived: 0,
			shareRewardReceived: 0,
			cashRewardPerShare: 0,
			shareRewardPerShare: 0
		});
		boardHistory.push(genesisSnapshot);

		withdrawLockupEpochs = 6; // Lock for 6 epochs (36h) before release withdraw
		rewardLockupEpochs = 3; // Lock for 3 epochs (18h) before release claimReward

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(allocatorRole, address(_treasury));
		initialized = true;
		emit Initialized(msg.sender, block.number);
	}

	/**
	 * @notice It allows the admin to change up lock up durations
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _withdrawLockupEpochs The number of epochs before a withdraw can happen
	 * @param _rewardLockupEpochs The number of epochs before rewards can be claimed
	 */
	function setLockUp(
		uint256 _withdrawLockupEpochs,
		uint256 _rewardLockupEpochs
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(
			_withdrawLockupEpochs >= _rewardLockupEpochs &&
				_withdrawLockupEpochs <= 56,
			'_withdrawLockupEpochs: out of range'
		); // <= 2 week
		withdrawLockupEpochs = _withdrawLockupEpochs;
		rewardLockupEpochs = _rewardLockupEpochs;
	}

	/* ========== VIEW FUNCTIONS ========== */

	// =========== Snapshot getters

	function latestSnapshotIndex() public view returns (uint256) {
		return boardHistory.length.sub(1);
	}

	function getLatestSnapshot() internal view returns (BoardSnapshot memory) {
		return boardHistory[latestSnapshotIndex()];
	}

	function getLastSnapshotIndexOf(address director)
		public
		view
		returns (uint256)
	{
		return directors[director].lastSnapshotIndex;
	}

	function getLastSnapshotOf(address director)
		internal
		view
		returns (BoardSnapshot memory)
	{
		return boardHistory[getLastSnapshotIndexOf(director)];
	}

	function canWithdraw(address director) external view returns (bool) {
		return
			directors[director].epochTimerStart.add(withdrawLockupEpochs) <=
			treasury.epoch();
	}

	function canClaimReward(address director) external view returns (bool) {
		return
			directors[director].epochTimerStart.add(rewardLockupEpochs) <=
			treasury.epoch();
	}

	function epoch() external view returns (uint256) {
		return treasury.epoch();
	}

	function nextEpochPoint() external view returns (uint256) {
		return treasury.nextEpochPoint();
	}

	function getDollarPrice() external view returns (uint256) {
		return treasury.getDollarPrice();
	}

	// =========== Director getters

	function rewardPerShare() external view returns (uint256, uint256) {
		return (
			getLatestSnapshot().cashRewardPerShare,
			getLatestSnapshot().shareRewardPerShare
		);
	}

	function earned(address director) public view returns (uint256, uint256) {
		uint256 latestCRPS = getLatestSnapshot().cashRewardPerShare;
		uint256 storedCRPS = getLastSnapshotOf(director).cashRewardPerShare;

		uint256 latestSRPS = getLatestSnapshot().shareRewardPerShare;
		uint256 storedSRPS = getLastSnapshotOf(director).shareRewardPerShare;

		return (
			balanceOf(director).mul(latestCRPS.sub(storedCRPS)).div(1e18).add(
				directors[director].cashRewardEarned
			),
			balanceOf(director).mul(latestSRPS.sub(storedSRPS)).div(1e18).add(
				directors[director].shareRewardEarned
			)
		);
	}

	/* ========== MUTATIVE FUNCTIONS ========== */

	/*
	 * @notice Deposit staked tokens
	 * @param _amount: Amount to deposit (in want tokens)
	 */
	function stake(uint256 amount)
		public
		override
		onlyOneBlock
		updateReward(msg.sender)
	{
		_stake(amount);
	}

	function _stake(uint256 amount) internal {
		require(amount > 0, 'Boardroom: Cannot stake 0');
		super.stake(amount);
		directors[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
		emit Staked(msg.sender, amount);
	}

	/*
	 * @notice Withdraw staked tokens and collect reward tokens
	 * @dev Users can only withdraw if withdraw lock up has ended
	 * @param _amount: Amount to withdraw (in want tokens)
	 */
	function withdraw(uint256 amount)
		public
		override
		onlyOneBlock
		directorExists
		updateReward(msg.sender)
	{
		require(amount > 0, 'Boardroom: Cannot withdraw 0');
		require(
			directors[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <=
				treasury.epoch(),
			'Boardroom: still in withdraw lockup'
		);
		claimReward();
		super.withdraw(amount);
		emit Withdrawn(msg.sender, amount);
	}

	/**
	 * @notice Allows a user to exit a boardroom without rewards
	 */
	function exit() external {
		withdraw(balanceOf(msg.sender));
	}

	/**
	 * @notice Allows a user to claim rewards
	 * @dev Users can only claim rewards if reward lock up has ended
	 */
	function claimReward() public updateReward(msg.sender) {
		uint256 cashReward = directors[msg.sender].cashRewardEarned;
		uint256 shareReward = directors[msg.sender].shareRewardEarned;

		if (cashReward > 0 || shareReward > 0) {
			require(
				directors[msg.sender].epochTimerStart.add(rewardLockupEpochs) <=
					treasury.epoch(),
				'Boardroom: still in reward lockup'
			);
			directors[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
			directors[msg.sender].cashRewardEarned = 0;
			directors[msg.sender].shareRewardEarned = 0;

			if (cashReward > 0) cash.safeTransfer(msg.sender, cashReward);
			if (shareReward > 0) share.safeTransfer(msg.sender, shareReward);
			emit RewardPaid(msg.sender, cashReward, shareReward);
		}
	}

	/**
	 * @notice Pulls dollar and share rewards as part of seigniorage staking
	 * @param cashAmount The amount of dollar rewards
	 * @param shareAmount The amount of share rewards
	 */
	function allocateSeigniorage(uint256 cashAmount, uint256 shareAmount)
		external
		onlyOneBlock
		onlyRole(allocatorRole)
	{
		require(
			cashAmount > 0 || shareAmount > 0,
			'Boardroom: Cannot allocate 0'
		);
		require(
			totalSupply() > 0,
			'Boardroom: Cannot allocate when totalSupply is 0'
		);

		// Create & add new snapshot
		uint256 prevCRPS = getLatestSnapshot().cashRewardPerShare;
		uint256 nextCRPS = prevCRPS.add(
			cashAmount.mul(1e18).div(totalSupply())
		);

		uint256 prevSRPS = getLatestSnapshot().shareRewardPerShare;
		uint256 nextSRPS = prevSRPS.add(
			shareAmount.mul(1e18).div(totalSupply())
		);

		BoardSnapshot memory newSnapshot = BoardSnapshot({
			time: block.number,
			cashRewardReceived: cashAmount,
			cashRewardPerShare: nextCRPS,
			shareRewardReceived: shareAmount,
			shareRewardPerShare: nextSRPS
		});
		boardHistory.push(newSnapshot);

		if (cashAmount > 0)
			cash.safeTransferFrom(msg.sender, address(this), cashAmount);
		if (shareAmount > 0)
			share.safeTransferFrom(msg.sender, address(this), shareAmount);
		emit RewardAdded(msg.sender, cashAmount, shareAmount);
	}

	function governanceRecoverUnsupported(
		IERC20 _token,
		uint256 _amount,
		address _to
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		// do not allow to drain core tokens
		require(address(_token) != address(cash), 'cash');
		require(address(_token) != address(share), 'share');
		require(address(_token) != address(wantToken), 'wantToken');
		_token.safeTransfer(_to, _amount);
	}

	function setTreasury(ITreasury _treasury)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		emit NewTreasury(address(treasury), address(_treasury));
		treasury = _treasury;
	}
}
