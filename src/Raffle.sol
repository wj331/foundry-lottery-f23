//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/VRFCoordinatorV2.sol";
import {VRFConsumerBaseV2} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample  Raffle contract
 * @author wj331
 * @notice This contract is for creating a simple raffle
 * @dev Implmenets Chainlink VRFv2
 */
//uses VRF to get random number
contract Raffle is VRFConsumerBaseV2 {
            error Raffle_NotEnoughEthSent();
            error Raffle_TransferFailed();
            error Raffle_RaffleNotOpen();
            error Raffle_UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

            //create type declarations using enum
            enum RaffleState{OPEN,  CALCULATING} //0 and 1


            uint16 private constant REQUEST_CONFIRMATIONS = 3;
            uint32 private constant NUM_WORDS = 1;

            uint256 private immutable i_entranceFee;
            address payable[] private s_players;
            uint256 private immutable i_interval;
            uint256 private s_lastTimeStamp;
            VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
            bytes32 private immutable i_gasLane;
            uint64 private immutable i_subscriptionId;
            uint32 private immutable i_callbackGasLimit;
            address private s_recentWinner;
            RaffleState private s_raffleState;

            //Events
            event EnteredRaffle (address indexed player);
            event PickedWinner (address indexed winner);
            event RequestedRaffleWinner(uint256 indexed requestId);

            constructor (uint256 entranceFee, uint256 interval, address vrfCoordinator, bytes32 gasLane, uint64 subscriptionId, uint32 callbackGasLimit) VRFConsumerBaseV2(vrfCoordinator) {
            i_entranceFee = entranceFee;
            i_interval = interval;
            s_lastTimeStamp = block.timestamp;
            i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
            i_gasLane = gasLane;
            i_subscriptionId = subscriptionId;
            i_callbackGasLimit = callbackGasLimit;
            s_raffleState = RaffleState.OPEN;
            }

        function enterRaffle() external payable{
        //pay for ticket
        if (msg.value < i_entranceFee) {
            revert Raffle_NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_RaffleNotOpen();
        }
        
        //enter by pushing them onto our array 
        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);
    }

    // 1. get a random number
    // 2. use the random number to pick a player
    //3. be automatically called using chainlink automation

    //this function will call upkeep function and triggers the chainlink automation
    function checkUpKeep(bytes memory /* checkldata */ ) public view  returns (bool upkeepNeeded, bytes memory /*performData*/) {
        //check to see if enough time has passed
        bool timeHasPassed =  (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance >0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }


    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpKeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
    
        s_raffleState = RaffleState.CALCULATING;

        //chainlink vrf 1. request the RNG, 2. Get the random number
        //make request to chainlink node to give us a random number
        uint256 requestId = i_vrfCoordinator.requestRandomWords (
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256 /*requestId*/, uint256[] memory randomWords) internal override {
        // what we do when we have the random number
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;

        //reset everything and make another round of raffle
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;


        (bool success, ) = winner.call {value: address(this).balance}("");

        if (!success) {
            revert Raffle_TransferFailed();
        }
        emit PickedWinner(winner);
    }

    //getter function
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}