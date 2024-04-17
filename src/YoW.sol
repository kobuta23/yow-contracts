// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ISuperfluid, ISuperToken, ISuperApp, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperfluidPool} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {CFASuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFASuperAppBase.sol";
import {BasicParticle, SemanticMoney, FlowRate, Value, Time} from "@superfluid-finance/solidity-semantic-money/src/SemanticMoney.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";


function mul_div(Value a, Value b, Value c) pure returns (Value) {
    return Value.wrap(Value.unwrap(a) * Value.unwrap(b) / Value.unwrap(c));
}

interface IMintableSuperToken {
    function burn(uint256 amount) external;
}

contract YoW is CFASuperAppBase {
    using SemanticMoney for BasicParticle;
    using SuperTokenV1Library for ISuperToken;

    uint256 public powerflator;
    uint256 public offset;
    Time public gameEnded;

    struct Team {
        address leader;
        bool isWinning;
        address z;
    }
    
    uint256 public winningCountdownStart; // timestamp of when the team start winning
    uint256 public winningThreshold = 4 hours; // duration of the game
    address internal winningPot = address(0x99); // money from the losers
    Value internal proportionPotV;
    Value internal winningPotV;
    address internal proportionPot = address(0x33); // money from the winners at the game closing time

    Team public teamA;
    Team public teamB;

    ISuperToken immutable public yoink;

    mapping (address => BasicParticle) _userAccounts;

    mapping(ISuperToken => bool) internal _acceptedSuperTokens;

    constructor
        (ISuperToken _yoink, address _TEAMALeader, address _TEAMBLeader) 
        CFASuperAppBase(ISuperfluid(_yoink.getHost())) {
            selfRegister(true,true,true);
            yoink = _yoink;
            _acceptedSuperTokens[yoink] = true;
            teamA.leader = _TEAMALeader;
            teamB.leader = _TEAMBLeader;
            teamA.z = address(0x0);
            teamB.z = address(0x1);
        }
    
    /* WINNING FUNCTIONS */
    function timeToEnd() public view returns (uint256) {
        return winningCountdownStart + winningThreshold - block.timestamp;
    }

    function winningTeam() public view returns (Team memory) {
        return teamA.isWinning ? teamA: teamB;
    }
    function losingTeam() public view returns (Team memory) {
        return teamA.isWinning ? teamB: teamA;
    }

    function gameCanEnd() public view returns (bool) {
        if(winningCountdownStart == 0) {
            return false;
        }
        if(Time.unwrap(gameEnded) != 0) {
            return true;
        }
        return winningCountdownStart + winningThreshold < block.timestamp;
    }

    function updateWinners() internal {
        require(gameEnded == Time.wrap(0), "can't change winners after game ended");

        FlowRate flowRateA = _userAccounts[teamA.z].flow_rate();
        FlowRate flowRateB = _userAccounts[teamB.z].flow_rate();
        console2.log("flowRate teamA: %d", FlowRate.unwrap(flowRateA));
        console2.log("flowRate teamB: %d", FlowRate.unwrap(flowRateB));
        if(FlowRate.unwrap(flowRateA - flowRateB) > 0){
            // if this new flowRate changes things, set the winning team anew
            if(!teamA.isWinning){
                winningCountdownStart = block.timestamp;
                teamA.isWinning = true;
                teamB.isWinning = false;
            }
        } else {
            if(!teamB.isWinning){
                winningCountdownStart = block.timestamp;
                teamA.isWinning = false;
                teamB.isWinning = true;
            }
        }
    }
    /* ACCOUNTING FUNCTIONS */
    function isAcceptedSuperToken(ISuperToken superToken) public view override returns (bool) {
        return _acceptedSuperTokens[superToken];
        // fallback to the default impl allows us to easily test it
    }

    // wrapper that sets the team 
    function accountFlow(address account, int96 flowRate) internal {
        if (flowRate % 2 == 0) {
            accountFlowForTeam(account, teamA.z, flowRate);
        } else {
            accountFlowForTeam(account, teamB.z, flowRate);
        }
        console.log("Just accounted flow for %s", account);
        console.log("flowRate: ", uint256(int256(flowRate)));
        console.log("team: ", flowRate % 2 == 0 ? "teamA" : "teamB");
        console2.log("rtb of user:\t", Value.unwrap(_userAccounts[account].rtb(timeNow())));
        console2.log("rtb of team:\t", Value.unwrap(_userAccounts[flowRate % 2 == 0 ? teamA.z : teamB.z].rtb(timeNow())));
    }

    // adds stream accounting to the user
    function accountFlowForTeam(address account, address team, int96 flowRate) internal {
        (_userAccounts[account], _userAccounts[team]) = _userAccounts[account].shift_flow2b(_userAccounts[team], FlowRate.wrap(int96(flowRate)), timeNow());
    }

    function getFlowRate(address account) public view returns (int128) {
        return FlowRate.unwrap(_userAccounts[account].flow_rate());
    }

    // amount streamed so far by the user or team
    // 
    function balanceOf(address account) public view returns (uint256) {
        return balanceOfAt(account, block.timestamp);
    }

    // amount streamed by the user at a certain point in time
    function balanceOfAt(address account, uint timestamp) public view returns (uint256) {
        Time t = Time.wrap(uint32(timestamp));
        int256 balance = Value.unwrap(_userAccounts[account].rtb(t));
        if(balance < 0){
            return uint256(balance*-1);
        }
        return uint256(balance);
    }

    function timeNow() internal view returns (Time) {
        return Time.wrap(uint32(block.timestamp));
    }

    /* FLOW CALLBACKS */

    function onFlowCreated(ISuperToken, /*superToken*/ address sender, bytes calldata ctx)
        internal
        override
        returns (bytes memory)
    {
        int96 flowRate = yoink.getFlowRate(sender, address(this));
        if(Time.unwrap(_userAccounts[sender].settled_at()) != 0){
            revert("Can only stream once");
        }
        if(sender == teamA.leader || sender == teamB.leader){
            if(sender == teamA.leader){
                require(flowRate % 2 == 0, "wrong team");
            } else if (sender == teamB.leader){
                require(flowRate % 2 == 1, "wrong team");
            }
        }
        
        if(winningCountdownStart == 0){
            if (sender == teamA.leader || sender == teamB.leader){

                int96 flowA = yoink.getFlowRate(teamA.leader, address(this));
                int96 flowB = yoink.getFlowRate(teamB.leader, address(this));
                if(flowA > 0 && flowB > 0){
                    // game can start
                    winningCountdownStart = block.timestamp;
                    teamA.isWinning = false;
                    teamB.isWinning = false;
                }
            } else {
                revert("Only team leaders can start the game");
            }
        }

        accountFlow(sender, flowRate);
        updateWinners();
        if(gameCanEnd()) revert("Game is ended. No new streams");
        return ctx;
    }

    // UPDATE
    function onFlowUpdated(
        ISuperToken, /*superToken*/
        address sender,
        int96 previousFlowRate,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal override returns (bytes memory) {
        int96 flowRate = yoink.getFlowRate(sender, address(this));
        require(previousFlowRate % 2 == flowRate % 2, "wrong team");
        accountFlow(sender, -previousFlowRate);
        accountFlow(sender, flowRate);
        updateWinners();
        if(gameCanEnd()) revert("Game is ended. No new streams");
        return ctx;
    }

    // DELETE
    function onFlowDeleted(
        ISuperToken, /*superToken*/
        address sender,
        address receiver,
        int96 previousFlowRate,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal override returns (bytes memory) {
        if(receiver != address(this)) return ctx;
        
        if(!gameCanEnd()){
            console.log("in deleteFlow: game can NOT end");
            accountFlow(sender, -previousFlowRate);
            updateWinners();
            // user got liquidated during game. They lose their streamed amount
            // Shift their balance to teamLeader
            address teamLeader = previousFlowRate % 2 == 0 ? teamA.leader : teamB.leader;
            Value senderAmount = _userAccounts[sender].rtb(timeNow());
            console2.log("team leader balance before: %s", Value.unwrap(_userAccounts[teamLeader].rtb(timeNow())));
            (_userAccounts[sender], _userAccounts[teamLeader]) = 
                _userAccounts[sender].shift2(
                        _userAccounts[teamLeader], 
                        senderAmount
                    );
            if(sender == teamLeader) {
                IMintableSuperToken(address(yoink)).burn(SafeCast.toUint256(Value.unwrap(senderAmount))); 
                console.log("Leader dropped out, burning tokens");
            }
            console2.log("team leader balance after: %s", Value.unwrap(_userAccounts[teamLeader].rtb(timeNow())));
            return ctx;
        } 
        
        if(Time.unwrap(gameEnded) == 0){
            console.log("in deleteFlow: triggering game end");
            // this is the user triggering game-ending.
            console.log("in deleteFlow: timeNow() when game ended:", Time.unwrap(timeNow()));
            gameEnded = timeNow();
            gameEndingSequence();
        } 

        console.log("in deleteFlow: process payouts");
        // this is a user after the game was ended.
        // we should process refunds for them 
        processRepayments(sender, previousFlowRate);
        accountFlow(sender, -previousFlowRate); //this should close their internal streams
        return ctx;
    }

    function gameEndingSequence() internal {
        Value loserBalance = _userAccounts[losingTeam().z].rtb(timeNow());
        console2.log("loserBalance: \t %d", Value.unwrap(loserBalance));
        console2.log("winnerBalance: \t %d", Value.unwrap(_userAccounts[winningTeam().z].rtb(timeNow())));
        proportionPotV = _userAccounts[winningTeam().z].rtb(timeNow());
        winningPotV = loserBalance;
        (_userAccounts[losingTeam().z], _userAccounts[winningTeam().z]) = _userAccounts[losingTeam().z].shift2(_userAccounts[winningTeam().z], loserBalance);  
    }

    function processRepayments(address sender, int96 previousFlowRate) internal {
        bool isUserWinner = (previousFlowRate % 2 == 0 && teamA.isWinning) || (previousFlowRate % 2 != 0 && teamB.isWinning);
        console.log("in PR: isUserWinner: ", isUserWinner);
        ( uint256 postgameRefund, uint256 pregameRefund, uint256 winnings) = calculateClaimableAmount(sender, previousFlowRate, isUserWinner);
        console.log("in PR: postgameRefund: ", postgameRefund);
        console.log("in PR: pregameRefund: ", pregameRefund);
        console.log("in PR: winnings: ", winnings);

        uint256 toTransfer = postgameRefund + pregameRefund + winnings;
        if(isUserWinner){
            (_userAccounts[winningTeam().z], _userAccounts[sender]) = _userAccounts[winningTeam().z].shift2(_userAccounts[sender], Value.wrap(int256(toTransfer)));
        } else {
            (_userAccounts[losingTeam().z], _userAccounts[sender]) = _userAccounts[losingTeam().z].shift2(_userAccounts[sender], Value.wrap(int256(toTransfer)));
        }
        // in internal accounting, all of these sums are stored in the userAccounts[team]
        // so we just need to shift the funds from their team to the user (both internally and externally)

        console.log("transferring \t", toTransfer);
        console.log("balanceOf app: \t", yoink.balanceOf(address(this)));
        console.log("balanceOf user: \t", yoink.balanceOf(sender));
        if(toTransfer > 0) {
            uint256 balance = yoink.balanceOf(address(this));
            if(toTransfer > balance) toTransfer = balance;
            yoink.transferFrom(address(this), sender, toTransfer);
        }
        console.log("balanceOf app: \t", yoink.balanceOf(address(this)));
        console.log("balanceOf user: \t", yoink.balanceOf(sender));
    }

    function calculateClaimableAmount(address sender, int96 previousFlowRate, bool isUserWinner) internal view returns (uint256 pregameRefund, uint256 postgameRefund, uint256 winnings){
        console2.log("gameEnded: \t\t\t %d", Time.unwrap(gameEnded));
        console2.log("sender rtb now: \t\t %d", Value.unwrap(_userAccounts[sender].rtb(timeNow())));
        console2.log("sender rtb before: \t\t %d", Value.unwrap(_userAccounts[sender].rtb(gameEnded)));
        if(isUserWinner){
            Value pregameRefundV = -_userAccounts[sender].rtb(gameEnded);
            Value postgameRefundV = -_userAccounts[sender].rtb(timeNow()) - pregameRefundV;
            console2.log("refund: pre  \t\t\t %d", Value.unwrap(pregameRefundV));
            console2.log("refund: post \t\t\t %d", Value.unwrap(postgameRefundV));
            console2.log("refund: proportionPotV \t %d", Value.unwrap(proportionPotV));
            Value winningsV = mul_div(
                winningPotV,
                pregameRefundV,
                proportionPotV
            );
            console2.log("winnings: \t\t\t %d", Value.unwrap(winningsV));
            pregameRefund = SafeCast.toUint256(Value.unwrap(pregameRefundV));
            postgameRefund = SafeCast.toUint256(Value.unwrap(postgameRefundV));
            winnings = SafeCast.toUint256(Value.unwrap(winningsV));
        } else {
            pregameRefund = 0;
            Value postgameRefundV = -_userAccounts[sender].rtb(timeNow()) - _userAccounts[sender].rtb(gameEnded);
            postgameRefund = SafeCast.toUint256(Value.unwrap(postgameRefundV));
            winnings = 0;
        }
    }

    function isUserBanned(address user) public view returns (bool) {
        uint256 settledAt = Time.unwrap(_userAccounts[user].settled_at());
        int128 currentFlowRate = FlowRate.unwrap(_userAccounts[user].flow_rate());
        //int96 currentFlowRate = yoink.getFlowRate(user, address(this));
        return (currentFlowRate == 0 && settledAt != 0); 
    }

}
