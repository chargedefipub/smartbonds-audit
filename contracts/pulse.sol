// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import './Interfaces/IMintableToken.sol';

contract Pulse is ERC20Burnable, AccessControlEnumerable, IMintableToken {
	bytes32 public constant minterRole = keccak256('minterrole');

	/**
	 * @notice Constructs the Pulse ERC-20 contract.
	 */
	constructor() ERC20('Pulse', 'Pulse') {
		_setupRole(minterRole, msg.sender);
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
		onlyRole(minterRole)
		returns (bool)
	{
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
