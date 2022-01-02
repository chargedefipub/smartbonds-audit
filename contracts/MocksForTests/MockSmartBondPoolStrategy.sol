pragma solidity 0.8.4;
import '../Interfaces/IBoardroom.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../Interfaces/IStrategy.sol';
import '../Interfaces/IMintableToken.sol';
import '../SmartBond/ISmartBondStrategy.sol';

contract MockSmartBondPoolStrategy is ISmartBondStrategy {
	IERC20 public override stakedToken;
	IERC20 public override earnedToken;
	uint256 public yield;
	address public earnerAddress;

	constructor(
		IERC20 _earnedToken,
		uint256 _yield,
		address _earnerAddress
	) {
		earnedToken = _earnedToken;
		yield = _yield;
		earnerAddress = _earnerAddress;
	}

	function setYield(uint256 _yield) external {
		yield = _yield;
	}

	// Total staked tokens managed by strategy
	function stakedLockedTotal() external view override returns (uint256) {
		return 0;
	}

	function earn() external override {
		IMintableToken(address(earnedToken)).mint(earnerAddress, yield);
	}

	function deposit(uint256 _amount) external override returns (uint256) {
		return 0;
	}

	function withdraw(uint256 _amount) external override returns (uint256) {
		return 0;
	}

	function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount)
		external
		override
	{}

	function stakedTokenPrice() external view override returns (uint256) {
		return 0;
	}

	function pendingEarned() external view override returns (uint256) {
		return yield;
	}
}
