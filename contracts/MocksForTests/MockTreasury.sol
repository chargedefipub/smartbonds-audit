pragma solidity 0.8.4;

import '../Interfaces/ITreasury.sol';

contract MockTreasury is ITreasury {

	constructor()
	{
		period = 100000;
		_epoch = 1;
		_nextEpochPoint = 200000;
		_dollarPrice = 1e18 * 2;
	}

	uint256 private period;

	function setPeriod(uint256 period_) public
	{
		period = period_;
	}
	function PERIOD() external override view returns (uint256)
	{
		return period;
	}


	uint256 private _epoch;
	function setEpoch(uint256 epoch_) public
	{
		_epoch = epoch_;
	}

	function epoch() external view override returns (uint256)
	{
		return _epoch;
	}

	uint256 private _nextEpochPoint;
	function setNextEpochPoint(uint256 nextEpochPoint_) public 
	{
		_nextEpochPoint = nextEpochPoint_;
	}

	function nextEpochPoint() external override view returns (uint256)
	{ 
		return _nextEpochPoint;
	}

	uint256 private _dollarPrice;
	function setDollarPrice(uint256 dollarPrice_) public 
	{
		_dollarPrice = dollarPrice_;
	}
	function getDollarPrice() external override view returns (uint256)
	{ 
		return _dollarPrice;
	}
}