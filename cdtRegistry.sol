// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CDTStaking is ReentrancyGuard {
    uint256 public constant CLAIMABLE_PERCENT = 90;
    
    IERC20 public immutable cdtToken;
    uint256 public alreadyClaimedTotal;
    mapping(address => uint256) public userStakes;
    mapping(address => uint256) public userClaimed;
    uint256 public totalStaked;
    
    event Funded(address indexed funder, uint256 amount);
    event Staked(address indexed user, uint256 tokenAmount, uint256 ethRewards);
    event Claimed(address indexed user, uint256 ethAmount);
    event Unstaked(address indexed user, uint256 ethReturned, uint256 tokensReceived);
    event Burned(address indexed user, uint256 tokenAmount, uint256 ethRewards);
    event ClaimedAndStaked(address indexed user, uint256 tokenAmount, uint256 totalEthRewards);
    event UnstakedUnclaimed(address indexed user, uint256 tokenAmount);
    event BurnedNonStaked(address indexed user, uint256 tokenAmount, uint256 ethRewards);
    
    constructor(address cdtTokenAddress) {
        cdtToken = IERC20(cdtTokenAddress);
    }
    
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }
    
    function fund() external payable {
        emit Funded(msg.sender, msg.value);
    }
    
    function totalFunds() public view returns (uint256) {
        return address(this).balance + alreadyClaimedTotal;
    }
    
    function calculateStake(uint256 stakeAmount) public view returns (uint256) {
        uint256 cdtTotalSupply = cdtToken.totalSupply();
        uint256 totalFundsAmount = totalFunds();
        
        if (cdtTotalSupply == 0 || totalFundsAmount == 0) {
            return 0;
        }
        
        uint256 fullReward = (stakeAmount * totalFundsAmount) / cdtTotalSupply;
        return (fullReward * CLAIMABLE_PERCENT) / 100;
    }
    
    function calculateBurn(uint256 stakeAmount) public view returns (uint256) {
        uint256 cdtTotalSupply = cdtToken.totalSupply();
        uint256 totalFundsAmount = totalFunds();
        
        if (cdtTotalSupply == 0 || totalFundsAmount == 0) {
            return 0;
        }
        
        return (stakeAmount * totalFundsAmount) / cdtTotalSupply;
    }
    
    function getClaimableFunds(address user) public view returns (uint256) {
        uint256 totalClaimable = calculateStake(userStakes[user]);
        uint256 alreadyClaimed = userClaimed[user];
        
        if (totalClaimable <= alreadyClaimed) {
            return 0;
        }
        
        return totalClaimable - alreadyClaimed;
    }
    
    function stake(uint256 amount) external nonReentrant {
        _stake(amount);
    }
    
    function claim() external nonReentrant {
        _claim();
    }
    
    function unstake() external payable nonReentrant {
        _unstake();
    }
    
    function burn(uint256 amount) external nonReentrant {
        _burn(amount);
    }
    
    function _stake(uint256 amount) internal {
        uint256 claimableFunds = calculateStake(amount);
        
        userStakes[msg.sender] += amount;
        totalStaked += amount;
        alreadyClaimedTotal += claimableFunds;
        userClaimed[msg.sender] += claimableFunds;
        
        cdtToken.transferFrom(msg.sender, address(this), amount);
        
        if (claimableFunds > 0) {
            payable(msg.sender).transfer(claimableFunds);
        }
        
        emit Staked(msg.sender, amount, claimableFunds);
    }
    
    function _claim() internal {
        uint256 claimableFunds = getClaimableFunds(msg.sender);
        
        alreadyClaimedTotal += claimableFunds;
        userClaimed[msg.sender] += claimableFunds;
        
        if (claimableFunds > 0) {
            payable(msg.sender).transfer(claimableFunds);
        }
        
        emit Claimed(msg.sender, claimableFunds);
    }
    
    function _unstake() internal {
        uint256 ethReturned = msg.value;
        uint256 userClaimedAmount = userClaimed[msg.sender];
        uint256 userStakedAmount = userStakes[msg.sender];
        
        require(userStakedAmount > 0, "No tokens staked");
        require(ethReturned <= userClaimedAmount, "Cannot return more than claimed");
        
        uint256 tokensToReturn = (ethReturned * userStakedAmount) / userClaimedAmount;
        
        userStakes[msg.sender] -= tokensToReturn;
        totalStaked -= tokensToReturn;
        userClaimed[msg.sender] -= ethReturned;
        alreadyClaimedTotal -= ethReturned;
        
        cdtToken.transfer(msg.sender, tokensToReturn);
        
        emit Unstaked(msg.sender, ethReturned, tokensToReturn);
    }
    
    function _burn(uint256 amount) internal {
        require(userStakes[msg.sender] >= amount, "Insufficient staked tokens");
        
        uint256 burnFunds = calculateBurn(amount);
        
        userStakes[msg.sender] -= amount;
        totalStaked -= amount;
        alreadyClaimedTotal += burnFunds;
        
        cdtToken.transfer(msg.sender, amount);
        ERC20Burnable(address(cdtToken)).burnFrom(msg.sender, amount);
        
        if (burnFunds > 0) {
            payable(msg.sender).transfer(burnFunds);
        }
        
        emit Burned(msg.sender, amount, burnFunds);
    }
    
    // Experimental functions
    
    function calculateClaimAndStake(uint256 stakeAmount) public view returns (uint256 claimFunds, uint256 stakeFunds) {
        claimFunds = getClaimableFunds(msg.sender);
        stakeFunds = calculateStake(stakeAmount);
        return (claimFunds, stakeFunds);
    }
    
    function calculateUnstakeUnclaimed() public view returns (uint256) {
        uint256 userClaimedAmount = userClaimed[msg.sender];
        uint256 userStakedAmount = userStakes[msg.sender];
        
        if (userClaimedAmount == 0 || userStakedAmount == 0) {
            return 0;
        }
        
        uint256 tokensNeededToCoverClaims = (userClaimedAmount * cdtToken.totalSupply()) / (totalFunds() * CLAIMABLE_PERCENT / 100);
        
        if (tokensNeededToCoverClaims >= userStakedAmount) {
            return 0;
        }
        
        return userStakedAmount - tokensNeededToCoverClaims;
    }
    
    function claimAndStake(uint256 amount) external nonReentrant {
        _claimAndStake(amount);
    }
    
    function unstakeUnclaimed() external nonReentrant {
        _unstakeUnclaimed();
    }
    
    function burnNonStaked(uint256 amount) external nonReentrant {
        _burnNonStaked(amount);
    }
    
    function _claimAndStake(uint256 amount) internal {
        uint256 claimableFunds = getClaimableFunds(msg.sender);
        uint256 stakeFunds = calculateStake(amount);
        
        userClaimed[msg.sender] += claimableFunds;
        userStakes[msg.sender] += amount;
        totalStaked += amount;
        alreadyClaimedTotal += claimableFunds + stakeFunds;
        userClaimed[msg.sender] += stakeFunds;
        
        cdtToken.transferFrom(msg.sender, address(this), amount);
        
        uint256 totalFunds = claimableFunds + stakeFunds;
        if (totalFunds > 0) {
            payable(msg.sender).transfer(totalFunds);
        }
        
        emit ClaimedAndStaked(msg.sender, amount, totalFunds);
    }
    
    function _unstakeUnclaimed() internal {
        uint256 tokensToUnstake = calculateUnstakeUnclaimed();
        require(tokensToUnstake > 0, "No unclaimed tokens to unstake");
        
        userStakes[msg.sender] -= tokensToUnstake;
        totalStaked -= tokensToUnstake;
        
        cdtToken.transfer(msg.sender, tokensToUnstake);
        
        emit UnstakedUnclaimed(msg.sender, tokensToUnstake);
    }
    
    function _burnNonStaked(uint256 amount) internal {
        require(cdtToken.balanceOf(msg.sender) >= amount, "Insufficient token balance");
        
        uint256 burnFunds = calculateBurn(amount);
        
        alreadyClaimedTotal += burnFunds;
        
        ERC20Burnable(address(cdtToken)).burnFrom(msg.sender, amount);
        
        if (burnFunds > 0) {
            payable(msg.sender).transfer(burnFunds);
        }
        
        emit BurnedNonStaked(msg.sender, amount, burnFunds);
    }
}