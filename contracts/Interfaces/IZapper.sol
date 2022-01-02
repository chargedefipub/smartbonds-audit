// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

/**
 *
 */
interface IZapper {
	/**
	 * Create LP (_to) from BNB
	 */
	function zapBNBToLP(address _to) external payable;

	/**
	 * Creates LP (_to) from a single asset (_from). Use this when the _from asset is not BNB
	 */
	function zapTokenToLP(
		address _from,
		uint256 amount,
		address _to
	) external;

	/**
	 * Breaks LP (_from) and returns the single assets to the sender
	 */
	function breakLP(address _from, uint256 amount) external;
}
