// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./SimpleOracle.sol";
import { StatisticsUtils } from "../utils/StatisticsUtils.sol";

contract WhitelistOracle {
    using StatisticsUtils for uint256[];

    error OnlyOwner();
    error IndexOutOfBounds();
    error NoOraclesAvailable();

    address public owner;
    SimpleOracle[] public oracles;
    uint256 public constant STALE_DATA_WINDOW = 24 seconds;

    event OracleAdded(address oracleAddress, address oracleOwner);
    event OracleRemoved(address oracleAddress);

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function addOracle(address _owner) public onlyOwner {
        SimpleOracle newOracle = new SimpleOracle(_owner);
        oracles.push(newOracle);
        emit OracleAdded(address(newOracle), _owner);
    }

    function removeOracle(uint256 index) public onlyOwner {
        if (index >= oracles.length) revert IndexOutOfBounds();

        address oracleAddress = address(oracles[index]);

        if (index != oracles.length - 1) {
            oracles[index] = oracles[oracles.length - 1];
        }
        oracles.pop();

        emit OracleRemoved(oracleAddress);
    }

    function getPrice() public view returns (uint256) {
        if (oracles.length == 0) revert NoOraclesAvailable();

        uint256[] memory tempPrices = new uint256[](oracles.length);
        uint256 validCount = 0;

        for (uint256 i = 0; i < oracles.length; i++) {
            (uint256 price, uint256 timestamp) = oracles[i].getPrice();
            if (timestamp != 0 && block.timestamp - timestamp < STALE_DATA_WINDOW) {
                tempPrices[validCount] = price;
                validCount++;
            }
        }

        if (validCount == 0) revert NoOraclesAvailable();

        uint256[] memory validPrices = new uint256[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            validPrices[i] = tempPrices[i];
        }

        validPrices.sort();
        return validPrices.getMedian();
    }

    function getActiveOracleNodes() public view returns (address[] memory) {
        address[] memory tempNodes = new address[](oracles.length);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < oracles.length; i++) {
            (, uint256 timestamp) = oracles[i].getPrice();
            if (timestamp != 0 && block.timestamp - timestamp < STALE_DATA_WINDOW) {
                tempNodes[activeCount] = address(oracles[i]);
                activeCount++;
            }
        }

        address[] memory activeNodes = new address[](activeCount);
        for (uint256 i = 0; i < activeCount; i++) {
            activeNodes[i] = tempNodes[i];
        }

        return activeNodes;
    }
}
