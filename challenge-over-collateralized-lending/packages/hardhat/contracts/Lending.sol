// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Corn.sol";
import "./CornDEX.sol";

interface IFlashLoanRecipient {
    function executeOperation(uint256 amount, address initiator, address extraParam) external returns (bool);
}

contract Lending is Ownable {
    uint256 private constant COLLATERAL_RATIO = 120; // 120% collateralization required
    uint256 private constant LIQUIDATOR_REWARD = 10; // 10% reward for liquidators

    Corn private i_corn;
    CornDEX private i_cornDEX;

    mapping(address => uint256) public s_userCollateral; // Users collateral balance
    mapping(address => uint256) public s_userBorrowed; // Users borrowed corn balance

    event CollateralAdded(address indexed user, uint256 indexed amount, uint256 price);
    event CollateralWithdrawn(address indexed user, uint256 indexed amount, uint256 price);
    event AssetBorrowed(address indexed user, uint256 indexed amount, uint256 price);
    event AssetRepaid(address indexed user, uint256 indexed amount, uint256 price);
    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 amountForLiquidator,
        uint256 liquidatedUserDebt,
        uint256 price
    );

    error Lending__InvalidAmount();
    error Lending__TransferFailed();
    error Lending__UnsafePositionRatio();
    error Lending__BorrowingFailed();
    error Lending__RepayingFailed();
    error Lending__PositionSafe();
    error Lending__NotLiquidatable();
    error Lending__InsufficientLiquidatorCorn();

    constructor(address _cornDEX, address _corn) Ownable(msg.sender) {
        i_cornDEX = CornDEX(_cornDEX);
        i_corn = Corn(_corn);
        i_corn.approve(address(this), type(uint256).max);
    }

    /**
     * @notice Allows users to add collateral to their account
     */
    function addCollateral() public payable {
        if (msg.value == 0) {
            revert Lending__InvalidAmount();
        }
        s_userCollateral[msg.sender] += msg.value;
        emit CollateralAdded(msg.sender, msg.value, i_cornDEX.currentPrice());
    }

    /**
     * @notice Allows users to withdraw collateral as long as it doesnt make them liquidatable
     * @param amount The amount of collateral to withdraw
     */
    function withdrawCollateral(uint256 amount) public {
        if (amount == 0 || s_userCollateral[msg.sender] < amount) {
            revert Lending__InvalidAmount();
        }

        s_userCollateral[msg.sender] -= amount;

        if (s_userBorrowed[msg.sender] > 0) {
            _validatePosition(msg.sender);
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert Lending__TransferFailed();
        }

        emit CollateralWithdrawn(msg.sender, amount, i_cornDEX.currentPrice());
    }

    /**
     * @notice Calculates the total collateral value for a user based on their collateral balance
     * @param user The address of the user to calculate the collateral value for
     * @return uint256 The collateral value
     */
    function calculateCollateralValue(address user) public view returns (uint256) {
        uint256 collateralAmount = s_userCollateral[user];
        return (collateralAmount * i_cornDEX.currentPrice()) / 1e18;
    }

    /**
     * @notice Calculates the position ratio for a user to ensure they are within safe limits
     * @param user The address of the user to calculate the position ratio for
     * @return uint256 The position ratio
     */
    function _calculatePositionRatio(address user) internal view returns (uint256) {
        uint256 borrowedAmount = s_userBorrowed[user];
        uint256 collateralValue = calculateCollateralValue(user);
        if (borrowedAmount == 0) return type(uint256).max;
        return (collateralValue * 1e18) / borrowedAmount;
    }

    /**
     * @notice Checks if a user's position can be liquidated
     * @param user The address of the user to check
     * @return bool True if the position is liquidatable, false otherwise
     */
    function isLiquidatable(address user) public view returns (bool) {
        uint256 positionRatio = _calculatePositionRatio(user);
        return (positionRatio * 100) < COLLATERAL_RATIO * 1e18;
    }

    /**
     * @notice Internal view method that reverts if a user's position is unsafe
     * @param user The address of the user to validate
     */
    function _validatePosition(address user) internal view {
        if (isLiquidatable(user)) {
            revert Lending__UnsafePositionRatio();
        }
    }

    /**
     * @notice Allows users to borrow corn based on their collateral
     * @param borrowAmount The amount of corn to borrow
     */
    function borrowCorn(uint256 borrowAmount) public {
        if (borrowAmount == 0) {
            revert Lending__InvalidAmount();
        }
        s_userBorrowed[msg.sender] += borrowAmount;
        _validatePosition(msg.sender);

        bool success = i_corn.transferFrom(address(this), msg.sender, borrowAmount);
        if (!success) {
            revert Lending__BorrowingFailed();
        }

        emit AssetBorrowed(msg.sender, borrowAmount, i_cornDEX.currentPrice());
    }

    /**
     * @notice Allows users to repay corn and reduce their debt
     * @param repayAmount The amount of corn to repay
     */
    function repayCorn(uint256 repayAmount) public {
        if (repayAmount == 0 || repayAmount > s_userBorrowed[msg.sender]) {
            revert Lending__InvalidAmount();
        }
        s_userBorrowed[msg.sender] -= repayAmount;

        bool success = i_corn.transferFrom(msg.sender, address(this), repayAmount);
        if (!success) {
            revert Lending__RepayingFailed();
        }

        emit AssetRepaid(msg.sender, repayAmount, i_cornDEX.currentPrice());
    }

    /**
     * @notice Allows liquidators to liquidate unsafe positions
     * @param user The address of the user to liquidate
     */
    function liquidate(address user) public {
        if (!isLiquidatable(user)) {
            revert Lending__NotLiquidatable();
        }

        uint256 userDebt = s_userBorrowed[user];
        if (i_corn.balanceOf(msg.sender) < userDebt) {
            revert Lending__InsufficientLiquidatorCorn();
        }

        uint256 userCollateral = s_userCollateral[user];
        uint256 collateralValue = calculateCollateralValue(user);

        bool success = i_corn.transferFrom(msg.sender, address(this), userDebt);
        if (!success) {
            revert Lending__RepayingFailed();
        }

        s_userBorrowed[user] = 0;

        uint256 collateralPurchased = (userDebt * userCollateral) / collateralValue;
        uint256 liquidatorReward = (collateralPurchased * LIQUIDATOR_REWARD) / 100;
        uint256 amountForLiquidator = collateralPurchased + liquidatorReward;
        amountForLiquidator = amountForLiquidator > userCollateral ? userCollateral : amountForLiquidator;

        s_userCollateral[user] = userCollateral - amountForLiquidator;

        (bool sent, ) = payable(msg.sender).call{value: amountForLiquidator}("");
        if (!sent) {
            revert Lending__TransferFailed();
        }

        emit Liquidation(user, msg.sender, amountForLiquidator, userDebt, i_cornDEX.currentPrice());
    }

    function flashLoan(IFlashLoanRecipient _recipient, uint256 _amount, address _extraParam) public {
        i_corn.transfer(address(_recipient), _amount);
        bool ok = _recipient.executeOperation(_amount, msg.sender, _extraParam);
        require(ok, "Operation was unsuccessful");
        i_corn.transferFrom(address(_recipient), address(this), _amount);
    }

    function getMaxBorrowAmount(uint256 ethCollateralAmount) public view returns (uint256) {
        if (ethCollateralAmount == 0) return 0;
        uint256 collateralValue = (ethCollateralAmount * i_cornDEX.currentPrice()) / 1e18;
        return (collateralValue * 100) / COLLATERAL_RATIO;
    }

    function getMaxWithdrawableCollateral(address user) public view returns (uint256) {
        uint256 borrowedAmount = s_userBorrowed[user];
        uint256 userCollateral = s_userCollateral[user];
        if (borrowedAmount == 0) return userCollateral;

        uint256 maxBorrowedAmount = getMaxBorrowAmount(userCollateral);
        if (borrowedAmount == maxBorrowedAmount) return 0;

        uint256 potentialBorrowingAmount = maxBorrowedAmount - borrowedAmount;
        uint256 ethValueOfPotentialBorrowingAmount = (potentialBorrowingAmount * 1e18) / i_cornDEX.currentPrice();

        return (ethValueOfPotentialBorrowingAmount * COLLATERAL_RATIO) / 100;
    }
}
