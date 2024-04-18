// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/YoW.sol";
import "../src/MintableSuperToken.sol";

import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperApp.sol";
import "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

interface IMint {
    function initialize(address factory, string memory _name, string memory _symbol) external;
    function mint(address to, uint256 amount) external;
}

contract DeployYoW is Script {
    address internal constant admin = address(0x476E2651BF97dE8a26e4A05a9c8e00A6EFa1390c); // has to be this address
    address internal constant alice = address(0x420);
    address internal constant bob = address(0x421);

    function setUp() public {}

    function run() public {
        vm.startBroadcast(admin);

        // Create token
        address STFactory = 0x36be86dEe6BC726Ed0Cbd170ccD2F21760BC73D9; //celo
        ISuperToken yoink = ISuperToken(address(new MintableSuperToken()));
        IMint mint = IMint(address(yoink));
        console.log("Deployed yoink: ", address(yoink));
        mint.initialize(STFactory, "yoink", "yoink");
        console.log("Initialized yoink");


        console.log("-----");
        console.log("Deploying Factory: Beacon");
        address yowBeacon = address(new UpgradeableBeacon(address(new YoW(host))));
        console.log("deployed yowBeacon: ", yowBeacon);

        // deploy yowFactory
        console.log("Deploying Factory: Factory");
        YowFactory yowFactory = new YowFactory(yoink, yowBeacon);
        console.log("deployed yowFactory: ", address(yowFactory));

        // deploy yow
        console.log("Deploying YoW");
        yow = YoW( yowFactory.createYoW(alice, bob) );
        console.log("deployed yow: ", address(yow));

        vm.stopBroadcast();
    }
}
