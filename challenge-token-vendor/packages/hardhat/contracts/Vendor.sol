// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./YourToken.sol";

contract Vendor is Ownable {
    YourToken public yourToken;
    uint256 public constant tokensPerEth = 100;

    event BuyTokens(address indexed buyer, uint256 amountOfETH, uint256 amountOfTokens);
    event SellTokens(address indexed seller, uint256 amountOfTokens, uint256 amountOfETH);

    error InvalidEthAmount();
    error InsufficientVendorTokenBalance(uint256 available, uint256 required);
    error EthTransferFailed(address to, uint256 amount);
    error InvalidTokenAmount();
    error InsufficientVendorEthBalance(uint256 available, uint256 required);

    constructor(address tokenAddress) Ownable(msg.sender) {
        yourToken = YourToken(tokenAddress);
    }

    // 1. Покупка токенов за ETH
    function buyTokens() public payable {
        if (msg.value == 0) revert InvalidEthAmount();

        uint256 tokensToBuy = msg.value * tokensPerEth;
        uint256 vendorBalance = yourToken.balanceOf(address(this));

        if (vendorBalance < tokensToBuy) {
            revert InsufficientVendorTokenBalance(vendorBalance, tokensToBuy);
        }

        yourToken.transfer(msg.sender, tokensToBuy);
        emit BuyTokens(msg.sender, msg.value, tokensToBuy);
    }

    // 2. Вывод накопленного ETH владельцем контракта
    function withdraw() public onlyOwner {
        uint256 amount = address(this).balance;
        (bool ok, ) = owner().call{value: amount}("");
        if (!ok) revert EthTransferFailed(owner(), amount);
    }

    // 3. Обратный выкуп токенов у пользователя за ETH (требует предварительного approve)
    function sellTokens(uint256 amount) public {
        if (amount == 0) revert InvalidTokenAmount();

        uint256 ethToReturn = amount / tokensPerEth;
        uint256 vendorEthBalance = address(this).balance;

        if (vendorEthBalance < ethToReturn) {
            revert InsufficientVendorEthBalance(vendorEthBalance, ethToReturn);
        }

        yourToken.transferFrom(msg.sender, address(this), amount);

        (bool ok, ) = payable(msg.sender).call{value: ethToReturn}("");
        if (!ok) revert EthTransferFailed(msg.sender, ethToReturn);

        emit SellTokens(msg.sender, amount, ethToReturn);
    }
}