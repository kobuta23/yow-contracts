// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/YoW.sol";
import {MintableSuperToken} from "../src/MintableSuperToken.sol";
import {
    BatchOperation,
    ISuperfluid
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperApp} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperApp.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {ERC1820RegistryCompiled} from
    "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

interface IMint {
    function initialize(address factory, string memory _name, string memory _symbol) external;
    function mint(address to, uint256 amount) external;
}

struct Team {
    address leader;
    bool isWinning;
}

contract YOWTest is Test {
    using SuperTokenV1Library for ISuperToken;

    YoW yow;
    ISuperToken yoink;
    IMint mint;

    address internal constant admin = address(0x476E2651BF97dE8a26e4A05a9c8e00A6EFa1390c); // has to be this address
    address internal constant alice = address(0x420);
    address internal constant bob = address(0x421);
    address internal constant charlie = address(0x422);
    address internal constant daniel = address(0x423);
    address internal constant emily = address(0x424);
    address internal constant flo = address(0x425);
    address internal constant gemma = address(0x426);
    address internal constant hillary = address(0x427);
    address[8] users = [alice, bob, charlie, daniel, emily, flo, gemma, hillary];
    string[8] names = ["alice", "bob", "charlie", "daniel", "emily", "flo", "gemma", "hillary"];
    // mapping of address to name
    function nameOf(address user) internal view returns (string memory){
        for(uint256 i = 0; i < users.length; i++) {
            if(users[i] == user) return names[i];
        }
        return "unknown";
    }

    function setUp() public {

        //create token
        address STFactory = 0x36be86dEe6BC726Ed0Cbd170ccD2F21760BC73D9; //celo
        //BASE 0xe20B9a38E0c96F61d1bA6b42a61512D56Fea1Eb3;

        vm.startPrank(admin);
        yoink = ISuperToken(address(new MintableSuperToken()));
        mint = IMint(address(yoink));
        console.log("deployed yoink: ", address(yoink));
        mint.initialize(STFactory, "yoink", "yoink");
        console.log("initialize yoink");
        
        yow = new YoW(yoink, alice, bob);
        console.log("deployed yow: ", address(yow));
    }

    function dealTo(address to) internal {
        vm.startPrank(admin);
        mint.mint(to, 1e20 ether);
        vm.stopPrank();
    }

    function testStartStreamToGame() public {
        int96 flowRate = 1e12;
        //flowRate = int96(int256(bound(uint256(int256(flowRate)), 1, 1e14)));
        dealTo(alice);
        vm.startPrank(alice);
        
        uint256 balanceBefore = yoink.balanceOf(alice);
        uint256 balanceAppBefore = yoink.balanceOf(address(yow));
        yoink.createFlow(address(yow), flowRate);
        vm.stopPrank();
        uint256 timeshift = 100;
        vm.warp(block.timestamp + timeshift);
        uint256 balanceAfter = yoink.balanceOf(alice);
        uint256 balanceAppAfter = yoink.balanceOf(address(yow));
        console.log("balanceBefore: ", balanceBefore);
        console.log("balanceAfter: ", balanceAfter);
        console.log("balanceAppBefore: ", balanceAppBefore);
        console.log("balanceAppAfter: ", balanceAppAfter);
        assertEq(balanceAppAfter, uint256(int256(flowRate)) * timeshift);
        assertEq(balanceAppAfter, yow.balanceOf(alice));
    } 

    function testStreamWinningCondition() public {
        int96 aliceFlowRate = int96(1e6);
        int96 bobFlowRate = int96(2e6+1); // Bob streams at a higher rate

        dealTo(alice);
        dealTo(bob);

        vm.startPrank(alice);
        yoink.createFlow(address(yow), aliceFlowRate);
        vm.stopPrank();

        vm.startPrank(bob);
        yoink.createFlow(address(yow), bobFlowRate);
        vm.stopPrank();

        uint256 fourHours = 4 hours + 1 seconds;
        vm.warp(block.timestamp + fourHours);

        (,bool teamAWinning,) = yow.teamA();
        (,bool teamBWinning,) = yow.teamB();
        console.log("gameEnded: ", Time.unwrap(yow.gameEnded()));
        assertFalse(Time.unwrap(yow.gameEnded()) > 0, "GameEnded variable larger than zero");
        assertTrue(yow.gameCanEnd(), "Game should have ended after 4 hours");
        assertFalse(teamAWinning, "Team A should not be winning");
        assertTrue(teamBWinning, "Team B should be winning");

        // Alice closes her stream
        vm.startPrank(alice);
        yoink.deleteFlow(alice, address(yow));
        vm.stopPrank();
        console.log("check if app was jailed");
        console.log(ISuperfluid(yoink.getHost()).isAppJailed(ISuperApp(address(yow))));

        console.log("gameEnded: ", Time.unwrap(yow.gameEnded()));

        assertTrue(Time.unwrap(yow.gameEnded()) > 0, "Game should have ended after Alice closes her stream post 4 hours");
    }

    function testCharlieShiftsBalanceToAliceOnStreamClose() public {
        int96 aliceFlowRate = int96(1e6);
        int96 bobFlowRate = int96(2e6 +1);
        int96 charlieFlowRate = int96(3e6); // Charlie streams at the highest rate

        dealTo(alice);
        dealTo(bob);
        dealTo(charlie);

        vm.startPrank(alice);
        yoink.createFlow(address(yow), aliceFlowRate);
        vm.stopPrank();

        vm.startPrank(bob);
        yoink.createFlow(address(yow), bobFlowRate);
        vm.stopPrank();

        vm.startPrank(charlie);
        yoink.createFlow(address(yow), charlieFlowRate);
        vm.stopPrank();

        uint256 twoHours = 2 hours + 1 seconds;
        vm.warp(block.timestamp + twoHours);

        // Charlie closes his stream before the game ends
        vm.startPrank(charlie);
        yoink.deleteFlow(charlie, address(yow));
        vm.stopPrank();

        uint256 balanceAliceAfter = yow.balanceOf(alice);
        uint256 balanceCharlieAfter = yow.balanceOf(charlie);

        console.log("balanceAliceAfter: ", balanceAliceAfter);
        console.log("balanceCharlieAfter: ", balanceCharlieAfter);

        assertTrue(balanceCharlieAfter == 0, "Charlie's balance should be 0 after closing the stream");
        assertTrue(balanceAliceAfter > 0, "Alice's balance should increase after Charlie closes his stream");
    }

    function testStreamDropoutBeforeGameCanEnd() public {
        int96 aliceFlowRate = int96(1e6);
        int96 bobFlowRate = int96(1e6+1);

        dealTo(alice);
        dealTo(bob);

        vm.startPrank(alice);
        yoink.createFlow(address(yow), aliceFlowRate);
        vm.stopPrank();

        vm.startPrank(bob);
        yoink.createFlow(address(yow), bobFlowRate);
        vm.stopPrank();

        uint256 oneHour = 1 hours;
        vm.warp(block.timestamp + oneHour);

        // Alice or Bob drops out before game can end
        vm.startPrank(alice);
        yoink.deleteFlow(alice, address(yow));
        vm.stopPrank();

        // Check if revert happens as expected
        bool end = yow.gameCanEnd();
        console.log("Game can end: ", end);
        console.log("balance of alice: ", yow.balanceOf(alice));
        console.log("balance of bob: ", yow.balanceOf(bob));

        console.log("Test passed: Stream dropout before game can end doesn't revert");
    }


    function testFail_NonLeaderStartGameRevert() public {
        dealTo(charlie);
        vm.startPrank(charlie);
        int96 flowRate = int96(1e6);
        //vm.expectRevert();\
        yoink.createFlow(address(yow), flowRate);
    
        vm.stopPrank();
    }

    function testFail_UserAlreadyHadAStream() public {
        int96 aliceFlowRate = int96(1e6);
        int96 bobFlowRate = int96(2e6);
        int96 charlieFlowRate = int96(3e6); // Charlie streams at the highest rate

        dealTo(alice);
        dealTo(bob);
        dealTo(charlie);

        vm.startPrank(alice);
        yoink.createFlow(address(yow), aliceFlowRate);
        vm.stopPrank();

        vm.startPrank(bob);
        yoink.createFlow(address(yow), bobFlowRate);
        vm.stopPrank();

        vm.startPrank(charlie);
        yoink.createFlow(address(yow), charlieFlowRate);
        vm.stopPrank();

        uint256 oneHour = 1 hours;
        vm.warp(block.timestamp + oneHour);

        // Charlie closes his stream
        vm.startPrank(charlie);
        yoink.deleteFlow(charlie, address(yow));
        vm.stopPrank();

        // Charlie reopens his stream
        vm.startPrank(charlie);
        yoink.createFlow(address(yow), charlieFlowRate);
        vm.stopPrank();
    }

    function testPayouts() public {
        int96 r1 = int96(1e13);
        int96 r2 = int96(1e13)+1;
        int96 r3 = int96(1e13);
        int96 r4 = int96(1e13)+1;
        int96 r5 = int96(1e13);
        address[5] memory users = [alice, bob, charlie, daniel, emily];
        int96[5] memory flowRates = [r1, r2, r3, r4, r5];
        
        uint256 randomWarpTime = 45 minutes;

        dealTo(users[0]);
        vm.startPrank(users[0]);
        yoink.createFlow(address(yow), flowRates[0]);
        vm.stopPrank();
        dealTo(users[1]);
        vm.startPrank(users[1]);
        yoink.createFlow(address(yow), flowRates[1]);
        vm.stopPrank();
        // Randomly warp time between stream creations
        uint256 t0 = block.timestamp;
        uint256 t1 = t0 + randomWarpTime;
        vm.warp(t0 + randomWarpTime);

        // Create streams for each user
        for(uint i = 2; i < users.length; i++) {
            dealTo(users[i]);
            vm.startPrank(users[i]);
            yoink.createFlow(address(yow), flowRates[i]);
            vm.stopPrank();
            // Randomly warp time between stream creations
            vm.warp(block.timestamp + randomWarpTime);
            if(yow.winningTeam().z == address(0x0)) {
                console.log("Team A is winning");
            } else {
                console.log("Team B is winning");
            }
            console.log("Time to end: ", yow.timeToEnd());
        }

        console.log("all players are in the game. Now we can fast forward, and check payouts");
        // Warp enough time for the game to end
        console.log("calc inputs");
        console.log(yow.winningCountdownStart());
        console.log(yow.winningThreshold());
        vm.warp(t1 + 4 hours + 1);
        console.log("now the game should be able to end:");
        console.log(yow.gameCanEnd());
        // Log everyone's balances
        for(uint i = 0; i < users.length; i++) {
            uint256 balance = yow.balanceOf(users[i]);
            console.log(nameOf(users[i]), "'s\t in app credit:\t", balance/1e12);
        }
        for(uint i = 0; i < users.length; i++) {
            uint256 balanceOfToken = yoink.balanceOf(users[i]);
            console.log(nameOf(users[i]), "'s\t token balance:\t", balanceOfToken/1e12);
        }
        for(uint i = 0; i < users.length; i++) {
            int96 flowRate = yoink.getFlowRate(users[i], address(yow));
            int128 internalFlowRate = yow.getFlowRate(users[i]);
            console.log("external and internal flowrates for", nameOf(users[i]));
            console2.log(flowRate);
            console2.log(internalFlowRate);
        }
        // before closing user balances, we should try and guess what is gonna happen
        // check how much each user should get and then check if they get it 
        uint256 balanceOfAppBefore = yoink.balanceOf(address(yow));
        console.log("balanceOfAppBefore:\t", balanceOfAppBefore/1e12);
        console.log("app gameEndTime:\t", Time.unwrap(yow.gameEnded()));

        for (uint i = 0; i < users.length; i++) {
            // Close one user's stream and calculate if they get enough
            console.log("CLOSING STREAM FOR %s", nameOf(users[i]));
            vm.startPrank(users[i]);
            yoink.deleteFlow(users[i], address(yow));
            vm.stopPrank();

            assertTrue(!ISuperfluid(yoink.getHost()).isAppJailed(ISuperApp(address(yow))));

            uint256 balanceAfterClosing = yoink.balanceOf(users[i]);
            console.log(nameOf(users[i]), "'s\t balance after closing stream:\t", balanceAfterClosing/1e12);
            vm.warp(block.timestamp + 10000);
        }
        uint256 balanceOfAppAfter = yoink.balanceOf(address(yow));
        console.log("balanceOfAppAfter:\t", balanceOfAppAfter);
        console.log("app gameEndTime:\t", Time.unwrap(yow.gameEnded()));
        console.log("check if app was jailed");
        console.log(ISuperfluid(yoink.getHost()).isAppJailed(ISuperApp(address(yow))));
    }

    struct Action {
        uint8 who;
        uint80 flowRate;
        uint16 dt;
    }

    function testFuzzShit(uint80 r1, uint80 r2, Action[8] memory actions) public {
        dealTo(users[0]);
        vm.startPrank(users[0]);
        yoink.createFlow(address(yow), int96(uint96(r1)) / 2 * 2 + 2);
        vm.stopPrank();

        dealTo(users[1]);
        vm.startPrank(users[1]);
        yoink.createFlow(address(yow), int96(uint96(r2)) / 2 * 2 + 1);
        vm.stopPrank();

        for (uint i = 0; i < actions.length; i++) {
            Action memory action = actions[i];
            // in this test case we exclude further actions from alice and bob. write another test case for those cases.
            address tester = users[action.who % (users.length - 2) + 2];
            dealTo(tester);
            if(yow.gameCanEnd()){
                setFlow(tester, 0);
            } else {
                setFlow(tester, int96(uint96(action.flowRate)));
            }
            vm.warp(block.timestamp + uint32(action.dt));
            assertFalse(ISuperfluid(yoink.getHost()).isAppJailed(yow), "fucked");
        }
    }

    function setFlow(address tester, int96 flowRate) internal {
        vm.startPrank(tester);
        int96 currentFlowRate = yoink.getFlowRate(tester, address(yow));
        if(currentFlowRate == 0 && flowRate != 0) {
            if(!yow.isUserBanned(tester)) {
                yoink.createFlow(address(yow), flowRate);
            }
        } else if(currentFlowRate != 0 && flowRate == 0) {
            yoink.deleteFlow(tester, address(yow));
        } else if(currentFlowRate != 0 && flowRate != 0) {
            if(currentFlowRate % 2 == flowRate % 2) {
                yoink.updateFlow(address(yow), flowRate);
            } else {
                yoink.updateFlow(address(yow), flowRate+1);
            }
        }
        vm.stopPrank();
    }
    
}

