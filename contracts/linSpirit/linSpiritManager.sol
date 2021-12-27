// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ILinSpiritStrategy.sol";
import "./interfaces/ILinSpirit.sol";

contract linSpiritManager {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant spirit = address(0x5Cc61A78F164885776AA610fb0FE1257df78E59B);
    uint256 private constant MAXTIME = 4 * 364 * 86400;
    uint256 private constant WEEK = 7 * 86400;

    address public feeManager;
    address public strategy;
    address public linSpirit;
    uint256 public incentiveSpirit = 0;
    uint256 public unlockTime;

    constructor(address _strategy, address _linSpirit) public {
        strategy = _strategy;
        linSpirit = _linSpirit;
        feeManager = msg.sender;
    }

    function initialLock() public {
        require(msg.sender == feeManager || msg.sender == address(this), "!auth");

        uint256 unlockAt = block.timestamp + MAXTIME;
        uint256 unlockInWeeks = (unlockAt / WEEK) * WEEK;

        //release old lock if exists
        ILinSpiritStrategy(strategy).release();
        //create new lock
        uint256 spiritBalanceStrategy = IERC20(spirit).balanceOf(strategy);
        ILinSpiritStrategy(strategy).createLock(spiritBalanceStrategy, unlockAt);
        unlockTime = unlockInWeeks;
    }

    //lock more spirit into the inSpirit contract
    function _lockMoreSpirit(uint256 _amount) internal {
        if (_amount > 0) {
            IERC20(spirit).safeTransfer(strategy, _amount);
        }

        //increase amount
        if (_amount == 0) {
            return;
        }

        uint256 _strategyInSpiritBalance = ILinSpiritStrategy(strategy).balanceOfInSpirit();

        if (_strategyInSpiritBalance > 0) {
            //increase amount
            ILinSpiritStrategy(strategy).increaseAmount(_amount);
        } else {
            initialLock();
        }
    }

    //deposit spirit for GinSpirit
    //can locking immediately or defer locking to someone else by paying a fee.
    //while users can choose to lock or defer, this is mostly in place so that
    //the cvx reward contract isnt costly to claim rewards

    function deposit(uint256 _amount) external {
        require(_amount > 0, "!>0");
        //lock immediately, transfer directly to strategy to skip an erc20 transfer
        IERC20(spirit).safeTransferFrom(msg.sender, address(this), _amount);
        _lockMoreSpirit(_amount);
        if (incentiveSpirit > 0) {
            //add the incentive tokens here so they can be staked together
            _amount = _amount.add(incentiveSpirit);
            incentiveSpirit = 0;
        }

        ILinSpirit(linSpirit).mint(msg.sender, _amount);
    }

    function depositAll() external {
        uint256 spiritBal = IERC20(spirit).balanceOf(msg.sender);
        _deposit(spiritBal);
    }

    function _deposit(uint256 _amount) internal {
        require(_amount > 0, "!>0");
        //lock immediately, transfer directly to strategy to skip an erc20 transfer
        IERC20(spirit).safeTransferFrom(msg.sender, address(this), _amount);
        _lockMoreSpirit(_amount);
        if (incentiveSpirit > 0) {
            //add the incentive tokens here so they can be staked together
            _amount = _amount.add(incentiveSpirit);
            incentiveSpirit = 0;
        }

        ILinSpirit(linSpirit).mint(msg.sender, _amount);
    }
}
