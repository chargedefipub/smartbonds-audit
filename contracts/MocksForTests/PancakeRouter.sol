// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import 'hardhat/console.sol';

contract PancakeRouter {
	address public immutable WETH;
	address public immutable LP;

	constructor(address _WETH, address _LP) {
		WETH = _WETH;
		LP = _LP;
	}

	struct ExactTokensSwapInfo {
		uint256 amountIn;
		uint256 amountOutMin;
		address[] path;
		address to;
		uint256 deadline;
		address tokenA;
		address tokenB;
		uint256 amountADesired;
		uint256 amountBDesired;
		uint256 amountAMin;
		uint256 amountBMin;
		// token to token = 1
		// token to eth = 2
		// eth to token = 3
		// tokens to lp = 4
		uint256 swapType;
	}

	uint256 public numExactTokensSwapInfoCalls = 0;
	mapping(uint256 => ExactTokensSwapInfo) public exactTokensSwapInfo;

	function swapExactTokensForTokensSupportingFeeOnTransferTokens(
		uint256 amountIn,
		uint256 amountOutMin,
		address[] calldata path,
		address to,
		uint256 deadline
	) external virtual {
		IERC20(path[0]).transferFrom(
			address(msg.sender),
			address(this),
			amountIn
		);

		ExactTokensSwapInfo storage info = exactTokensSwapInfo[
			numExactTokensSwapInfoCalls++
		];
		info.amountIn = amountIn;
		info.amountOutMin = amountOutMin;
		info.path = path;
		info.to = to;
		info.deadline = deadline;
		info.swapType = 1;

		IERC20(path[path.length - 1]).transfer(to, amountIn);
	}

	function getAmountsOut(uint256 amountIn, address[] calldata path)
		external
		view
		returns (uint256[] memory amounts)
	{
		amounts = new uint256[](path.length);
		for (uint256 i; i < path.length; i++) {
			amounts[i] = amountIn;
		}
	}

	function swapExactTokensForETHSupportingFeeOnTransferTokens(
		uint256 amountIn,
		uint256 amountOutMin,
		address[] calldata path,
		address to,
		uint256 deadline
	) external {
		IERC20(path[0]).transferFrom(
			address(msg.sender),
			address(this),
			amountIn
		);

		ExactTokensSwapInfo storage info = exactTokensSwapInfo[
			numExactTokensSwapInfoCalls++
		];
		info.amountIn = amountIn;
		info.amountOutMin = amountOutMin;
		info.path = path;
		info.to = to;
		info.deadline = deadline;
		info.swapType = 2;

		payable(msg.sender).transfer(amountIn);
	}

	function swapExactETHForTokensSupportingFeeOnTransferTokens(
		uint256 amountOutMin,
		address[] calldata path,
		address to,
		uint256 deadline
	) external payable {
		ExactTokensSwapInfo storage info = exactTokensSwapInfo[
			numExactTokensSwapInfoCalls++
		];
		info.amountIn = msg.value;
		info.amountOutMin = amountOutMin;
		info.path = path;
		info.to = to;
		info.deadline = deadline;
		info.swapType = 3;

		IERC20(path[path.length - 1]).transfer(to, msg.value);
	}

	function addLiquidity(
		address tokenA,
		address tokenB,
		uint256 amountADesired,
		uint256 amountBDesired,
		uint256 amountAMin,
		uint256 amountBMin,
		address to,
		uint256 deadline
	)
		external
		returns (
			uint256 amountA,
			uint256 amountB,
			uint256 liquidity
		)
	{
		IERC20(tokenA).transferFrom(
			address(msg.sender),
			address(this),
			amountADesired
		);

		IERC20(tokenB).transferFrom(
			address(msg.sender),
			address(this),
			amountBDesired
		);

		ExactTokensSwapInfo storage info = exactTokensSwapInfo[
			numExactTokensSwapInfoCalls++
		];
		info.tokenA = tokenA;
		info.tokenB = tokenB;
		info.amountADesired = amountADesired;
		info.amountBDesired = amountBDesired;
		info.to = to;
		info.deadline = deadline;
		info.swapType = 4;

		IERC20(LP).transfer(to, amountADesired + amountBDesired);

		return (
			amountADesired,
			amountBDesired,
			amountADesired + amountBDesired
		);
	}

	function exactTokensSwapPath(uint256 index)
		external
		view
		returns (address[] memory)
	{
		return exactTokensSwapInfo[index].path;
	}

	receive() external payable {}
}
