pragma solidity ^0.5.4;

import './DSLibrary/DSAuth.sol';
import './interface/ITargetHandler.sol';
import './interface/IERC20.sol';

interface IFund {
	function transferOut(address _tokenID, address _to, uint amount) external returns (bool);
}

interface DFToken {
	function getDecimals() external returns (uint256);
}

library DSMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
}

contract Dispatcher is DSAuth {
	using DSMath for uint256;

	address public token;
	address public profitBeneficiary;
	address public fundPool;
	TargetHandler[] public ths;
	uint256 public reserveUpperLimit;
	uint256 public reserveLowerLimit;
	uint256 public executeUnit;

	struct TargetHandler {
		address targetHandlerAddr;
		address targetAddr;
		uint256 aimedPropotion;
	}

	constructor (address _tokenAddr, address _fundPool, address[] memory _thAddr, uint256[] memory _thPropotion) public {
		owner = msg.sender;
		token = _tokenAddr;
		fundPool = _fundPool;
		require(_thAddr.length == _thPropotion.length, "wrong length");
		uint256 sum = 0;
		uint256 i;
		for(i = 0; i < _thAddr.length; ++i) {
			sum = sum.add(_thPropotion[i]);
		}
		require(sum == 1000, "the sum of propotion must be 1000");
		for(i = 0; i < _thAddr.length; ++i) {
			ths.push(TargetHandler(_thAddr[i], ITargetHandler(_thAddr[i]).getTargetAddress(), _thPropotion[i]));
		}
		executeUnit = (10 ** 18) / 10; //0.1

		// set up the default limit 
		reserveUpperLimit = 350; // 350 / 1000 = 0.35
		reserveLowerLimit = 300; // 300 / 1000 = 0.3 
	}

	function trigger () external {
		uint256 reserve = getReserve();
		uint256 reserveMax = reserveUpperLimit * getBalance() / 1000;
		uint256 reserveMin = reserveLowerLimit * getBalance() / 1000;
		uint256 amounts;
		if (reserve > reserveMax) {
			amounts = reserve - reserveMax;
			amounts = amounts / executeUnit * executeUnit;
			if (amounts != 0) {
				internalDeposit(amounts);	
			}			
		} else if (reserve < reserveMin) {
			amounts = reserveMin - reserve;
			amounts = amounts / executeUnit * executeUnit;
			if (amounts != 0) {
				withdrawPrinciple(amounts);	
			} 			
		}
	}

	function internalDeposit (uint256 _amounts) internal {
		uint256 i;
		uint256 amountsToTH;
		uint256 thCurrentBalance;
		uint256 amountsToSatisfiedAimedPropotion;
		uint256 totalPrincipleAfterDeposit = getPrinciple().add(_amounts);
		TargetHandler memory _th;
		for(i = 0; i < ths.length; ++i) {
			_th = ths[i];
			amountsToTH = 0;
			thCurrentBalance = getTHPrinciple(i);
			amountsToSatisfiedAimedPropotion = totalPrincipleAfterDeposit.mul(_th.aimedPropotion) / 1000;
			if (thCurrentBalance > amountsToSatisfiedAimedPropotion) {
				continue;
			} else {
				amountsToTH = amountsToSatisfiedAimedPropotion - thCurrentBalance;
				if (amountsToTH > _amounts) {
					amountsToTH = _amounts;
					_amounts = 0;
				} else {
					_amounts -= amountsToTH;
				}
				require(IFund(fundPool).transferOut(token, _th.targetHandlerAddr, amountsToTH));
				ITargetHandler(_th.targetHandlerAddr).trigger();
			}
		}	
	}

	function withdrawPrinciple (uint256 _amounts) internal {
		uint256 i;
		uint256 amountsFromTH;
		uint256 thCurrentBalance;
		uint256 amountsToSatisfiedAimedPropotion;
		uint256 totalBalanceAfterWithdraw = getPrinciple().sub(_amounts);
		TargetHandler memory _th;
		for(i = 0; i < ths.length; ++i) {
			_th = ths[i];
			amountsFromTH = 0;
			thCurrentBalance = getTHBalance(i);
			amountsToSatisfiedAimedPropotion = totalBalanceAfterWithdraw.mul(_th.aimedPropotion) / 1000;
			if (thCurrentBalance < amountsToSatisfiedAimedPropotion) {
				continue;
			} else {
				amountsFromTH = thCurrentBalance - amountsToSatisfiedAimedPropotion;
				if (amountsFromTH > _amounts) {
					amountsFromTH = _amounts;
					_amounts = 0;
				} else {
					_amounts -= amountsFromTH;
				}
				ITargetHandler(_th.targetHandlerAddr).withdraw(amountsFromTH);
			}
		}
	}

	function withdrawProfit () external {
		uint256 i;
		TargetHandler memory _th;
		for(i = 0; i < ths.length; ++i) {
			_th = ths[i];
			ITargetHandler(_th.targetHandlerAddr).withdrawProfit(profitBeneficiary);
		}		
	}

	// getter function 
	function getReserve() view public returns (uint256) {
		return IERC20(token).balanceOf(fundPool);
	}

	function getReserveRatio() view public returns (uint256) {
		uint256 fraction = getReserve();
		uint256 denominator = getPrinciple().add(fraction);
		if (denominator == 0) {
			return 0;
		} else {
			return fraction * 1000 / denominator;
		}
	}

	function getPrinciple() view public returns (uint256 result) {
		TargetHandler memory _th;
		result = 0;
		for(uint256 i = 0; i < ths.length; ++i) {
			_th = ths[i];
			result = result.add(getTHPrinciple(i));
		}	
	}

	function getBalance() view public returns (uint256 result) {
		TargetHandler memory _th;
		result = 0;
		for(uint256 i = 0; i < ths.length; ++i) {
			_th = ths[i];
			result = result.add(getTHBalance(i));
		}
	}

	function getProfit() view public returns (uint256) {
		return getBalance().sub(getPrinciple());
	}

	function getTHPrinciple(uint256 _index) view public returns (uint256) {
		return ITargetHandler(ths[_index].targetHandlerAddr).getPrinciple();
	}

	function getTHBalance(uint256 _index) view public returns (uint256) {
		return ITargetHandler(ths[_index].targetHandlerAddr).getBalance();
	}

	function getTHProfit(uint256 _index) view public returns (uint256) {
		return ITargetHandler(ths[_index].targetHandlerAddr).getProfit();
	}

	// owner function 
	function setAimedPropotion(uint256[] memory _thPropotion) public onlyOwner {
		require(ths.length == _thPropotion.length);
		uint256 sum = 0;
		uint256 i;
		TargetHandler memory _th;
		for(i = 0; i < _thPropotion.length; ++i) {
			sum += _thPropotion[i];
		}
		require(sum == 1000, "the sum of propotion must be 1000");
		for(i = 0; i < _thPropotion.length; ++i) {
			_th = ths[i];
			_th.aimedPropotion = _thPropotion[i];			
			ths[i] = _th;
		}
	}

	function removeTargetHandler(address _targetHandlerAddr, uint256 _index) external onlyOwner {
		uint256 length = ths.length;
		require(length != 1, "can not remove the last target handler");
		require(_index < length, "not the correct index");
		require(ths[_index].targetHandlerAddr == _targetHandlerAddr, "not the correct index or address");
		require(getTHBalance(_index) == 0, "must drain all balance in the target handler");
		ths[_index] = ths[length - 1];
		ths.length --;
	}

	function addTargetHandler(address _targetHandlerAddr) external onlyOwner {
		uint256 length = ths.length;
		TargetHandler memory _th;
		for(uint256 i = 0; i < length; ++i) {
			_th = ths[i];
			require(_th.targetHandlerAddr != _targetHandlerAddr, "exist target handler");
		}
		ths.push(TargetHandler(_targetHandlerAddr, ITargetHandler(_targetHandlerAddr).getTargetAddress(), 0));		
	}

	function setReserveUpperLimit(uint256 _number) external onlyOwner {
		require(_number > reserveLowerLimit);
		reserveUpperLimit = _number;
	}

	function setReserveLowerLimit(uint256 _number) external onlyOwner {
		require(_number < reserveUpperLimit);
		reserveLowerLimit = _number;
	}

	function setExecuteUnit(uint256 _number) external onlyOwner {
		executeUnit = _number;
	}
}