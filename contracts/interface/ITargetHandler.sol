pragma solidity ^0.5.4;

interface ITargetHandler {
	function trigger() external; // trigger token deposit 
	function withdraw(uint256 _amounts) external;
	function withdrawProfit(address _beneficiary) external;
	function getBalance() view external returns (uint256);
	function getPrinciple() view external returns (uint256);
	function getProfit() view external returns (uint256);
	function getTargetAddress() view external returns (address);
	function getToken() view external returns (address);
	function getDispatcher() view external returns (address);
}