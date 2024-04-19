pragma solidity ^0.8.20;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

interface IYoW {

	struct Team {
		address leader;
		bool isWinning;
		address z;
	}

	function initialize(ISuperToken yoinkToken, address teamLeaderA, address teamLeaderB) external;
	function timeToEnd() external view returns (uint256);
	function winningTeam() external view returns (Team memory);
	function losingTeam() external view returns (Team memory);
	function gameCanEnd() external view returns (bool);
	function getFlowRate(address account) external view returns (int128);
	function balanceOf(address account) external view returns (uint256);
	function balanceOfAt(address account, uint timestamp) external view returns (uint256);
	function isUserBanned(address user) external view returns (bool);


}