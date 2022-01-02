pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '../Interfaces/IMintableToken.sol';

contract MockToken is ERC20Burnable, IMintableToken {
	/**
	 * @notice Constructs the MockToken ERC-20 contract.
	 */
	constructor(string memory name_, string memory symbol_)
		ERC20(name_, symbol_)
	{}

	/**
	 * @param recipient_ The address of recipient
	 * @param amount_ The amount of basis bonds to mint to
	 * @return whether the process has been done
	 */
	function mint(address recipient_, uint256 amount_)
		external
		override
		returns (bool)
	{
		uint256 balanceBefore = balanceOf(recipient_);
		_mint(recipient_, amount_);
		uint256 balanceAfter = balanceOf(recipient_);

		return balanceAfter > balanceBefore;
	}
}
