// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    IERC20 public token;
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    /* ========== EVENTS ========== */

    event EthToTokenSwap(address swapper, uint256 tokenOutput, uint256 ethInput);
    event TokenToEthSwap(address swapper, uint256 tokensInput, uint256 ethOutput);
    event LiquidityProvided(address liquidityProvider, uint256 liquidityMinted, uint256 ethInput, uint256 tokensInput);
    event LiquidityRemoved(
        address liquidityRemover,
        uint256 liquidityWithdrawn,
        uint256 tokensOutput,
        uint256 ethOutput
    );

    /* ========== ERRORS ========== */

    error DexAlreadyInitialized();
    error TokenTransferFailed();
    error InvalidEthAmount();
    error InvalidTokenAmount();
    error InsufficientTokenBalance(uint256 available, uint256 required);
    error InsufficientTokenAllowance(uint256 available, uint256 required);
    error EthTransferFailed(address to, uint256 amount);
    error InsufficientLiquidity(uint256 available, uint256 required);

    /* ========== CONSTRUCTOR ========== */

    constructor(address tokenAddr) {
        token = IERC20(tokenAddr);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // 1. Первичная инициализация пула ликвидности
    function init(uint256 tokens) public payable returns (uint256) {
        if (totalLiquidity != 0) revert DexAlreadyInitialized();

        totalLiquidity = address(this).balance;
        liquidity[msg.sender] = totalLiquidity;

        if (!token.transferFrom(msg.sender, address(this), tokens)) revert TokenTransferFailed();
        return totalLiquidity;
    }

    // 2. Формула расчета цены AMM (x * y = k) с комиссией 0.3%
    function price(
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public pure returns (uint256 yOutput) {
        uint256 xInputWithFee = xInput * 997;
        uint256 numerator = xInputWithFee * yReserves;
        uint256 denominator = (xReserves * 1000) + xInputWithFee;
        return (numerator / denominator);
    }

    // 3. Просмотр доли ликвидности пользователя
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    // 4. Обмен ETH -> $BAL
    function ethToToken() public payable returns (uint256 tokenOutput) {
        if (msg.value == 0) revert InvalidEthAmount();

        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));
        tokenOutput = price(msg.value, ethReserve, tokenReserve);

        if (!token.transfer(msg.sender, tokenOutput)) revert TokenTransferFailed();

        emit EthToTokenSwap(msg.sender, tokenOutput, msg.value);
        return tokenOutput;
    }

    // 5. Обмен $BAL -> ETH (требует предварительного approve)
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        if (tokenInput == 0) revert InvalidTokenAmount();

        uint256 userBalance = token.balanceOf(msg.sender);
        if (userBalance < tokenInput) revert InsufficientTokenBalance(userBalance, tokenInput);

        uint256 userAllowance = token.allowance(msg.sender, address(this));
        if (userAllowance < tokenInput) revert InsufficientTokenAllowance(userAllowance, tokenInput);

        uint256 tokenReserve = token.balanceOf(address(this));
        ethOutput = price(tokenInput, tokenReserve, address(this).balance);

        if (!token.transferFrom(msg.sender, address(this), tokenInput)) revert TokenTransferFailed();

        (bool sent, ) = msg.sender.call{value: ethOutput}("");
        if (!sent) revert EthTransferFailed(msg.sender, ethOutput);

        emit TokenToEthSwap(msg.sender, tokenInput, ethOutput);
        return ethOutput;
    }

    // 6. Добавление ликвидности в пул (ETH + $BAL в пропорции резервов)
    function deposit() public payable returns (uint256 tokensDeposited) {
        if (msg.value == 0) revert InvalidEthAmount();

        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));

        uint256 tokenDeposit = ((msg.value * tokenReserve) / ethReserve) + 1;

        uint256 userBalance = token.balanceOf(msg.sender);
        if (userBalance < tokenDeposit) revert InsufficientTokenBalance(userBalance, tokenDeposit);

        uint256 userAllowance = token.allowance(msg.sender, address(this));
        if (userAllowance < tokenDeposit) revert InsufficientTokenAllowance(userAllowance, tokenDeposit);

        uint256 liquidityMinted = (msg.value * totalLiquidity) / ethReserve;
        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;

        if (!token.transferFrom(msg.sender, address(this), tokenDeposit)) revert TokenTransferFailed();

        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokenDeposit);
        return tokenDeposit;
    }

    // 7. Вывод ликвидности из пула обратно на кошелек
    function withdraw(uint256 amount) public returns (uint256 ethAmount, uint256 tokenAmount) {
        if (liquidity[msg.sender] < amount) revert InsufficientLiquidity(liquidity[msg.sender], amount);

        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));

        uint256 ethWithdrawn = (amount * ethReserve) / totalLiquidity;
        tokenAmount = (amount * tokenReserve) / totalLiquidity;

        liquidity[msg.sender] -= amount;
        totalLiquidity -= amount;

        (bool sent, ) = payable(msg.sender).call{value: ethWithdrawn}("");
        if (!sent) revert EthTransferFailed(msg.sender, ethWithdrawn);

        if (!token.transfer(msg.sender, tokenAmount)) revert TokenTransferFailed();

        emit LiquidityRemoved(msg.sender, amount, tokenAmount, ethWithdrawn);
        return (ethWithdrawn, tokenAmount);
    }
}