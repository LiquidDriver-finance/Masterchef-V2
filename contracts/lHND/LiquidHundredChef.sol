// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@boringcrypto/boring-solidity/contracts/libraries/BoringMath.sol";
import "@boringcrypto/boring-solidity/contracts/BoringBatchable.sol";
import "@boringcrypto/boring-solidity/contracts/BoringOwnable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../interfaces/ISecondRewarder.sol";
import "../interfaces/IStrategy.sol";

interface IMigratorChef {
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    function migrate(IERC20 token) external returns (IERC20);
}

/// @notice The (older) MasterChef contract gives out a constant number of TOKEN tokens per block.
/// It is the only address with minting rights for TOKEN.
/// The idea for this MasterChef V2 (MCV2) contract is therefore to be the owner\ of a dummy token
/// that is deposited into the MasterChef V1 (MCV1) contract.
contract LiquidHundredChef is OwnableUpgradeable {
    using SafeMath for uint256;
    using BoringMath128 for uint256;
    using BoringERC20 for IERC20;
    using SignedSafeMath for int256;

    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of TOKEN to distribute per block.
    struct PoolInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardTime;
        uint256 allocPoint;
    }

    /// @notice Address of TOKEN contract.
    IERC20 public TOKEN;
    // @notice The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    /// @notice Info of each MCV2 pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each MCV2 pool.
    IERC20[] public lpToken;
    /// @notice Address of each `ISecondRewarder` contract in MCV2.
    ISecondRewarder[] public rewarder;
    /// @notice Address of each `IStrategy`.
    IStrategy[] public strategies;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @dev Tokens added
    mapping(address => bool) public addedTokens;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 public tokenPerSecond;
    uint256 public ACC_TOKEN_PRECISION;

    uint256 public distributionPeriod;
    uint256 public lastDistributedTime;

    uint256 public overDistributed;

    address public liHNDStrategy;

    string public __NAME__;

    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event Withdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(
        uint256 indexed pid,
        uint256 allocPoint,
        IERC20 indexed lpToken,
        ISecondRewarder indexed rewarder
    );
    event LogSetPool(
        uint256 indexed pid,
        uint256 allocPoint,
        ISecondRewarder indexed rewarder,
        bool overwrite
    );
    event LogUpdatePool(
        uint256 indexed pid,
        uint256 lastRewardTime,
        uint256 lpSupply,
        uint256 accTokenPerShare
    );
    event LogTokenPerSecond(uint256 tokenPerSecond);

    constructor() public {}

    function initialize(IERC20 _token, string memory _name) public initializer {
        __Ownable_init();
        TOKEN = _token;
        ACC_TOKEN_PRECISION = 1e12;
        __NAME__ = _name;
    }

    function setName(string memory _name) external onlyOwner {
        __NAME__ = _name;
    }

    function setLiHNDStrategy(address _liHNDStrategy) external onlyOwner {
        liHNDStrategy = _liHNDStrategy;
    }

    function setDistributionPeriod(uint256 _distributionPeriod) external onlyOwner {
        distributionPeriod = _distributionPeriod;
    }

    modifier onlyOwnerOrLiHNDStrategy() {
        require(owner() == _msgSender() || _msgSender() == liHNDStrategy, "!Ownable");
        _;
    }

    /// @notice Returns the number of MCV2 pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Address of the rewarder delegate.
    function add(
        uint256 allocPoint,
        IERC20 _lpToken,
        ISecondRewarder _rewarder,
        IStrategy _strategy
    ) public onlyOwner {
        require(addedTokens[address(_lpToken)] == false, "Token already added");
        totalAllocPoint = totalAllocPoint.add(allocPoint);
        lpToken.push(_lpToken);
        rewarder.push(_rewarder);
        strategies.push(_strategy);

        poolInfo.push(
            PoolInfo({
                allocPoint: allocPoint,
                lastRewardTime: block.timestamp,
                accTokenPerShare: 0
            })
        );
        addedTokens[address(_lpToken)] = true;
        emit LogPoolAddition(
            lpToken.length.sub(1),
            allocPoint,
            _lpToken,
            _rewarder
        );
    }

    /// @notice Update the given pool's TOKEN allocation point and `ISecondRewarder` contract.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _rewarder Address of the rewarder delegate.
    /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        ISecondRewarder _rewarder,
        IStrategy _strategy,
        bool overwrite
    ) public onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        if (overwrite) {
            rewarder[_pid] = _rewarder;

            if (address(strategies[_pid]) != address(_strategy)) {
                if (address(strategies[_pid]) != address(0)) {
                    _withdrawAllFromStrategy(_pid, strategies[_pid]);
                }
                if (address(_strategy) != address(0)) {
                    _depositAllToStrategy(_pid, _strategy);
                }
                strategies[_pid] = _strategy; 
            }
        }
        emit LogSetPool(
            _pid,
            _allocPoint,
            overwrite ? _rewarder : rewarder[_pid],
            overwrite
        );
    }

    function _withdrawAllFromStrategy(uint256 _pid, IStrategy _strategy) internal {
        IERC20 _lpToken = lpToken[_pid];
        uint256 _strategyBalance = _strategy.balanceOf();
        require(address(_lpToken) == _strategy.want(), '!lpToken');

        if (_strategyBalance > 0) {
            _strategy.withdraw(_strategyBalance);
            uint256 _currentBalance = _lpToken.balanceOf(address(this));

            require(_currentBalance >= _strategyBalance, '!balance1');

            _strategyBalance = _strategy.balanceOf();
            require(_strategyBalance == 0, '!balance2');
        }
    }

    function _depositAllToStrategy(uint256 _pid, IStrategy _strategy) internal {
        IERC20 _lpToken = lpToken[_pid];
        uint256 _strategyBalanceBefore = _strategy.balanceOf();
        uint256 _balanceBefore = _lpToken.balanceOf(address(this));
        require(address(_lpToken) == _strategy.want(), '!lpToken');

        if (_balanceBefore > 0) {
            _lpToken.safeTransfer(address(_strategy), _balanceBefore);
            _strategy.deposit();

            uint256 _strategyBalanceAfter = _strategy.balanceOf();
            uint256 _strategyBalanceDiff = _strategyBalanceAfter.sub(_strategyBalanceBefore);

            require(_strategyBalanceDiff == _balanceBefore, '!balance1');

            uint256 _balanceAfter = _lpToken.balanceOf(address(this));
            require(_balanceAfter == 0, '!balance2');
        }
    }

    /// @notice Sets the token per second to be distributed. Can only be called by the owner.
    /// @param _tokenPerSecond The amount of Token to be distributed per second.
    function setTokenPerSecond(uint256 _tokenPerSecond) public onlyOwner {
        massUpdateAllPools();
        tokenPerSecond = _tokenPerSecond;
        massUpdateAllPools();
        emit LogTokenPerSecond(_tokenPerSecond);
    }

    function setDistributionRate(uint256 amount) external onlyOwnerOrLiHNDStrategy {
        massUpdateAllPools();
        uint256 _notDistributed;
        if (lastDistributedTime > 0 && block.timestamp < lastDistributedTime) {
            uint256 timeLeft = lastDistributedTime.sub(block.timestamp);
            _notDistributed = tokenPerSecond.mul(timeLeft);
        }

        amount = amount.add(_notDistributed);

        uint256 _moreDistributed = overDistributed;
        overDistributed = 0;

        if (lastDistributedTime > 0 && block.timestamp > lastDistributedTime) {
            uint256 timeOver = block.timestamp.sub(lastDistributedTime);
            _moreDistributed = _moreDistributed.add(tokenPerSecond.mul(timeOver));
        }

        if (amount < _moreDistributed) {
            overDistributed = _moreDistributed.sub(amount);
            tokenPerSecond = 0;
            lastDistributedTime = block.timestamp.add(distributionPeriod);
            massUpdateAllPools();
            emit LogTokenPerSecond(tokenPerSecond);
        } else {
            amount = amount.sub(_moreDistributed);
            tokenPerSecond = amount.div(distributionPeriod);
            lastDistributedTime = block.timestamp.add(distributionPeriod);
            massUpdateAllPools();
            emit LogTokenPerSecond(tokenPerSecond);
        }
    }

    function setOverDistributed(uint256 _overDistributed) public onlyOwner {
        overDistributed = _overDistributed;
    }

    /// @notice Set the `migrator` contract. Can only be called by the owner.
    /// @param _migrator The contract address to set.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    /// @notice Migrate LP token to another LP contract through the `migrator` contract.
    /// @param _pid The index of the pool. See `poolInfo`.
    function migrate(uint256 _pid) public {
        require(
            address(migrator) != address(0),
            "MasterChefV2: no migrator set"
        );
        IERC20 _lpToken = lpToken[_pid];
        uint256 bal = _lpToken.balanceOf(address(this));
        _lpToken.approve(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(_lpToken);
        require(
            bal == newLpToken.balanceOf(address(this)),
            "MasterChefV2: migrated balance must match"
        );
        require(
            addedTokens[address(newLpToken)] == false,
            "Token already added"
        );
        addedTokens[address(newLpToken)] = true;
        addedTokens[address(_lpToken)] = false;
        lpToken[_pid] = newLpToken;
    }

    /// @notice View function to see pending TOKEN on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending TOKEN reward for a given user.
    function pendingToken(uint256 _pid, address _user)
        external
        view
        returns (uint256 pending)
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;

        uint256 lpSupply;

        if (address(strategies[_pid]) != address(0)) {
            lpSupply = lpToken[_pid].balanceOf(address(this)).add(
                strategies[_pid].balanceOf()
            );
        }
        else {
            lpSupply = lpToken[_pid].balanceOf(address(this));
        }

        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 time = block.timestamp.sub(pool.lastRewardTime);
            uint256 tokenReward = time.mul(tokenPerSecond).mul(
                pool.allocPoint
            ) / totalAllocPoint;
            accTokenPerShare = accTokenPerShare.add(
                tokenReward.mul(ACC_TOKEN_PRECISION) / lpSupply
            );
        }
        pending = int256(
            user.amount.mul(accTokenPerShare) / ACC_TOKEN_PRECISION
        ).sub(user.rewardDebt).toUInt256();
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    function massUpdateAllPools() public {
        uint256 len = poolInfo.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(i);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTime) {

            uint256 lpSupply;

            if (address(strategies[pid]) != address(0)) {
                lpSupply = lpToken[pid].balanceOf(address(this)).add(
                    strategies[pid].balanceOf()
                );
            }
            else {
                lpSupply = lpToken[pid].balanceOf(address(this));
            }

            if (lpSupply > 0) {
                uint256 time = block.timestamp.sub(pool.lastRewardTime);
                uint256 tokenReward = time.mul(tokenPerSecond).mul(
                    pool.allocPoint
                ) / totalAllocPoint;
                pool.accTokenPerShare = pool.accTokenPerShare.add(
                    (tokenReward.mul(ACC_TOKEN_PRECISION) / lpSupply)
                );
            }
            pool.lastRewardTime = block.timestamp;
            poolInfo[pid] = pool;
            emit LogUpdatePool(
                pid,
                pool.lastRewardTime,
                lpSupply,
                pool.accTokenPerShare
            );
        }
    }

    /// @notice Deposit LP tokens to MCV2 for TOKEN allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][to];

        // Effects
        user.amount = user.amount.add(amount);
        user.rewardDebt = user.rewardDebt.add(
            int256(amount.mul(pool.accTokenPerShare) / ACC_TOKEN_PRECISION)
        );

        // Interactions
        ISecondRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, to, to, 0, user.amount);
        }

        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);

        IStrategy _strategy = strategies[pid];
        if (address(_strategy) != address(0)) {
            uint256 _amount = lpToken[pid].balanceOf(address(this));
            lpToken[pid].safeTransfer(address(_strategy), _amount);
            _strategy.deposit();
        }

        emit Deposit(msg.sender, pid, amount, to);
    }

    function _withdraw(uint256 amount, uint256 pid, address to) internal returns (uint256) {
        uint256 balance = lpToken[pid].balanceOf(address(this));
        IStrategy strategy = strategies[pid];
        if (amount > balance) {
            uint256 missing = amount.sub(balance);
            uint256 withdrawn = strategy.withdraw(missing);
            amount = balance.add(withdrawn);
        }

        lpToken[pid].safeTransfer(to, amount);

        return amount;
    }

    /// @notice Withdraw LP tokens from MCV2.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        // Effects
        user.rewardDebt = user.rewardDebt.sub(
            int256(amount.mul(pool.accTokenPerShare) / ACC_TOKEN_PRECISION)
        );
        user.amount = user.amount.sub(amount);

        // Interactions
        ISecondRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, 0, user.amount);
        }

        // lpToken[pid].safeTransfer(to, amount);
        amount = _withdraw(amount, pid, to);

        emit Withdraw(msg.sender, pid, amount, to);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of TOKEN rewards.
    function harvest(uint256 pid, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedToken = int256(
            user.amount.mul(pool.accTokenPerShare) / ACC_TOKEN_PRECISION
        );
        uint256 _pendingToken = accumulatedToken
            .sub(user.rewardDebt)
            .toUInt256();

        // Effects
        user.rewardDebt = accumulatedToken;

        // Interactions
        if (_pendingToken != 0) {
            TOKEN.safeTransfer(to, _pendingToken);
        }

        ISecondRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(
                pid,
                msg.sender,
                to,
                _pendingToken,
                user.amount
            );
        }

        emit Harvest(msg.sender, pid, _pendingToken);
    }

    /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and TOKEN rewards.
    function withdrawAndHarvest(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedToken = int256(
            user.amount.mul(pool.accTokenPerShare) / ACC_TOKEN_PRECISION
        );
        uint256 _pendingToken = accumulatedToken
            .sub(user.rewardDebt)
            .toUInt256();

        // Effects
        user.rewardDebt = accumulatedToken.sub(
            int256(amount.mul(pool.accTokenPerShare) / ACC_TOKEN_PRECISION)
        );
        user.amount = user.amount.sub(amount);

        // Interactions
        TOKEN.safeTransfer(to, _pendingToken);

        ISecondRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(
                pid,
                msg.sender,
                to,
                _pendingToken,
                user.amount
            );
        }

        // lpToken[pid].safeTransfer(to, amount);
        _withdraw(amount, pid, to);

        emit Withdraw(msg.sender, pid, amount, to);
        emit Harvest(msg.sender, pid, _pendingToken);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) public {
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        ISecondRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, 0, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        // lpToken[pid].safeTransfer(to, amount);
        amount = _withdraw(amount, pid, to);
        emit EmergencyWithdraw(msg.sender, pid, amount, to);
    }
}
