// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./subContracts.sol";

interface ILido {
    function submit(address referral) external payable returns (uint256);
}

contract cdtTokenRegistry {
    using SafeMath for uint256;

    // no need in v1 ?
    address private cdtMainAddress;
    address public stockTokenAddress;
    uint256 public alreadyBorrowedTotal;
    mapping(address => uint256) public alreadyStakedHolder;
    mapping(address => uint256) public alreadyBorrowedHolder;

    address constant LIDO_CONTRACT = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    // TBR after prototype, fundingentries store fundings for FE usage
    struct FundingEntry {
        uint256 blockNumber;
        uint256 amount;
    }
    FundingEntry[] public fundingEntries;
    uint256 public fundingsAmount;
    event FundsUpdated(uint256 fundsAdded, uint256 newFunds);
    // TBR

    event Staked(address staker, uint256 stakedAmount, uint256 newClaim);
    event StakedAndRestaked(
        address staker,
        uint256 stakedAmount,
        uint256 newClaim
    );
    event Restaked(address staker, uint256 restakeAmount);
    event TokensBurned(
        address burner,
        uint256 burnedAmount,
        uint256 paidAmount
    );
    event Unstaked(
        address staker,
        uint256 unstakedAmount,
        uint256 returnedAmount
    );

    
    constructor(address _cdtMainAddress, address _stockTokenAddress) public {
        cdtMainAddress = _cdtMainAddress;
        stockTokenAddress = _stockTokenAddress;
        // TBR
        fundingsAmount = 0;
        // TBR
    }

    receive() external payable {
        // TBR
        fund();
        // TBR
    }

    function getTotalFunds() public view returns (uint256) {
        return address(this).balance.add(alreadyBorrowedTotal);
    }

    // TBR
    function fund() public payable {
        require(msg.value > 0, "Invalid Ether value sent");

        uint256 newFundsTotal = getTotalFunds();

        fundingEntries.push(
            FundingEntry({blockNumber: block.number, amount: msg.value})
        );
        fundingsAmount++;

        emit FundsUpdated(msg.value, newFundsTotal);
    }

    // TBR

    function stake(uint256 amount) public {
        if (amount > 0) {
            require(
                IERC20(stockTokenAddress).transferFrom(
                    msg.sender,
                    address(this),
                    amount
                ),
                "ERC-20 transfer failed"
            );
        }

        uint256 newClaim = calculateRestake(msg.sender, amount);

        if (amount > 0) {
            alreadyStakedHolder[msg.sender] = alreadyStakedHolder[msg.sender]
                .add(amount);
        }

        if (newClaim > 0) {
            alreadyBorrowedHolder[msg.sender] = alreadyBorrowedHolder[
                msg.sender
            ].add(newClaim);
            alreadyBorrowedTotal = alreadyBorrowedTotal.add(newClaim);

            payable(msg.sender).transfer(newClaim);

            emit Staked(msg.sender, amount, newClaim);
        }
    }

    function calculateRestake(address staker, uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 alreadyStakedAmount = alreadyStakedHolder[staker];
        uint256 alreadyBorrowedAmount = alreadyBorrowedHolder[staker];

        uint256 fundsPerToken = calculateFundsPerToken(97);
        // new maxBorrow with raised stake
        uint256 maxBorrow = alreadyStakedAmount.add(amount).mul(fundsPerToken);

        if (maxBorrow <= alreadyBorrowedAmount) {
            return 0;
        } else {
            return maxBorrow.sub(alreadyBorrowedAmount);
        }
    }

    function unstakeByBorrowedAmount() public payable {
        uint256 borrowedAmountReturning = msg.value;

        uint256 stakedAmount = alreadyStakedHolder[msg.sender];
        uint256 borrowedAmount = alreadyBorrowedHolder[msg.sender];

        if (borrowedAmountReturning > 0) {
            alreadyBorrowedTotal = alreadyBorrowedTotal.sub(
                borrowedAmountReturning
            );
        }

        uint256 tokensToReturn = calculateUnstake(
            msg.sender,
            borrowedAmountReturning
        );

        if (borrowedAmountReturning > 0) {
            alreadyBorrowedHolder[msg.sender] = borrowedAmount.sub(
                borrowedAmountReturning
            );
        }

        if (tokensToReturn > 0) {
            require(
                IERC20(stockTokenAddress).transfer(msg.sender, tokensToReturn),
                "Token transfer failed"
            );
        }

        alreadyStakedHolder[msg.sender] = stakedAmount.sub(tokensToReturn);

        emit Unstaked(msg.sender, tokensToReturn, borrowedAmountReturning);
    }

    function calculateUnstake(address staker, uint256 borrowedAmountReturning)
        public
        view
        returns (uint256)
    {
        uint256 stakedAmount = alreadyStakedHolder[staker];
        uint256 borrowedAmount = alreadyBorrowedHolder[staker];

        if (borrowedAmount == 0) {
            return stakedAmount;
        }

        uint256 fundsPerToken = calculateFundsPerToken(97);

        // new min stake with lowered borrowed amount
        uint256 minStake = borrowedAmount.sub(borrowedAmountReturning).mul(
            fundsPerToken
        );

        if (minStake >= stakedAmount) {
            return 0;
        } else {
            return stakedAmount.sub(minStake);
        }
    }

    function calculateBurn(address staker, uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 stakedAmount = alreadyStakedHolder[staker];
        uint256 borrowedAmount = alreadyBorrowedHolder[staker];

        require(amount <= borrowedAmount, "Invalid amount to return");
        uint256 fundsPerToken = calculateFundsPerToken(100);

        uint256 maxStake = borrowedAmount.sub(amount).mul(fundsPerToken);

        if (maxStake >= stakedAmount) {
            return 0;
        } else {
            return stakedAmount.sub(maxStake);
        }
    }

    function burnStakedFrom(uint256 amount) public {
        uint256 stakedAmount = alreadyStakedHolder[msg.sender];
        uint256 borrowedAmount = alreadyBorrowedHolder[msg.sender];

        require(amount > 0, "Invalid amount to burn");
        require(amount <= stakedAmount, "Invalid amount to burn");

        // Step 1: Transfer tokens back to user
        IERC20(stockTokenAddress).transfer(msg.sender, amount);

        // Step 2: Burn tokens from user using previously given approval
        ERC20Burnable(stockTokenAddress).burnFrom(msg.sender, amount);

 
        uint256 fundsPerToken = calculateFundsPerToken(100);
        uint256 fundsToPay = amount.mul(fundsPerToken).sub(borrowedAmount);

        alreadyBorrowedTotal = alreadyBorrowedTotal.sub(fundsToPay);
        if (fundsToPay < borrowedAmount) {
            alreadyBorrowedHolder[msg.sender] = borrowedAmount.sub(fundsToPay);
        } else {
            alreadyBorrowedHolder[msg.sender] = 0;
        }

        payable(msg.sender).transfer(fundsToPay);

        emit TokensBurned(msg.sender, amount, fundsToPay);
    }

    function calculateFundsPerToken(uint256 reserve)
        public
        view
        returns (uint256)
    {
        uint256 totalSupply = IERC20(stockTokenAddress).totalSupply();
        uint256 funds = getTotalFunds();

        return totalSupply.mul(100).div(reserve).div(funds);
    }
}
