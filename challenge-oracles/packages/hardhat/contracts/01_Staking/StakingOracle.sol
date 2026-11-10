// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { ORA } from "./OracleToken.sol";
import { StatisticsUtils } from "../utils/StatisticsUtils.sol";

contract StakingOracle {
    using StatisticsUtils for uint256[];

    error NodeNotRegistered();
    error InsufficientStake();
    error NodeAlreadyRegistered();
    error InvalidPrice();
    error AlreadyReportedInCurrentBucket();
    error NodeAlreadySlashed();
    error WaitingPeriodNotOver();
    error NoRewardsAvailable();
    error IndexOutOfBounds();
    error NodeNotAtGivenIndex();
    error TransferFailed();
    error OnlyPastBucketsAllowed();
    error BucketMedianAlreadyRecorded();
    error MedianNotRecorded();
    error NotDeviated();

    ORA public oracleToken;

    struct OracleNode {
        uint256 stakedAmount;
        uint256 lastReportedBucket;
        uint256 reportCount;
        uint256 claimedReportCount;
        uint256 firstBucket;
        bool active;
    }

    struct BlockBucket {
        mapping(address => bool) slashedOffenses;
        address[] reporters;
        uint256[] prices;
        uint256 medianPrice;
    }

    mapping(address => OracleNode) public nodes;
    mapping(uint256 => BlockBucket) public blockBuckets;
    address[] public nodeAddresses;

    uint256 public constant MINIMUM_STAKE = 100 ether;
    uint256 public constant BUCKET_WINDOW = 24;
    uint256 public constant SLASHER_REWARD_PERCENTAGE = 10;
    uint256 public constant REWARD_PER_REPORT = 1 ether;
    uint256 public constant INACTIVITY_PENALTY = 1 ether;
    uint256 public constant MISREPORT_PENALTY = 100 ether;
    uint256 public constant MAX_DEVIATION_BPS = 1000;
    uint256 public constant WAITING_PERIOD = 2;

    event NodeRegistered(address indexed node, uint256 stakedAmount);
    event PriceReported(address indexed node, uint256 price, uint256 bucketNumber);
    event BucketMedianRecorded(uint256 indexed bucketNumber, uint256 medianPrice);
    event NodeSlashed(address indexed node, uint256 amount);
    event NodeRewarded(address indexed node, uint256 amount);
    event StakeAdded(address indexed node, uint256 amount);
    event NodeExited(address indexed node, uint256 amount);

    modifier onlyNode() {
        if (!nodes[msg.sender].active) revert NodeNotRegistered();
        _;
    }

    constructor(address payable _oracleToken) {
        oracleToken = ORA(_oracleToken);
    }

    function getCurrentBucketNumber() public view returns (uint256) {
        return (block.number / BUCKET_WINDOW) + 1;
    }

    function getNodeAddresses() public view returns (address[] memory) {
        return nodeAddresses;
    }

    function registerNode(uint256 amount) public {
        if (amount < MINIMUM_STAKE) revert InsufficientStake();
        if (nodes[msg.sender].active) revert NodeAlreadyRegistered();

        if (!oracleToken.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        nodes[msg.sender] = OracleNode({
            stakedAmount: amount,
            lastReportedBucket: 0,
            reportCount: 0,
            claimedReportCount: 0,
            firstBucket: getCurrentBucketNumber(),
            active: true
        });

        nodeAddresses.push(msg.sender);
        emit NodeRegistered(msg.sender, amount);
    }

    function addStake(uint256 amount) public onlyNode {
        if (amount == 0) revert InsufficientStake();
        if (!oracleToken.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        nodes[msg.sender].stakedAmount += amount;
        emit StakeAdded(msg.sender, amount);
    }

    function getEffectiveStake(address nodeAddress) public view returns (uint256) {
        OracleNode memory node = nodes[nodeAddress];
        if (!node.active) return 0;

        uint256 currentBucket = getCurrentBucketNumber();
        if (currentBucket <= node.firstBucket) return node.stakedAmount;

        uint256 expectedReports = currentBucket - node.firstBucket;
        uint256 completedReports = node.reportCount;

        if (node.lastReportedBucket == currentBucket && completedReports > 0) {
            completedReports -= 1;
        }

        if (completedReports >= expectedReports) return node.stakedAmount;

        uint256 missedReports = expectedReports - completedReports;
        uint256 penalty = missedReports * INACTIVITY_PENALTY;

        if (penalty >= node.stakedAmount) return 0;
        return node.stakedAmount - penalty;
    }

    function reportPrice(uint256 price) public onlyNode {
        if (price == 0) revert InvalidPrice();
        if (getEffectiveStake(msg.sender) < MINIMUM_STAKE) revert InsufficientStake();

        uint256 currentBucket = getCurrentBucketNumber();
        OracleNode storage node = nodes[msg.sender];

        if (node.lastReportedBucket == currentBucket) revert AlreadyReportedInCurrentBucket();

        BlockBucket storage bucket = blockBuckets[currentBucket];
        bucket.reporters.push(msg.sender);
        bucket.prices.push(price);

        node.lastReportedBucket = currentBucket;
        node.reportCount += 1;

        emit PriceReported(msg.sender, price, currentBucket);
    }

    function claimReward() public {
        OracleNode storage node = nodes[msg.sender];
        uint256 delta = node.reportCount - node.claimedReportCount;
        if (delta == 0) revert NoRewardsAvailable();

        node.claimedReportCount = node.reportCount;
        uint256 rewardAmount = delta * REWARD_PER_REPORT;

        oracleToken.mint(msg.sender, rewardAmount);
        emit NodeRewarded(msg.sender, rewardAmount);
    }

    function recordBucketMedian(uint256 bucketNumber) public {
        if (bucketNumber >= getCurrentBucketNumber() || bucketNumber == 0) revert OnlyPastBucketsAllowed();

        BlockBucket storage bucket = blockBuckets[bucketNumber];
        if (bucket.medianPrice != 0) revert BucketMedianAlreadyRecorded();

        uint256[] memory pricesCopy = bucket.prices;
        pricesCopy.sort();
        uint256 median = pricesCopy.getMedian();

        bucket.medianPrice = median;
        emit BucketMedianRecorded(bucketNumber, median);
    }

    function getLatestPrice() public view returns (uint256) {
        return getPastPrice(getCurrentBucketNumber() - 1);
    }

    function getPastPrice(uint256 bucketNumber) public view returns (uint256) {
        uint256 median = blockBuckets[bucketNumber].medianPrice;
        if (median == 0) revert MedianNotRecorded();
        return median;
    }

    function getSlashedStatus(
        address nodeAddress,
        uint256 bucketNumber
    ) public view returns (uint256 reportedPrice, bool slashed) {
        BlockBucket storage bucket = blockBuckets[bucketNumber];
        for (uint256 i = 0; i < bucket.reporters.length; i++) {
            if (bucket.reporters[i] == nodeAddress) {
                return (bucket.prices[i], bucket.slashedOffenses[nodeAddress]);
            }
        }
        return (0, bucket.slashedOffenses[nodeAddress]);
    }

    function _checkPriceDeviated(uint256 reportedPrice, uint256 medianPrice) internal pure returns (bool) {
        uint256 deviation = reportedPrice > medianPrice ? reportedPrice - medianPrice : medianPrice - reportedPrice;
        uint256 deviationBps = (deviation * 10_000) / medianPrice;
        return deviationBps > MAX_DEVIATION_BPS;
    }

    function getOutlierNodes(uint256 bucketNumber) public view returns (address[] memory) {
        BlockBucket storage bucket = blockBuckets[bucketNumber];
        if (bucket.medianPrice == 0) revert MedianNotRecorded();

        address[] memory tempOutliers = new address[](bucket.reporters.length);
        uint256 count = 0;

        for (uint256 i = 0; i < bucket.reporters.length; i++) {
            address reporter = bucket.reporters[i];
            if (!bucket.slashedOffenses[reporter] && _checkPriceDeviated(bucket.prices[i], bucket.medianPrice)) {
                tempOutliers[count] = reporter;
                count++;
            }
        }

        address[] memory outliers = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            outliers[i] = tempOutliers[i];
        }
        return outliers;
    }

    function _removeNode(address nodeAddress, uint256 index) internal {
        if (index >= nodeAddresses.length) revert IndexOutOfBounds();
        if (nodeAddresses[index] != nodeAddress) revert NodeNotAtGivenIndex();

        if (index != nodeAddresses.length - 1) {
            nodeAddresses[index] = nodeAddresses[nodeAddresses.length - 1];
        }
        nodeAddresses.pop();
        nodes[nodeAddress].active = false;
    }

    function slashNode(
        address nodeToSlash,
        uint256 bucketNumber,
        uint256 reportIndex,
        uint256 nodeAddressesIndex
    ) public {
        if (bucketNumber >= getCurrentBucketNumber() || bucketNumber == 0) revert OnlyPastBucketsAllowed();

        BlockBucket storage bucket = blockBuckets[bucketNumber];
        if (bucket.medianPrice == 0) revert MedianNotRecorded();
        if (bucket.slashedOffenses[nodeToSlash]) revert NodeAlreadySlashed();

        if (reportIndex >= bucket.reporters.length) revert IndexOutOfBounds();
        if (bucket.reporters[reportIndex] != nodeToSlash) revert NodeNotAtGivenIndex();

        if (nodeAddressesIndex >= nodeAddresses.length) revert IndexOutOfBounds();
        if (nodeAddresses[nodeAddressesIndex] != nodeToSlash) revert NodeNotAtGivenIndex();

        if (!_checkPriceDeviated(bucket.prices[reportIndex], bucket.medianPrice)) revert NotDeviated();

        bucket.slashedOffenses[nodeToSlash] = true;

        OracleNode storage node = nodes[nodeToSlash];
        uint256 penalty = MISREPORT_PENALTY > node.stakedAmount ? node.stakedAmount : MISREPORT_PENALTY;
        node.stakedAmount -= penalty;

        if (getEffectiveStake(nodeToSlash) == 0) {
            _removeNode(nodeToSlash, nodeAddressesIndex);
        }

        uint256 reward = (penalty * SLASHER_REWARD_PERCENTAGE) / 100;
        if (!oracleToken.transfer(msg.sender, reward)) revert TransferFailed();

        emit NodeSlashed(nodeToSlash, penalty);
    }

    function exitNode(uint256 index) public onlyNode {
        OracleNode storage node = nodes[msg.sender];
        if (node.lastReportedBucket + WAITING_PERIOD > getCurrentBucketNumber()) revert WaitingPeriodNotOver();

        uint256 stakeToWithdraw = getEffectiveStake(msg.sender);
        _removeNode(msg.sender, index);
        node.stakedAmount = 0;

        if (stakeToWithdraw > 0) {
            if (!oracleToken.transfer(msg.sender, stakeToWithdraw)) revert TransferFailed();
        }

        emit NodeExited(msg.sender, stakeToWithdraw);
    }
}
