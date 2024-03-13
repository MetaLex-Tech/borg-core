// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../libs/auth.sol";
import "../../libs/conditions/conditionManager.sol";

contract vetoVoteMod is ConditionManager { //is baseImplant

    address public immutable BORG_SAFE;
    address public immutable governanceToken;
    uint256 public duration;
    uint256 public objectionsThreshold;
    uint256 public lastMotionId;

     struct Proposal {
        uint256 id;
        uint256 duration;
        uint256 startTime;
        uint256 objectionsThreshold;
        uint256 objectionsAmount;
        address token;
        address recipient;
        uint256 amount;
        address votingAuthority;
    }

    struct approvedGrantToken { 
        address token;
        uint256 spendingLimit;
        uint256 amountSpent;
    }

    constructor(Auth _auth, address _borgSafe, address _governanceToken, uint256 _duration, uint256 _objectionsThreshold) ConditionManager(_auth) {
        BORG_SAFE = _borgSafe;
        governanceToken = _governanceToken;
        duration = _duration;
        objectionsThreshold = _objectionsThreshold;
        lastMotionId=0;
    }
}