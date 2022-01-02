// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';

contract WBNB is ERC20Burnable {
	/**
	 * @notice Constructs the Bat True Bond ERC-20 contract.
	 */
	constructor() ERC20('WBNB', 'WBNB') {}

	/**
	 * @notice Operator mints basis bonds to a recipient
	 * @param recipient_ The address of recipient
	 * @param amount_ The amount of basis bonds to mint to
	 * @return whether the process has been done
	 */
	function mint(address recipient_, uint256 amount_) external returns (bool) {
		uint256 balanceBefore = balanceOf(recipient_);
		_mint(recipient_, amount_);
		uint256 balanceAfter = balanceOf(recipient_);

		return balanceAfter > balanceBefore;
	}

	function burn(uint256 amount) public override {
		super.burn(amount);
	}

	function burnFrom(address account, uint256 amount) public override {
		super.burnFrom(account, amount);
	}
}
