// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../linSpirit/interfaces/ILinSpiritStrategy.sol";

contract Voter is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public WEEK;
    address public xLQDR;
    address public linSpiritStrategy;

    mapping(uint256 => mapping(address => uint256)) public delegationAmount;
    mapping(uint256 => mapping(address => bool)) public delegated;
    mapping(uint256 => mapping(address => address)) public delegatedAddress;

    mapping(uint256 => mapping(address => uint256)) public inSpiritVote;
    mapping(uint256 => address[]) public inSpiritTokens;
    mapping(uint256 => mapping(address => bool)) public inSpiritTokensAdded;
    mapping(uint256 => mapping(address => bool)) public voted;

    mapping(address => mapping(uint256 => mapping(address => uint256))) public inSpiritVoteData;
    mapping(address => mapping(uint256 => address[])) public inSpiritVotedTokens;

    mapping(address => bool) public isVoter;

    address public defaultDelegate;

    constructor() public {}

    function initialize(
        address _xLQDR,
        address _linSpiritStrategy
    ) public initializer {
        __Ownable_init();
        xLQDR = _xLQDR;
        linSpiritStrategy = _linSpiritStrategy;
        WEEK = 7 days;
    }

    modifier restricted() {
        require(msg.sender == owner() || isVoter[msg.sender], "!Auth");
        _;
    }

    function enableVoter(address _voter) external onlyOwner {
        isVoter[_voter] = true;
    }

    function disableVoter(address _voter) external onlyOwner {
        isVoter[_voter] = false;
    }

    function setXLQDR(address _xLQDR) external onlyOwner {
        xLQDR = _xLQDR;
    }

    function setDefaultDelegate(address _delegate) external onlyOwner {
        defaultDelegate = _delegate;
    }

    function _reset(address _owner) internal {
        uint256 _thisWeek = thisWeek();
        address[] storage _votedTokens = inSpiritVotedTokens[_owner][_thisWeek];
        uint256 _tokenCnt = _votedTokens.length;

        for (uint256 i = 0; i < _tokenCnt; i++) {
            address _token = _votedTokens[i];
            inSpiritVote[_thisWeek][_token] = inSpiritVote[_thisWeek][_token]
                .sub(inSpiritVoteData[_owner][_thisWeek][_token]);
            inSpiritVoteData[_owner][_thisWeek][_token] = 0;
        }

        delete inSpiritVotedTokens[_owner][_thisWeek];
    }

    function _removeDelegation(address _owner) internal {
        uint256 _thisWeek = thisWeek();

        if (!delegated[_thisWeek][_owner]) {
            return;
        }

        address _delegatedAddress = delegatedAddress[_thisWeek][_owner];
        uint256 _voteWeight = IERC20(xLQDR).balanceOf(msg.sender);
        uint256 _delegationAmount = delegationAmount[_thisWeek][_delegatedAddress];

        delegationAmount[_thisWeek][_delegatedAddress] = _delegationAmount.sub(_voteWeight);
        
        _revote(delegatedAddress[_thisWeek][_owner]);

        delegatedAddress[_thisWeek][_owner] = address(0);
        delegated[_thisWeek][_owner] = false;
    }

    function _revote(address _owner) internal {
        uint256 _thisWeek = thisWeek();
        if (!voted[_thisWeek][_owner]) {
            return;
        }

        address[] memory _tokens = inSpiritVotedTokens[_owner][_thisWeek];
        uint256 _tokenCnt = _tokens.length;
        uint256[] memory _weights = new uint256[](_tokenCnt);

        for (uint256 i = 0; i < _tokenCnt; i ++) {
            address _token = _tokens[i];
            _weights[i] = inSpiritVoteData[_owner][_thisWeek][_token];
        }

        _vote(_owner, _tokens, _weights);
    }

    function vote(address[] memory _tokens, uint256[] memory _weights) public {
        _vote(msg.sender, _tokens, _weights);
    }

    function _vote(address _owner, address[] memory _tokens, uint256[] memory _weights) internal {
        uint256 _tokenCnt = _tokens.length;
        uint256 _voteWeight = IERC20(xLQDR).balanceOf(_owner);
        uint256 _thisWeek = thisWeek();

        if (delegated[_thisWeek][_owner]) {
            _removeDelegation(_owner);
        }

        _reset(_owner);

        _voteWeight = _voteWeight.add(delegationAmount[_thisWeek][_owner]);

        uint256 _totalWeight;
        for (uint256 i = 0; i < _tokenCnt; i++) {
            _totalWeight = _totalWeight.add(_weights[i]);
        }

        if (_voteWeight == 0 || _totalWeight == 0) {
            return;
        }

        for (uint256 i = 0; i < _tokenCnt; i++) {
            address _token = _tokens[i];
            uint256 _weight = _weights[i].mul(_voteWeight).div(_totalWeight);

            inSpiritVotedTokens[_owner][_thisWeek].push(_token);
            inSpiritVoteData[_owner][_thisWeek][_token] = _weight;
            inSpiritVote[_thisWeek][_token] = inSpiritVote[_thisWeek][_token].add(_weight);

            if (!inSpiritTokensAdded[_thisWeek][_token]) {
                inSpiritTokens[_thisWeek].push(_token);
                inSpiritTokensAdded[_thisWeek][_token] = true;
            }
        }

        voted[_thisWeek][_owner] = true;
    }

    function _delegate(address _owner, address _recipent) internal {
        require(_owner != _recipent, "Can not delegate yourself");
        uint256 _voteWeight = IERC20(xLQDR).balanceOf(_owner);
        uint256 _thisWeek = thisWeek();

        if (delegated[_thisWeek][_owner]) {
            _removeDelegation(_owner);
        }

        _reset(_owner);

        delegated[_thisWeek][_owner] = true;
        delegatedAddress[_thisWeek][_owner] = _recipent;
        delegationAmount[_thisWeek][_recipent] = delegationAmount[_thisWeek][_recipent].add(_voteWeight);

        _revote(_recipent);
    }

    function delegate(address _recipent) public {
        require(_recipent != address(0), "Recipent can't be null.");
        if (defaultDelegate != address(0)) {
            require(defaultDelegate == _recipent, "Recipent should be the default delegation address.");
        }
        _delegate(msg.sender, _recipent);
    }

    function voteInSpirit() external restricted {
        uint256 _thisWeek = thisWeek();

        address[] memory _tokens = inSpiritTokens[_thisWeek];
        uint256 _tokenCnt = _tokens.length;
        uint256[] memory _weights = new uint256[](_tokenCnt);

        for (uint256 i = 0; i < _tokenCnt; i ++) {
            address _token = _tokens[i];
            _weights[i] = inSpiritVote[_thisWeek][_token];
        }

        ILinSpiritStrategy(linSpiritStrategy).vote(_tokens, _weights);
    }

    function thisWeek() public view returns (uint256 _thisWeek) {
        _thisWeek = (block.timestamp / WEEK) * WEEK;
    }
}
