//make 1% devidendFEE changeable/votable by main holders and registered will fetch it
//make 1% devidendFEE individual for each registered token and registered will fetch it
//make 1% devidendFEE changeable by "devidendFEE" token holding on registered token contract
//make 90% borrowAmount changeable by "borrowAmount" token holding on registered token contract or staker

// register token with minimal initial funds
// payment for registering token

pragma solidity ^0.6.0;

import "./subContracts.sol";
import "./cdtTokenRegistry.sol";

contract cdtMain is ERC20Capped, ERC20Burnable {
    address[] public registeredTokensList;
    uint256 public alreadyBorrowedTotal;
    uint256 public alreadyStakedTotal;
    mapping(address => address) public tokenRegistry;
    mapping(address => uint256) public alreadyStakedHolder;
    mapping(address => uint256) public alreadyBorrowedHolder;

    event FundsUpdated(uint256 fundsAdded, uint256 newFunds);
    event Staked(address staker, uint256 stakedAmount, uint256 newBorrow);
    event StakedAndRestaked(
        address staker,
        uint256 stakedAmount,
        uint256 newBorrow
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
        uint256 withdrawnAmount
    );

    event NewTokenRegistered(
        address indexed registeredTokenAddress,
        address indexed cdtTokenRegistryAddress
    );

    /**
     * @param name Name of the token
     * @param symbol A symbol to be used as ticker
     * @param decimals Number of decimals. All the operations are done using the smallest and indivisible token unit
     * @param cap Maximum number of tokens mintable
     * @param initialSupply Initial token supply
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 cap,
        uint256 initialSupply
    ) public ERC20(name, symbol) ERC20Capped(cap) {
        _setupDecimals(decimals);
        _mint(_msgSender(), initialSupply);
    }

    receive() external payable {}

    function fund() external payable {}

    function mint(address to) public payable {
        uint256 number = msg.value.mul(totalSupply()).div(
            address(this).balance.sub(msg.value)
        );
        _mint(to, number);
    }

    function transfer(
        address to,
        uint256 value
    ) public virtual override(ERC20) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual override(ERC20) returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function valueOfTokens(uint256 amount) public view returns (uint256) {
        return address(this).balance.mul(amount).div(totalSupply());
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Capped) {
        super._beforeTokenTransfer(from, to, amount);
    }

    function registerToken(address tokenAddress) external returns (address) {

        require(
            tokenRegistry[tokenAddress] == address(0),
            "Token already registered"
        );

        bytes memory bytecode = abi.encodePacked(
            type(cdtTokenRegistry).creationCode,
            abi.encode(address(this), tokenAddress)
        );

        address deployedContract;
        assembly {
            deployedContract := create2(
                0,
                add(bytecode, 0x20),
                mload(bytecode),
                0
            )
        }

        tokenRegistry[tokenAddress] = deployedContract;
        registeredTokensList.push(tokenAddress);

        require(deployedContract != address(0), "Contract deployment failed");
        emit NewTokenRegistered(tokenAddress, deployedContract);

        return deployedContract;
    }

     function getTotalFunds() public view returns (uint256) {
        return address(this).balance.add(alreadyBorrowedTotal);
    }

//tbr
    function getAllTokenRegistryEntries()
        external
        view
        returns (address[] memory, address[] memory)
    {
        address[] memory keys = new address[](registeredTokensList.length);
        address[] memory values = new address[](registeredTokensList.length);

        for (uint256 i = 0; i < registeredTokensList.length; i++) {
            address tokenAddress = registeredTokensList[i];
            keys[i] = tokenAddress;
            values[i] = tokenRegistry[tokenAddress];
        }

        return (keys, values);
    }

    function stake(uint256 amount) public {
        if (amount > 0) {
            // Transfer tokens from sender to contract
            require(
                IERC20(address(this)).transferFrom(
                    msg.sender,
                    address(this),
                    amount
                ),
                "ERC-20 transfer failed"
            );
        }

        uint256 newBorrow = calculateRestake(msg.sender, amount);

        if (amount > 0) {
            alreadyStakedTotal = alreadyStakedTotal.add(amount);
            alreadyStakedHolder[msg.sender] = alreadyStakedHolder[msg.sender]
                .add(amount);
        }

        if (newBorrow > 0) {

            alreadyBorrowedHolder[msg.sender] = alreadyBorrowedHolder[
                msg.sender
            ].add(newBorrow);
            alreadyBorrowedTotal = alreadyBorrowedTotal.add(newBorrow);

            payable(msg.sender).transfer(newBorrow);

            emit Staked(msg.sender, amount, newBorrow);
        }
    }

    function calculateRestake(address staker, uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 totalSupply = IERC20(address(this)).totalSupply();
        uint256 stakedAmountTotal = alreadyStakedTotal;
        uint256 alreadyStakedAmount = alreadyStakedHolder[staker];
        uint256 alreadyBorrowedAmount = alreadyBorrowedHolder[staker];

        require(
            amount <= totalSupply.sub(stakedAmountTotal),
            "Invalid amount to stake"
        );

        //potential overflow?
        uint256 maxBorrow = alreadyStakedAmount
            .add(amount)
            .mul(getTotalFunds())
            .mul(90)
            .div(100)
            .div(totalSupply);

        if (maxBorrow <= alreadyBorrowedAmount) {
            return 0;
        } else {
            return maxBorrow.sub(alreadyBorrowedAmount);
        }
    }

    //check burn
    //override?
    function burn(uint256 amount) public override {
        require(amount > 0, "Invalid amount to burn");
        //test burn
        require(
            IERC20(address(this)).transferFrom(msg.sender, address(0), amount),
            "ERC-20 transfer failed"
        );
        uint256 totalSupply = IERC20(address(this)).totalSupply();
        uint256 funds = getTotalFunds();
        uint256 fundsToPay = funds.mul(amount).div(totalSupply);

        payable(msg.sender).transfer(fundsToPay);
        alreadyBorrowedTotal = alreadyBorrowedTotal.sub(fundsToPay);

        emit TokensBurned(msg.sender, amount, fundsToPay);
    }

   // I want to return BorrowedTokenamount to get some staked tokens back
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

        require(
            IERC20(address(this)).transfer(msg.sender, tokensToReturn),
            "Token transfer failed"
        );

        alreadyStakedHolder[msg.sender] = stakedAmount.sub(tokensToReturn);
        alreadyStakedTotal = alreadyStakedTotal.sub(tokensToReturn);

        emit Unstaked(msg.sender, tokensToReturn, borrowedAmountReturning);
    }

    function calculateUnstake(
        address staker,
        uint256 amount //I will return this many eth
    ) public view returns (uint256) {
        uint256 totalSupply = IERC20(address(this)).totalSupply();
        uint256 stakedAmount = alreadyStakedHolder[staker];
        uint256 borrowedAmount = alreadyBorrowedHolder[staker];
        uint256 funds = getTotalFunds();

        require(amount <= borrowedAmount, "Invalid amount to return");

        //potential overflow?
        uint256 maxStake = borrowedAmount
            .sub(amount)
            .mul(100)
            .mul(totalSupply)
            .div(90)
            .div(funds);

        if (maxStake >= stakedAmount) {
            return 0;
        } else {
            return stakedAmount.sub(maxStake);
        }
    }

   
}
