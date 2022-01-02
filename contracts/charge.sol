// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './Interfaces/IMintableToken.sol';
import './Interfaces/IShare.sol';

contract Charge is ERC20Burnable, AccessControlEnumerable, IShare {
	using SafeMath for uint256;

	uint256 public maxCap;
	bytes32 private constant _minterRole = keccak256('minterrole');

	mapping(address => uint256) private _mintLimit;
	mapping(address => uint256) private _mintedAmount;

	event MinterRegistered(address indexed account, uint256 mintLimit);
	event MinterUpdated(
		address indexed account,
		uint256 oldLimit,
		uint256 mintLimit
	);
	event MinterRemoved(address indexed account);
	event NewMaxCap(uint256 newMaxCap);

	/**
	 * @notice Constructs the Bat True Bond ERC-20 contract.
	 */
	constructor(uint256 _maxCap) ERC20('Charge', 'Charge') {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		maxCap = _maxCap;
	}

	/**
	 * @notice Operator mints basis bonds to a recipient
	 * @param recipient_ The address of recipient
	 * @param amount_ The amount of basis bonds to mint to
	 * @return whether the process has been done
	 */
	function mint(address recipient_, uint256 amount_)
		external
		override
		onlyRole(_minterRole)
		returns (bool)
	{
		require(totalSupply().add(amount_) <= maxCap, 'Exceeds max cap');

		uint256 newMintTotalForMinter = _mintedAmount[_msgSender()].add(
			amount_
		);
		require(
			newMintTotalForMinter <= _mintLimit[_msgSender()],
			'Exceeds minter limit'
		);

		uint256 balanceBefore = balanceOf(recipient_);
		_mint(recipient_, amount_);
		uint256 balanceAfter = balanceOf(recipient_);

		_mintedAmount[_msgSender()] = newMintTotalForMinter;
		return balanceAfter > balanceBefore;
	}

	function burn(uint256 amount) public override {
		super.burn(amount);
	}

	function burnFrom(address account, uint256 amount) public override {
		super.burnFrom(account, amount);
	}

	function registerMinter(address minter_, uint256 amount_)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(amount_ > 0, '=0');
		require(_mintLimit[minter_] == 0, 'minter already exists');
		require(
			_mintedAmount[minter_] <= amount_,
			'minted amount more than amount'
		);

		_mintLimit[minter_] = amount_;
		grantRole(_minterRole, minter_);

		emit MinterRegistered(minter_, amount_);
	}

	function updateMinter(address minter_, uint256 amount_)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(amount_ > 0, '=0');
		require(_mintLimit[minter_] > 0, 'minter does not exist');
		require(
			_mintedAmount[minter_] <= amount_,
			'minted amount more than amount'
		);

		uint256 oldLimit = _mintLimit[minter_];

		_mintLimit[minter_] = amount_;

		emit MinterUpdated(minter_, oldLimit, amount_);
	}

	function removeMinter(address minter_)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		_mintLimit[minter_] = 0;
		revokeRole(_minterRole, minter_);

		emit MinterRemoved(minter_);
	}

	function updateMaxCap(uint256 maxCap_)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(maxCap_ >= totalSupply(), 'max cap must more than minted');
		maxCap = maxCap_;
		emit NewMaxCap(maxCap);
	}

	function mintLimitOf(address minter_)
		external
		view
		override
		returns (uint256)
	{
		return _mintLimit[minter_];
	}

	function mintedAmountOf(address minter_)
		external
		view
		override
		returns (uint256)
	{
		return _mintedAmount[minter_];
	}

	function canMint(address minter_, uint256 amount_)
		external
		view
		override
		returns (bool)
	{
		return
			(totalSupply().add(amount_) <= maxCap) &&
			(_mintedAmount[minter_].add(amount_) <= _mintLimit[minter_]);
	}
}
