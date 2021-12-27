// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@boringcrypto/boring-solidity/contracts/libraries/BoringMath.sol";
import "@boringcrypto/boring-solidity/contracts/BoringBatchable.sol";
import "@boringcrypto/boring-solidity/contracts/BoringOwnable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../interfaces/IMasterChef.sol";

contract LinSpiritChef is BoringOwnable, BoringBatchable {
    using SafeMath for uint256;
    using BoringMath128 for uint128;
    using BoringERC20 for IERC20;
    using SignedSafeMath for int256;

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    struct PoolInfo {
        uint256 accSpiritPerShare;
        uint256 lastRewardTime;
        uint256 allocPoint;
    }

    /// @notice Address of SPIRIT contract.
    IERC20 public SPIRIT;

    /// @notice Info of each MCV2 pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each MCV2 pool.
    IERC20[] public lpToken;

    /// @notice Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 public spiritPerSecond;
    uint256 private constant ACC_SPIRIT_PRECISION = 1e12;

    // Deposit Fee Address
    address public feeAddress;

    uint256 public distributePeriod;
    uint256 public lastDistributedTime;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken);
    event LogSetPool(uint256 indexed pid, uint256 allocPoint);
    event LogUpdatePool(uint256 indexed pid, uint256 lastRewardTime, uint256 lpSupply, uint256 accSpiritPerShare);
    event LogSpiritPerSecond(uint256 spiritPerSecond);

    /// @param _spirit The SPIRIT token contract address.
    constructor(IERC20 _spirit) public {
        SPIRIT = _spirit;
        distributePeriod = 604800;
    }
    
    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }

    /// @notice Returns the number of MCV2 pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    function add(uint256 allocPoint, IERC20 _lpToken) public onlyOwner {
        totalAllocPoint = totalAllocPoint.add(allocPoint);
        lpToken.push(_lpToken);

        poolInfo.push(PoolInfo({
            allocPoint: allocPoint,
            lastRewardTime: block.timestamp,
            accSpiritPerShare: 0
        }));
        emit LogPoolAddition(lpToken.length.sub(1), allocPoint, _lpToken);
    }

    /// @notice Update the given pool's SPIRIT allocation point and `IRewarder` contract. Can only be called
    /// by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        emit LogSetPool(_pid, _allocPoint);
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 len = poolInfo.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(i);
        }
    }

    /// @notice Sets the spirit per second to be distributed. Can only be called by the owner.
    /// @param _spiritPerSecond The amount of Spirit to be distributed per second.
    function setSpiritPerSecond(uint256 _spiritPerSecond) public onlyOwner {
        spiritPerSecond = _spiritPerSecond;
        emit LogSpiritPerSecond(_spiritPerSecond);
    }

    function setDistributionRate(uint256 amount) public onlyOwner {
      uint256 notDistributed;
      if (lastDistributedTime > 0 && block.timestamp < lastDistributedTime) {
        uint256 timeLeft = lastDistributedTime.sub(block.timestamp);
        notDistributed = spiritPerSecond.mul(timeLeft);
      }

      amount = amount.add(notDistributed);
      uint256 _spiritPerSecond = amount.div(distributePeriod);
      spiritPerSecond = _spiritPerSecond;
      lastDistributedTime = block.timestamp.add(distributePeriod);
      massUpdatePools();
      emit LogSpiritPerSecond(_spiritPerSecond);
    }

    /// @notice View function to see pending SPIRIT on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending SPIRIT reward for a given user.
    function pendingSpirit(uint256 _pid, address _user) external view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSpiritPerShare = pool.accSpiritPerShare;
        uint256 lpSupply = lpToken[_pid].balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 time = block.timestamp.sub(pool.lastRewardTime);
            uint256 spiritReward = time.mul(spiritPerSecond).mul(pool.allocPoint) / totalAllocPoint;
            accSpiritPerShare = accSpiritPerShare.add(spiritReward.mul(ACC_SPIRIT_PRECISION) / lpSupply);
        }
        pending = int256(user.amount.mul(accSpiritPerShare) / ACC_SPIRIT_PRECISION).sub(user.rewardDebt).toUInt256();
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTime) {
            uint256 lpSupply = lpToken[pid].balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 time = block.timestamp.sub(pool.lastRewardTime);
                uint256 spiritReward = time.mul(spiritPerSecond).mul(pool.allocPoint) / totalAllocPoint;
                pool.accSpiritPerShare = pool.accSpiritPerShare
                    .add(spiritReward.mul(ACC_SPIRIT_PRECISION).div(lpSupply));
            }
            pool.lastRewardTime = block.timestamp;
            poolInfo[pid] = pool;
            emit LogUpdatePool(pid, pool.lastRewardTime, lpSupply, pool.accSpiritPerShare);
        }
    }

    /// @notice Deposit LP tokens to MCV2 for SPIRIT allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(uint256 pid, uint256 amount, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][to];

        // Effects
        user.amount = user.amount.add(amount);
        user.rewardDebt = user.rewardDebt.add(int256(amount.mul(pool.accSpiritPerShare) / ACC_SPIRIT_PRECISION));

        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, pid, amount, to);
    }

    /// @notice Withdraw LP tokens from MCV2.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(uint256 pid, uint256 amount, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        // Effects
        user.rewardDebt = user.rewardDebt.sub(int256(amount.mul(pool.accSpiritPerShare) / ACC_SPIRIT_PRECISION));
        user.amount = user.amount.sub(amount);
        
        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of SPIRIT rewards.
    function harvest(uint256 pid, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedSpirit = int256(user.amount.mul(pool.accSpiritPerShare) / ACC_SPIRIT_PRECISION);
        uint256 _pendingSpirit = accumulatedSpirit.sub(user.rewardDebt).toUInt256();

        // Effects
        user.rewardDebt = accumulatedSpirit;

        // Interactions
        if (_pendingSpirit != 0) {
            SPIRIT.safeTransfer(to, _pendingSpirit);
        }

        emit Harvest(msg.sender, pid, _pendingSpirit);
    }
    
    /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and SPIRIT rewards.
    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedSpirit = int256(user.amount.mul(pool.accSpiritPerShare) / ACC_SPIRIT_PRECISION);
        uint256 _pendingSpirit = accumulatedSpirit.sub(user.rewardDebt).toUInt256();

        // Effects
        user.rewardDebt = accumulatedSpirit.sub(int256(amount.mul(pool.accSpiritPerShare) / ACC_SPIRIT_PRECISION));
        user.amount = user.amount.sub(amount);
        
        // Interactions
        SPIRIT.safeTransfer(to, _pendingSpirit);

        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
        emit Harvest(msg.sender, pid, _pendingSpirit);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) public {
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[pid].safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount, to);
    }
}
