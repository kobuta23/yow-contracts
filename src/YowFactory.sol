pragma solidity ^0.8.20;

import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ISuperToken, ISuperfluid, ISuperApp, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IYoW} from "./interfaces/IYoW.sol";

contract YowFactory {

	UpgradeableBeacon public yowBeacon;
	address public admin;
	ISuperToken public yowToken;


	event BeaconSet(address indexed beacon);
	event AdminSet(address indexed admin);

	mapping(address channel => bool isCreated) internal _channels;

	constructor(ISuperToken yow, address beacon) {
		yowBeacon = new UpgradeableBeacon(beacon);
		yowToken = yow;
		admin = msg.sender;
	}

	function setYoWBeacon(address _beacon) external {
		require(msg.sender == admin, "YowFactory: not admin");
		yowBeacon = UpgradeableBeacon(_beacon);
		emit BeaconSet(_beacon);
	}

	function setAdmin(address _admin) external {
		require(msg.sender == admin, "YowFactory: not admin");
		admin = _admin;
		emit AdminSet(_admin);
	}

	function createYoW(address teamLeaderA, address teamLeaderB) external returns (address YowAddress) {
		require(teamLeaderA != address(0) && teamLeaderB != address(0), "YowFactory: INVALID_ADDRESS");
		require(teamLeaderA != teamLeaderB, "YowFactory: INVALID_TEAM");

		YowAddress = address(new BeaconProxy(address(getBeaconImplementation()), ""));
		IYoW(YowAddress).initialize(yowToken, teamLeaderA, teamLeaderB);

		// register as super app
		ISuperfluid host = ISuperfluid(yowToken.getHost());
		uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL | SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP | SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;
		host.registerAppByFactory(ISuperApp(YowAddress), configWord);
	}

	function getBeaconImplementation() public view returns (address) {
		return yowBeacon.implementation();
	}
}