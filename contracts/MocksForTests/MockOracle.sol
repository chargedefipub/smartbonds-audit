pragma solidity 0.8.4;
import '../Interfaces/IOracle.sol';

contract MockOracle is IOracle {
	function update() public override {}

	function consult(address token, uint256 amountIn)
		external
		view
		override
		returns (uint256 amountOut)
	{
		return price;
	}

	uint256 private price = 10**18;

	function setPrice(uint256 price_) external {
		price = price_;
	}
}
