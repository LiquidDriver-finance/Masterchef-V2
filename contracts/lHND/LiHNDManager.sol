// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/ILiHNDStrategy.sol";
import "./interfaces/ILiHND.sol";

contract LiHNDManager is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public HND;
    uint256 public MAXTIME;
    uint256 public WEEK;

    address public feeManager;
    address public strategy;
    address public liHND;
    uint256 public incentiveHND;
    uint256 public unlockTime;

    constructor() public {}

    function initialize(
        address _strategy,
        address _liHND
    ) public initializer {
        __Ownable_init();
        feeManager = msg.sender;
        strategy = _strategy;
        liHND = _liHND;
        incentiveHND = 0;
        MAXTIME = 4 * 364 * 86400;
        WEEK = 7 * 86400;
        HND = address(0x10010078a54396F62c96dF8532dc2B4847d47ED3);
    }

    function initialLock() public {
        require(msg.sender == feeManager || msg.sender == address(this), "!auth");

        uint256 unlockAt = block.timestamp + MAXTIME;
        uint256 unlockInWeeks = (unlockAt / WEEK) * WEEK;

        //release old lock if exists
        ILiHNDStrategy(strategy).release();
        //create new lock
        uint256 hndBalanceStrategy = IERC20(HND).balanceOf(strategy);
        ILiHNDStrategy(strategy).createLock(hndBalanceStrategy, unlockAt);
        unlockTime = unlockInWeeks;
    }

    //lock more HND into the inSpirit contract
    function _lockMoreSpirit(uint256 _amount) internal {
        if (_amount > 0) {
            IERC20(HND).safeTransfer(strategy, _amount);
        }

        //increase amount
        if (_amount == 0) {
            return;
        }

        uint256 _strategyVeHNDBalance = ILiHNDStrategy(strategy).balanceOfVeHND();

        if (_strategyVeHNDBalance > 0) {
            //increase amount
            ILiHNDStrategy(strategy).increaseAmount(_amount);
        } else {
            initialLock();
        }
    }

    //deposit HND for liHND
    //can locking immediately or defer locking to someone else by paying a fee.
    //while users can choose to lock or defer, this is mostly in place so that
    //the cvx reward contract isnt costly to claim rewards

    function deposit(uint256 _amount) public {
        require(_amount > 0, "!>0");
        //lock immediately, transfer directly to strategy to skip an erc20 transfer
        IERC20(HND).safeTransferFrom(msg.sender, address(this), _amount);
        _lockMoreSpirit(_amount);
        if (incentiveHND > 0) {
            //add the incentive tokens here so they can be staked together
            _amount = _amount.add(incentiveHND);
            incentiveHND = 0;
        }

        ILiHND(liHND).mint(msg.sender, _amount);
    }

    function depositAll() external {
        uint256 HNDBal = IERC20(HND).balanceOf(msg.sender);
        deposit(HNDBal);
    }
}
