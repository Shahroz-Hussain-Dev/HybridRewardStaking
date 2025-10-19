// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from,address to,uint256 amount) external returns (bool);
}

contract HybridRewardStaking {
    IERC20 public immutable stakeToken;
    IERC20 public immutable rewardToken;
    address public owner;

    uint256 public constant ACTIVITY_WEIGHT = 70; 
    uint256 public constant HOLDING_WEIGHT  = 30; 
    uint256 public constant WEIGHT_BASE     = 100;

    struct Epoch {
        uint256 reward;            
        uint256 start;           
        uint256 end;               
        uint256 totalActivity;    
        uint256 totalHolding;      
        bool    exists;
    }

    /// epochId -> Epoch
    mapping(uint256 => Epoch) public epochs;
    uint256 public epochCount = 0; 

    
    mapping(uint256 => mapping(address => uint256)) public userActivity;
   
    mapping(uint256 => mapping(address => uint256)) public userHolding;

   
    mapping(address => uint256) public stakeBalance;


    mapping(address => uint256) public lastUpdate; 
    mapping(address => uint256) public lastProcessedEpoch; 

    /// claimed flags: epochId => user => bool
    mapping(uint256 => mapping(address => bool)) public claimed;

    /// activity managers (addresses allowed to award activity points)
    mapping(address => bool) public activityManager;

    event EpochStarted(uint256 indexed epochId, uint256 start, uint256 end, uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event ActivityAwarded(uint256 indexed epochId, address indexed user, uint256 points);
    event Claimed(uint256 indexed epochId, address indexed user, uint256 rewardAmount);
    event ActivityManagerUpdated(address indexed manager, bool allowed);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    modifier onlyActivityManager() {
        require(activityManager[msg.sender] || msg.sender == owner, "only activity manager");
        _;
    }

    constructor(address _stakeToken, address _rewardToken) {
        require(_stakeToken != address(0) && _rewardToken != address(0), "zero addr");
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardToken);
        owner = msg.sender;
        lastProcessedEpoch[msg.sender] = 0;
    }


    function setActivityManager(address manager, bool allowed) external onlyOwner {
        activityManager[manager] = allowed;
        emit ActivityManagerUpdated(manager, allowed);
    }

    /// @notice transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function startEpoch(uint256 rewardAmount, uint256 durationSeconds) external onlyOwner {
        require(durationSeconds > 0, "duration>0");
        require(rewardAmount > 0, "reward>0");

        uint256 start = block.timestamp;
        uint256 end = start + durationSeconds;

        epochCount += 1;
        epochs[epochCount] = Epoch({
            reward: rewardAmount,
            start: start,
            end: end,
            totalActivity: 0,
            totalHolding: 0,
            exists: true
        });


        require(rewardToken.transferFrom(msg.sender, address(this), rewardAmount), "fund failed");

        emit EpochStarted(epochCount, start, end, rewardAmount);
    }


    function stake(uint256 amount) external {
        require(amount > 0, "amount>0");

        _updateUserHolding(msg.sender);

        // transfer tokens in
        require(stakeToken.transferFrom(msg.sender, address(this), amount), "transfer failed");

        // increase balance & set lastUpdate
        stakeBalance[msg.sender] += amount;
        if (lastUpdate[msg.sender] == 0) {
            lastUpdate[msg.sender] = block.timestamp;
        } else {
            lastUpdate[msg.sender] = block.timestamp;
        }

        emit Staked(msg.sender, amount);
    }

    /// @notice Unstake tokens (partial), updates holding accounting before reducing stake.
    function unstake(uint256 amount) external {
        require(amount > 0, "amount>0");
        require(stakeBalance[msg.sender] >= amount, "insufficient stake");

        // update user's holding accounting up to now
        _updateUserHolding(msg.sender);

        // reduce stake
        stakeBalance[msg.sender] -= amount;
        lastUpdate[msg.sender] = block.timestamp;

        // transfer tokens back
        require(stakeToken.transfer(msg.sender, amount), "transfer failed");

        emit Unstaked(msg.sender, amount);
    }

    function awardActivity(address user, uint256 points) external onlyActivityManager {
        require(points > 0, "points>0");
        uint256 currentEpoch = _currentEpochId();
        require(currentEpoch != 0 && epochs[currentEpoch].exists, "no active epoch");
        Epoch storage e = epochs[currentEpoch];


        require(block.timestamp >= e.start && block.timestamp <= e.end, "epoch not active");

        userActivity[currentEpoch][user] += points;
        e.totalActivity += points;

        emit ActivityAwarded(currentEpoch, user, points);
    }


    function _updateUserHolding(address user) internal {
        uint256 userStake = stakeBalance[user];
        uint256 from = lastUpdate[user];
        uint256 to = block.timestamp;

        // if never updated or no stake, just set lastUpdate and return
        if (from == 0) {
            lastUpdate[user] = to;
            return;
        }
        if (from >= to) return;
        if (userStake == 0) {
            lastUpdate[user] = to;
            return;
        }


        uint256 startEpoch1 = lastProcessedEpoch[user] + 1;
        if (startEpoch1 == 0) startEpoch1 = 1;
        for (uint256 eid = startEpoch1; eid <= epochCount; eid++) {
            Epoch storage e = epochs[eid];
            if (!e.exists) continue;

            uint256 overlapStart = _max(from, e.start);
            uint256 overlapEnd   = _min(to, e.end);

            if (overlapStart >= overlapEnd) {
                // no overlap
            } else {
                uint256 duration = overlapEnd - overlapStart; // seconds
                // stake-time points = stakeAmount * duration
                uint256 stakeTime = userStake * duration;
                userHolding[eid][user] += stakeTime;
                e.totalHolding += stakeTime;
            }

            // If 'to' is before this epoch's end, we are done
            if (to <= e.end) {
                // Set lastProcessedEpoch to current epoch - 1 if no full coverage; else set to eid
                lastProcessedEpoch[user] = eid;
                break;
            } else {
                // moved past this epoch
                lastProcessedEpoch[user] = eid;
            }
        }

        lastUpdate[user] = to;
    }


    function claim(uint256 epochId) external {
        require(epochId > 0 && epochId <= epochCount, "invalid epoch");
        Epoch storage e = epochs[epochId];
        require(e.exists, "no epoch");
        require(block.timestamp > e.end, "epoch not ended");
        require(!claimed[epochId][msg.sender], "already claimed");

  
        _updateUserHolding(msg.sender);

        uint256 activityPts = userActivity[epochId][msg.sender];
        uint256 holdingPts  = userHolding[epochId][msg.sender];


        if (e.totalActivity == 0 && e.totalHolding == 0) {
            claimed[epochId][msg.sender] = true;
            emit Claimed(epochId, msg.sender, 0);
            return;
        }


        uint256 rewardAmount = 0;
        uint256 PREC = 1e18;

        uint256 activitySharePart = 0;
        if (e.totalActivity > 0 && activityPts > 0) {
            activitySharePart = (PREC * activityPts) / e.totalActivity; // scaled
        }

        uint256 holdingSharePart = 0;
        if (e.totalHolding > 0 && holdingPts > 0) {
            holdingSharePart = (PREC * holdingPts) / e.totalHolding; // scaled
        }

        uint256 weightedScaled = (ACTIVITY_WEIGHT * activitySharePart + HOLDING_WEIGHT * holdingSharePart) / WEIGHT_BASE;

        // Final reward
        rewardAmount = (e.reward * weightedScaled) / PREC;

        claimed[epochId][msg.sender] = true;

        if (rewardAmount > 0) {
            require(rewardToken.transfer(msg.sender, rewardAmount), "reward transfer failed");
        }

        emit Claimed(epochId, msg.sender, rewardAmount);
    }


    function _currentEpochId() internal view returns (uint256) {
        uint256 id = epochCount;
        if (id == 0) return 0;
        // only possible active epoch is the latest one
        Epoch storage e = epochs[id];
        if (block.timestamp >= e.start && block.timestamp <= e.end) return id;
        return 0;
    }

    function currentEpochId() external view returns (uint256) {
        return _currentEpochId();
    }

    // small helpers
    function _min(uint256 a, uint256 b) internal pure returns (uint256) { return a < b ? a : b; }
    function _max(uint256 a, uint256 b) internal pure returns (uint256) { return a > b ? a : b; }

    // Emergency: allow owner to rescue tokens mistakenly sent
    function rescueToken(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero");
        IERC20(token).transfer(to, amount);
    }
}
