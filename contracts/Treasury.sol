// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import './lib/Babylonian.sol';
import './Interfaces/IBasisAsset.sol';
import './Interfaces/IOracle.sol';
import './Interfaces/IBoardroom.sol';
import './Interfaces/IShare.sol';
import './Interfaces/IBoardroomAllocation.sol';
import './lib/SafeMathint.sol';
import './lib/UInt256Lib.sol';
import './Interfaces/ITreasury.sol';
import './Interfaces/ISmartBondPool.sol';
import './Interfaces/IBalanceRebaser.sol';
import './Interfaces/IEpochListener.sol';

/**
 * @title Charge Defi Treasury contract
 * @notice Monetary policy logic to adjust supplies of tokens based on price. This increases above peg and rebases below
 *
 */
contract Treasury is AccessControlEnumerable, ITreasury, ReentrancyGuard {
	using SafeERC20 for IERC20;
	using Address for address;
	using SafeMath for uint256;
	using UInt256Lib for uint256;
	using SafeMathInt for int256;

	/* ========= CONSTANT VARIABLES ======== */

	uint256 public override PERIOD;
	bytes32 public constant allocatorRole = keccak256('allocator');

	/* ========== STATE VARIABLES ========== */

	// flags
	bool public migrated = false;
	bool public initialized = false;

	// epoch
	uint256 public startTime;
	uint256 public override epoch = 0;
	uint256 public epochSupplyContractionLeft = 0;
	uint256 public epochsUnderOne = 0;

	// core components
	address public dollar;
	address public bond;
	address public share;

	address public boardroomAllocation;
	address public dollarOracle;
	address public smartBondPool;

	// Listeners than can be notified of an epoch change
	IEpochListener[] public listeners;

	// price
	uint256 public dollarPriceOne;
	uint256 public dollarPriceCeiling;

	uint256 public seigniorageSaved;

	// protocol parameters
	uint256 public bondDepletionFloorPercent;
	uint256 public smartBondDepletionFloorPercent;
	uint256 public maxDebtRatioPercent;
	uint256 public devPercentage;
	uint256 public bondRepayPercent;
	uint256 public bondRepayToBondSmartPoolPercent;
	int256 public contractionIndex;
	int256 public expansionIndex;
	uint256 public triggerRebasePriceCeiling;
	uint256 public triggerRebaseNumEpochFloor;
	uint256 public maxSupplyContractionPercent;

	// share rewards
	uint256 public sharesMintedPerEpoch;

	address public devAddress;

	/* =================== Events =================== */

	event Initialized(address indexed executor, uint256 at);
	event Migration(address indexed target);
	event RedeemedBonds(
		uint256 indexed epoch,
		address indexed from,
		uint256 amount
	);
	event BoughtBonds(
		uint256 indexed epoch,
		address indexed from,
		uint256 amount
	);
	event TreasuryFunded(
		uint256 indexed epoch,
		uint256 timestamp,
		uint256 seigniorage
	);
	event BoardroomFunded(
		uint256 indexed epoch,
		uint256 timestamp,
		uint256 seigniorage,
		uint256 shareRewards
	);
	event DevsFunded(
		uint256 indexed epoch,
		uint256 timestamp,
		uint256 seigniorage
	);

	event NewSmartBondPool(address indexed smartBondPool);
	event NewSmartBondPoolPercent(uint256 percent);
	event NewContractIndex(int256 percent);
	event NewExpansionIndex(int256 percent);
	event NewBondRepayPercent(uint256 percent);
	event NewMaxSupplyContraction(uint256 percent);
	event NewMaxDebtRatio(uint256 percent);
	event NewBondDepletionFloor(uint256 percent);
	event NewSmartBondDepletionFloor(uint256 percent);
	event NewDevPercentage(uint256 percent);
	event NewDevAddress(address indexed devAddress);
	event NewDollarOracle(address indexed oracle);
	event NewDollarPriceCeiling(uint256 dollarCeiling);
	event NewRebasePriceCeiling(uint256 priceCeiling);
	event NewRebaseNumEpochFloor(uint256 floor);
	event NewSharesMintedPerEpoch(uint256 amount);

	/* =================== Modifier =================== */

	modifier whenActive() {
		require(!migrated, 'Migrated');
		require(block.timestamp >= startTime, 'Not started yet');
		_;
	}

	modifier whenNextEpoch() {
		require(block.timestamp >= nextEpochPoint(), 'Not opened yet');
		epoch = epoch.add(1);

		epochSupplyContractionLeft = IERC20(dollar)
			.totalSupply()
			.mul(maxSupplyContractionPercent)
			.div(10000);
		_;
	}

	/**
	 * @dev Modifier to make a function callable only by a certain role. In
	 * addition to checking the sender's role, `address(0)` 's role is also
	 * considered. Granting a role to `address(0)` is equivalent to enabling
	 * this role for everyone.
	 */
	modifier onlyRoleOrOpenRole(bytes32 role) {
		if (!hasRole(role, address(0))) {
			_checkRole(role, _msgSender());
		}
		_;
	}

	/* ========== VIEW FUNCTIONS ========== */

	// flags
	function isMigrated() external view returns (bool) {
		return migrated;
	}

	function isInitialized() external view returns (bool) {
		return initialized;
	}

	// epoch
	function nextEpochPoint() public view override returns (uint256) {
		return startTime.add(epoch.mul(PERIOD));
	}

	// oracle
	function getDollarPrice()
		public
		view
		override
		returns (uint256 dollarPrice)
	{
		try IOracle(dollarOracle).consult(dollar, 1e18) returns (
			uint256 price
		) {
			return price;
		} catch {
			revert('Failed to consult dollar price from the oracle');
		}
	}

	// budget
	function getReserve() public view returns (uint256) {
		return seigniorageSaved;
	}

	constructor() {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
	}

	/* ========== GOVERNANCE ========== */

	function initialize(
		uint256 _period,
		address _dollar,
		address _bond,
		address _share,
		uint256 _startTime,
		address _devAddress,
		address _boardroomAllocation,
		address _dollarOracle,
		address _smartBondPool
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(!initialized, 'Initialized');

		expansionIndex = 1000;
		contractionIndex = 10000;
		bondDepletionFloorPercent = 10000;
		smartBondDepletionFloorPercent = 9500;
		bondRepayPercent = 1000;
		triggerRebaseNumEpochFloor = 5;
		maxSupplyContractionPercent = 300;
		maxDebtRatioPercent = 3500;
		PERIOD = _period;

		dollar = _dollar;
		bond = _bond;
		share = _share;
		smartBondPool = _smartBondPool;
		startTime = _startTime;
		devAddress = _devAddress;
		boardroomAllocation = _boardroomAllocation;
		dollarOracle = _dollarOracle;
		dollarPriceOne = 1e18;
		dollarPriceCeiling = dollarPriceOne.mul(101).div(100);
		triggerRebasePriceCeiling = dollarPriceOne.mul(80).div(100);

		seigniorageSaved = IERC20(dollar).balanceOf(address(this));

		initialized = true;
		emit Initialized(msg.sender, block.number);
	}

	/**
	 * @notice It allows the admin to change address of the smart bond pool
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _smartBondPool The new smart bond pool
	 */
	function setSmartBondPool(address _smartBondPool)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		smartBondPool = _smartBondPool;
		emit NewSmartBondPool(_smartBondPool);
	}

	/**
	 * @notice It allows the admin to change how much of bond savings should be sent to smart bond pool
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param newAmount The new percentage
	 */
	function setSmartBondPoolPercent(uint256 newAmount)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		bondRepayToBondSmartPoolPercent = newAmount;
		emit NewSmartBondPoolPercent(bondRepayToBondSmartPoolPercent);
	}

	/**
	 * @notice It allows the admin to change how much contraction via rebases is allowed each epoch under peg
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _contractionIndex The new contraction index
	 */
	function setContractionIndex(int256 _contractionIndex)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(_contractionIndex >= 0, 'less than 0');
		require(_contractionIndex <= 10000, 'Contraction too large');
		contractionIndex = _contractionIndex;
		emit NewContractIndex(_contractionIndex);
	}

	/**
	 * @notice It allows the admin to change how much expansion is allowed each epoch over peg
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _expansionIndex The new expansion index
	 */
	function setExpansionIndex(int256 _expansionIndex)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(_expansionIndex >= 0, 'less than 0');
		require(_expansionIndex <= 10000, 'Expansion too large');
		expansionIndex = _expansionIndex;
		emit NewExpansionIndex(_expansionIndex);
	}

	/**
	 * @notice It allows the admin to change how much bonds are repaid each epoch after a contraction
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _bondRepayPercent The new repay percent
	 */
	function setBondRepayPercent(uint256 _bondRepayPercent)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(_bondRepayPercent <= 10000, 'Bond repayment is too large');
		bondRepayPercent = _bondRepayPercent;
		emit NewBondRepayPercent(_bondRepayPercent);
	}

	/**
	 * @notice It allows the admin to change how much contraction is allowed due to bond buying
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _maxSupplyContractionPercent The percent of the max supply that can be used for bonds
	 */
	function setMaxSupplyContractionPercent(
		uint256 _maxSupplyContractionPercent
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(_maxSupplyContractionPercent <= 10000, 'out of range'); // [0%, 100%]
		maxSupplyContractionPercent = _maxSupplyContractionPercent;
		emit NewMaxSupplyContraction(_maxSupplyContractionPercent);
	}

	/**
	 * @notice It allows the admin to change the max debt ratio of the protocol
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _maxDebtRatioPercent The new debt ratio
	 */
	function setMaxDebtRatioPercent(uint256 _maxDebtRatioPercent)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(_maxDebtRatioPercent <= 10000, 'out of range'); // [0%, 100%]
		maxDebtRatioPercent = _maxDebtRatioPercent;
		emit NewMaxDebtRatio(_maxDebtRatioPercent);
	}

	/**
	 * @notice It allows the admin to change the amount of bonds that can be funded
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _bondDepletionFloorPercent The new bond depletion percent
	 */
	function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(
			_bondDepletionFloorPercent >= 500 &&
				_bondDepletionFloorPercent <= 10000,
			'out of range'
		); // [5%, 100%]
		bondDepletionFloorPercent = _bondDepletionFloorPercent;
		emit NewBondDepletionFloor(_bondDepletionFloorPercent);
	}

	/**
	 * @notice It allows the admin to change the max amount of bonds from the total supply in smart bond pool that can
	 *			be funded.
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _smartBondDepletionFloorPercent The new bond depletion percent for the smart bond pool
	 */
	function setSmartBondDepletionFloorPercent(
		uint256 _smartBondDepletionFloorPercent
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(_smartBondDepletionFloorPercent <= 99000, 'out of range'); // [0%, 99%]
		smartBondDepletionFloorPercent = _smartBondDepletionFloorPercent;
		emit NewSmartBondDepletionFloor(_smartBondDepletionFloorPercent);
	}

	/**
	 * @notice It allows the admin to change the amount devs get each expansion
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _devPercentage The new dev percentage in basis points
	 */
	function setDevPercentage(uint256 _devPercentage)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(_devPercentage < 2000, 'Greedy devs are bad.');

		devPercentage = _devPercentage;
		emit NewDevPercentage(_devPercentage);
	}

	/**
	 * @notice It allows the admin to change the dev address funded each expansion
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _devAddress The new dev address
	 */
	function setDevAddress(address _devAddress)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		devAddress = _devAddress;
		emit NewDevAddress(_devAddress);
	}

	/**
	 * @notice It allows the admin to change the dollar oracle
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _dollarOracle The new dollar oracle
	 */
	function setDollarOracle(address _dollarOracle)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		dollarOracle = _dollarOracle;
		emit NewDollarOracle(_dollarOracle);
	}

	/**
	 * @notice It allows the admin to change the dollar price ceiling. i.e upper limit of peg
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _dollarPriceCeiling The upper limit of peg
	 */
	function setDollarPriceCeiling(uint256 _dollarPriceCeiling)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(
			_dollarPriceCeiling >= dollarPriceOne &&
				_dollarPriceCeiling <= dollarPriceOne.mul(120).div(100),
			'out of range'
		); // [$1.0, $1.2]
		dollarPriceCeiling = _dollarPriceCeiling;
		emit NewDollarPriceCeiling(_dollarPriceCeiling);
	}

	/**
	 * @notice It allows the admin to change at what price rebases happen
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _triggerRebasePriceCeiling The new dollar price to rebase at
	 */
	function setTriggerRebasePriceCeiling(uint256 _triggerRebasePriceCeiling)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(
			_triggerRebasePriceCeiling < dollarPriceOne,
			'rebase ceiling is too high'
		);
		triggerRebasePriceCeiling = _triggerRebasePriceCeiling;
		emit NewRebasePriceCeiling(_triggerRebasePriceCeiling);
	}

	/**
	 * @notice It allows the admin to shares minted per epoch
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _triggerRebaseNumEpochFloor The new number of epochs before a rebase happens
	 */
	function setTriggerRebaseNumEpochFloor(uint256 _triggerRebaseNumEpochFloor)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		triggerRebaseNumEpochFloor = _triggerRebaseNumEpochFloor;
		emit NewRebaseNumEpochFloor(_triggerRebaseNumEpochFloor);
	}

	/**
	 * @notice It allows the admin to shares minted per epoch
	 * @dev This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param _sharesMintedPerEpoch The new mint value
	 */
	function setSharesMintedPerEpoch(uint256 _sharesMintedPerEpoch)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		sharesMintedPerEpoch = _sharesMintedPerEpoch;
		emit NewSharesMintedPerEpoch(_sharesMintedPerEpoch);
	}

	/**
	 * @notice Adds an address as IEpochListener that gets called when a epoch updates
	 * @param listener Address of the listener contract
	 */
	function addEpochListener(IEpochListener listener)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(listeners.length <= 10, 'Too many listeners');

		for (uint256 i = 0; i < listeners.length; i++) {
			require(listeners[i] != listener, 'Listener exists');
		}
		listeners.push(listener);
	}

	/**
	 * @notice Removes an address as IEpochListener that gets called when a epoch updates
	 * @param listener Address of the listener contract
	 */
	function removeEpochListener(IEpochListener listener)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		for (uint256 i = 0; i < listeners.length; i++) {
			if (listeners[i] == listener) {
				listeners[i] = listeners[listeners.length - 1];
				listeners.pop();
				return;
			}
		}

		revert('Listener not found');
	}

	/**
	 * @return Number of listeners, in the listener list
	 */
	function listenersSize() external view returns (uint256) {
		return listeners.length;
	}

	/**
	 * @dev Handles migrating assets to a new treasury contract
	 *
	 * Steps to migrate
	 *	1. Deploy new treasury contract with required roles
	 * 	2. Call this migrate method with `target`
	 *  3. Revoke roles of this contract (optional, as all mint/rebase functions are blocked after migration)
	 *
	 * This function is only callable by DEFAULT_ADMIN_ROLE
	 * @param target The address of the new Treasury contract
	 *
	 */
	function migrate(address target) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(!migrated, 'Migrated');

		require(target != address(0), 'New contract cannot be zero');

		IERC20(dollar).safeTransfer(
			target,
			IERC20(dollar).balanceOf(address(this))
		);
		IERC20(bond).safeTransfer(
			target,
			IERC20(bond).balanceOf(address(this))
		);
		IERC20(share).safeTransfer(
			target,
			IERC20(share).balanceOf(address(this))
		);

		migrated = true;
		emit Migration(target);
	}

	/* ========== MUTABLE FUNCTIONS ========== */

	function _updateDollarPrice() internal {
		try IOracle(dollarOracle).update() {} catch {}
	}

	/**
	 * @notice Buy bonds for a user
	 * @dev Bonds can only be redeemed below peg and only a certain amount `epochSupplyContractionLeft`
	 *		can be bought per epoch
	 * @param amount The amount bonds to buy
	 */
	function buyBonds(uint256 amount) external nonReentrant whenActive {
		require(amount > 0, 'Cannot purchase bonds with zero amount');

		uint256 dollarPrice = getDollarPrice();
		uint256 accountBalance = IERC20(dollar).balanceOf(msg.sender);

		require(
			dollarPrice < dollarPriceOne, // price < $1
			'DollarPrice not eligible for bond purchase'
		);

		require(
			amount <= epochSupplyContractionLeft,
			'Not enough bond left to purchase this epoch'
		);
		require(accountBalance >= amount, 'Not enough BTD to buy bond');

		uint256 dollarSupply = IERC20(dollar).totalSupply();
		uint256 newBondSupply = IERC20(bond).totalSupply().add(amount);

		require(
			newBondSupply <= dollarSupply.mul(maxDebtRatioPercent).div(10000),
			'over max debt ratio'
		);

		IBasisAsset(dollar).burnFrom(msg.sender, amount);
		IBasisAsset(bond).mint(msg.sender, amount);

		epochSupplyContractionLeft = epochSupplyContractionLeft.sub(amount);
		_updateDollarPrice();

		emit BoughtBonds(epoch, msg.sender, amount);
	}

	/**
	 * @notice Redeems bonds for a user
	 * @dev Bonds can only be redeemed above peg and treasury must have enough funds for redemption
	 * @param amount The amount bonds to be redeemed
	 */
	function redeemBonds(uint256 amount) external nonReentrant whenActive {
		require(amount > 0, 'Cannot redeem bonds with zero amount');

		uint256 dollarPrice = getDollarPrice();
		require(
			dollarPrice > dollarPriceCeiling, // price > $1.01
			'DollarPrice not eligible for bond purchase'
		);
		require(
			IERC20(dollar).balanceOf(address(this)) >= amount,
			'Treasury has no more budget'
		);
		require(getReserve() >= amount, "Treasury hasn't saved any dollar");

		seigniorageSaved = seigniorageSaved.sub(amount);

		IBasisAsset(bond).burnFrom(msg.sender, amount);
		IERC20(dollar).safeTransfer(msg.sender, amount);

		_updateDollarPrice();

		emit RedeemedBonds(epoch, msg.sender, amount);
	}

	/**
	 * @notice Handles the expansion/contract of dollar supply based on epoch price
	 * @dev This can only be called once per epoch
	 */
	function allocateSeigniorage()
		external
		nonReentrant
		whenActive
		whenNextEpoch
		onlyRoleOrOpenRole(allocatorRole)
	{
		_updateDollarPrice();

		// expansion amount = (TWAP - 1.00) * totalsupply * index / maxindex
		// 10% saved for bonds
		// 10% after bonds saved for team
		// 45% after bonds given to shares
		// 45% after bonds given to LP

		uint256 dollarPrice = getDollarPrice();
		epochsUnderOne = dollarPrice >= dollarPriceOne
			? 0
			: epochsUnderOne.add(1);

		int256 supplyDelta = _computeSupplyDelta(dollarPrice, dollarPriceOne);
		uint256 shareRewards = _getSharesRewardsForEpoch();
		uint256 dollarRewards = 0;

		if (dollarPrice > dollarPriceCeiling) {
			dollarRewards = _expandDollar(supplyDelta);
		} else if (
			dollarPrice <= triggerRebasePriceCeiling ||
			epochsUnderOne > triggerRebaseNumEpochFloor
		) {
			_contractDollar(supplyDelta);
		}
		_sendToBoardRoom(dollarRewards, shareRewards);
		_notifyEpochChanged();
	}

	/**
	 * @notice It allows the admin to tokens in the contract
	 * @dev This function is only callable by admin.
	 * @param _token The address of the token to withdraw
	 * @param _amount The number of tokens to withdraw
	 * @param _to The account to send tokens
	 */
	function governanceRecoverUnsupported(
		IERC20 _token,
		uint256 _amount,
		address _to
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		// do not allow to drain core tokens
		require(address(_token) != address(dollar), 'dollar');
		require(address(_token) != address(bond), 'bond');
		require(address(_token) != address(share), 'share');
		_token.safeTransfer(_to, _amount);
	}

	/**
	 * @notice The amount of shares that can be minted per epoch
	 * @return Shares amount
	 */
	function _getSharesRewardsForEpoch() internal view returns (uint256) {
		uint256 mintLimit = IShare(share).mintLimitOf(address(this));
		uint256 mintedAmount = IShare(share).mintedAmountOf(address(this));

		uint256 amountMintable = mintLimit > mintedAmount
			? mintLimit.sub(mintedAmount)
			: 0;

		return Math.min(sharesMintedPerEpoch, amountMintable);
	}

	/**
	 * @notice Expands the dollar supply based on input
	 * @dev This method expands, saves tokens for bonds and returns the remaining amount available for boardroom
	 * @param supplyDelta The amount to increase the dollar supply by
	 * @return The amount of dollar tokens saved for boardroom
	 */
	function _expandDollar(int256 supplyDelta) private returns (uint256) {
		require(supplyDelta >= 0, 'Not allowed to convert to uint');

		// Expansion (Price > 1.01$): there is some seigniorage to be allocated
		supplyDelta = supplyDelta.mul(expansionIndex).div(10000);

		uint256 _bondSupply = IERC20(bond).totalSupply();
		uint256 _savedForBond = 0;
		uint256 _savedForBoardRoom;
		uint256 _savedForDevs;
		uint256 _totalBondsToRepay = _bondSupply
			.mul(bondDepletionFloorPercent)
			.div(10000);

		if (seigniorageSaved >= _totalBondsToRepay) {
			_savedForBoardRoom = uint256(supplyDelta);
		} else {
			// have not saved enough to pay dept, mint more
			uint256 _seigniorage = uint256(supplyDelta);
			if (
				_seigniorage.mul(bondRepayPercent).div(10000) <=
				_totalBondsToRepay.sub(seigniorageSaved)
			) {
				_savedForBond = _seigniorage.mul(bondRepayPercent).div(10000);
				_savedForBoardRoom = _seigniorage.sub(_savedForBond);
			} else {
				_savedForBond = _totalBondsToRepay.sub(seigniorageSaved);
				_savedForBoardRoom = _seigniorage.sub(_savedForBond);
			}
		}

		if (_savedForBond > 0) {
			uint256 maxAmountForSmartBondPool = IBalanceRebaser(smartBondPool)
				.totalBalance()
				.mul(smartBondDepletionFloorPercent)
				.div(10000);
			uint256 savedForSmartPool = _savedForBond
				.mul(bondRepayToBondSmartPoolPercent)
				.div(10000);

			savedForSmartPool = Math.min(
				savedForSmartPool,
				maxAmountForSmartBondPool
			);
			_savedForBond = _savedForBond.sub(savedForSmartPool);

			seigniorageSaved = seigniorageSaved.add(_savedForBond);
			emit TreasuryFunded(epoch, block.timestamp, _savedForBond);
			IBasisAsset(dollar).mint(
				address(this),
				_savedForBond.add(savedForSmartPool)
			);
			if (savedForSmartPool > 0) {
				IERC20(dollar).approve(smartBondPool, savedForSmartPool);
				ISmartBondPool(smartBondPool).allocateSeigniorage(
					savedForSmartPool
				);
			}
		}

		if (_savedForBoardRoom > 0) {
			_savedForDevs = _savedForBoardRoom.mul(devPercentage).div(10000);
			_savedForBoardRoom = _savedForBoardRoom.sub(_savedForDevs);
			_sendToDevs(_savedForDevs);
		}

		return _savedForBoardRoom;
	}

	function _contractDollar(int256 supplyDelta) private {
		supplyDelta = supplyDelta.mul(contractionIndex).div(10000);
		IBasisAsset(dollar).rebase(epoch, supplyDelta);
	}

	function _sendToDevs(uint256 _amount) internal {
		if (_amount > 0) {
			require(
				IBasisAsset(dollar).mint(devAddress, _amount),
				'Unable to mint for devs'
			);
			emit DevsFunded(epoch, block.timestamp, _amount);
		}
	}

	/**
	 * @notice Sends tokens to the boardroom
	 * @dev This method mints tokens as per need and sends to boardrooms based on allocation
	 * @param _cashAmount The amount of dollar tokens to send
	 * @param _shareAmount The amount of share tokens to send
	 */
	function _sendToBoardRoom(uint256 _cashAmount, uint256 _shareAmount)
		internal
	{
		if (_cashAmount > 0 || _shareAmount > 0) {
			uint256 boardroomCount = IBoardroomAllocation(boardroomAllocation)
				.boardroomInfoLength();

			// mint assets
			if (_cashAmount > 0)
				IBasisAsset(dollar).mint(address(this), _cashAmount);

			if (_shareAmount > 0)
				IBasisAsset(share).mint(address(this), _shareAmount);

			for (uint256 i = 0; i < boardroomCount; i++) {
				(
					address boardroom,
					bool isActive,
					uint256 cashAllocationPoints,
					uint256 shareAllocationPoints
				) = IBoardroomAllocation(boardroomAllocation).boardrooms(i);
				if (isActive) {
					uint256 boardroomCashAmount = _cashAmount
						.mul(cashAllocationPoints)
						.div(
							IBoardroomAllocation(boardroomAllocation)
								.totalCashAllocationPoints()
						);

					uint256 boardroomShareAmount = _shareAmount
						.mul(shareAllocationPoints)
						.div(
							IBoardroomAllocation(boardroomAllocation)
								.totalShareAllocationPoints()
						);

					if (boardroomCashAmount > 0)
						IERC20(dollar).safeApprove(
							boardroom,
							boardroomCashAmount
						);

					if (boardroomShareAmount > 0)
						IERC20(share).safeApprove(
							boardroom,
							boardroomShareAmount
						);

					if (boardroomCashAmount > 0 || boardroomShareAmount > 0) {
						IBoardroom(boardroom).allocateSeigniorage(
							boardroomCashAmount,
							boardroomShareAmount
						);
					}
				}
			}

			emit BoardroomFunded(
				epoch,
				block.timestamp,
				_cashAmount,
				_shareAmount
			);
		}
	}

	/**
	 * @notice Computes the total supply adjustment in response to the exchange rate
	 *         and the targetRate.
	 * @param rate The current token price
	 * @param targetRate The ideal token price
	 * @return Supply to be adjusted
	 */
	function _computeSupplyDelta(uint256 rate, uint256 targetRate)
		private
		view
		returns (int256)
	{
		int256 targetRateSigned = targetRate.toInt256Safe();

		int256 supply = (
			IERC20(dollar)
				.totalSupply()
				.sub(IERC20(dollar).balanceOf(address(this)))
				.sub(boardroomsBalance())
		).toInt256Safe();

		if (rate < targetRate) {
			supply = IBasisAsset(dollar).rebaseSupply().toInt256Safe();
		}
		return
			supply.mul(rate.toInt256Safe().sub(targetRateSigned)).div(
				targetRateSigned
			);
	}

	function boardroomsBalance() private view returns (uint256) {
		uint256 bal = 0;

		uint256 boardroomCount = IBoardroomAllocation(boardroomAllocation)
			.boardroomInfoLength();

		for (uint256 i = 0; i < boardroomCount; i++) {
			(address boardroom, , , ) = IBoardroomAllocation(
				boardroomAllocation
			).boardrooms(i);

			bal = bal.add(IERC20(dollar).balanceOf(boardroom));
		}

		return bal;
	}

	function _notifyEpochChanged() internal {
		for (uint256 i = 0; i < listeners.length; i++) {
			listeners[i].epochUpdate(epoch);
		}
	}
}
