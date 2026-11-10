// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

contract OptimisticOracle {
    error InvalidValue();
    error InvalidTime();
    error AssertionNotFound();
    error AssertionProposed();
    error NotProposedAssertion();
    error ProposalDisputed();
    error NotDisputedAssertion();
    error AwaitingDecider();
    error AlreadyClaimed();
    error AlreadySettled();
    error TransferFailed();
    error OnlyDecider();
    error OnlyOwner();

    enum State { Invalid, Asserted, Proposed, Disputed, Settled, Expired }

    struct EventAssertion {
        address asserter;
        address proposer;
        address disputer;
        bool proposedOutcome;
        bool resolvedOutcome;
        uint256 reward;
        uint256 bond;
        uint256 startTime;
        uint256 endTime;
        bool claimed;
        address winner;
        string description;
    }

    mapping(uint256 => EventAssertion) public assertions;
    uint256 public nextAssertionId = 1;
    address public decider;
    address public owner;

    uint256 public constant MINIMUM_ASSERTION_WINDOW = 3 minutes;
    uint256 public constant DISPUTE_WINDOW = 3 minutes;

    event EventAsserted(uint256 indexed assertionId, address indexed asserter, string description, uint256 reward);
    event OutcomeProposed(uint256 indexed assertionId, address indexed proposer, bool outcome);
    event OutcomeDisputed(uint256 indexed assertionId, address indexed disputer);
    event AssertionSettled(uint256 indexed assertionId, bool outcome, address indexed winner);
    event RewardClaimed(uint256 indexed assertionId, address indexed winner, uint256 amount);
    event RefundClaimed(uint256 indexed assertionId, address indexed asserter, uint256 amount);
    event DeciderUpdated(address indexed oldDecider, address indexed newDecider);

    modifier onlyDecider() {
        if (msg.sender != decider) revert OnlyDecider();
        _;
    }

    constructor(address _decider) {
        owner = msg.sender;
        decider = _decider;
    }

    function setDecider(address _decider) external onlyDecider {
        address oldDecider = decider;
        decider = _decider;
        emit DeciderUpdated(oldDecider, _decider);
    }

    function getAssertion(uint256 assertionId) external view returns (EventAssertion memory) {
        return assertions[assertionId];
    }

    function assertEvent(string memory description, uint256 startTime, uint256 endTime) external payable returns (uint256) {
        if (msg.value == 0) revert InvalidValue();
        if (startTime == 0) { startTime = block.timestamp; }
        if (endTime == 0) { endTime = startTime + MINIMUM_ASSERTION_WINDOW; }
        if (startTime < block.timestamp) revert InvalidTime();
        if (endTime < startTime + MINIMUM_ASSERTION_WINDOW) revert InvalidTime();

        uint256 assertionId = nextAssertionId++;
        assertions[assertionId] = EventAssertion({
            asserter: msg.sender,
            proposer: address(0),
            disputer: address(0),
            proposedOutcome: false,
            resolvedOutcome: false,
            reward: msg.value,
            bond: msg.value * 2,
            startTime: startTime,
            endTime: endTime,
            claimed: false,
            winner: address(0),
            description: description
        });

        emit EventAsserted(assertionId, msg.sender, description, msg.value);
        return assertionId;
    }

    function proposeOutcome(uint256 assertionId, bool outcome) external payable {
        EventAssertion storage assertion = assertions[assertionId];
        if (assertion.asserter == address(0)) revert AssertionNotFound();
        if (assertion.proposer != address(0)) revert AssertionProposed();
        if (block.timestamp < assertion.startTime || block.timestamp > assertion.endTime) revert InvalidTime();
        if (msg.value != assertion.bond) revert InvalidValue();

        assertion.proposer = msg.sender;
        assertion.proposedOutcome = outcome;
        assertion.endTime = block.timestamp + DISPUTE_WINDOW;

        emit OutcomeProposed(assertionId, msg.sender, outcome);
    }

    function disputeOutcome(uint256 assertionId) external payable {
        EventAssertion storage assertion = assertions[assertionId];
        if (assertion.asserter == address(0)) revert AssertionNotFound();
        if (assertion.proposer == address(0)) revert NotProposedAssertion();
        if (assertion.disputer != address(0)) revert ProposalDisputed();
        if (block.timestamp > assertion.endTime) revert InvalidTime();
        if (msg.value != assertion.bond) revert InvalidValue();

        assertion.disputer = msg.sender;
        emit OutcomeDisputed(assertionId, msg.sender);
    }

    function claimUndisputedReward(uint256 assertionId) external {
        EventAssertion storage assertion = assertions[assertionId];
        if (assertion.asserter == address(0)) revert AssertionNotFound();
        if (assertion.proposer == address(0)) revert NotProposedAssertion();
        if (assertion.disputer != address(0)) revert ProposalDisputed();
        if (block.timestamp <= assertion.endTime) revert InvalidTime();
        if (assertion.claimed) revert AlreadyClaimed();

        assertion.claimed = true;
        assertion.resolvedOutcome = assertion.proposedOutcome;
        assertion.winner = assertion.proposer;

        uint256 totalReward = assertion.reward + assertion.bond;
        (bool sent, ) = payable(assertion.proposer).call{value: totalReward}("");
        if (!sent) revert TransferFailed();

        emit RewardClaimed(assertionId, assertion.proposer, totalReward);
    }

    function claimDisputedReward(uint256 assertionId) external {
        EventAssertion storage assertion = assertions[assertionId];
        if (assertion.asserter == address(0)) revert AssertionNotFound();
        if (assertion.proposer == address(0)) revert NotProposedAssertion();
        if (assertion.disputer == address(0)) revert NotDisputedAssertion();
        if (assertion.winner == address(0)) revert AwaitingDecider();
        if (assertion.claimed) revert AlreadyClaimed();

        assertion.claimed = true;
        uint256 totalReward = assertion.reward + assertion.bond;

        (bool sentDecider, ) = payable(decider).call{value: assertion.bond}("");
        if (!sentDecider) revert TransferFailed();

        (bool sentWinner, ) = payable(assertion.winner).call{value: totalReward}("");
        if (!sentWinner) revert TransferFailed();

        emit RewardClaimed(assertionId, assertion.winner, totalReward);
    }

    function claimRefund(uint256 assertionId) external {
        EventAssertion storage assertion = assertions[assertionId];
        if (assertion.asserter == address(0)) revert AssertionNotFound();
        if (assertion.proposer != address(0)) revert AssertionProposed();
        if (block.timestamp <= assertion.endTime) revert InvalidTime();
        if (assertion.claimed) revert AlreadyClaimed();

        assertion.claimed = true;
        (bool sent, ) = payable(assertion.asserter).call{value: assertion.reward}("");
        if (!sent) revert TransferFailed();

        emit RefundClaimed(assertionId, assertion.asserter, assertion.reward);
    }

    function settleAssertion(uint256 assertionId, bool resolvedOutcome) external onlyDecider {
        EventAssertion storage assertion = assertions[assertionId];
        if (assertion.asserter == address(0)) revert AssertionNotFound();
        if (assertion.proposer == address(0)) revert NotProposedAssertion();
        if (assertion.disputer == address(0)) revert NotDisputedAssertion();
        if (assertion.winner != address(0)) revert AlreadySettled();

        assertion.resolvedOutcome = resolvedOutcome;
        assertion.winner = (assertion.proposedOutcome == resolvedOutcome) ? assertion.proposer : assertion.disputer;

        emit AssertionSettled(assertionId, resolvedOutcome, assertion.winner);
    }

    function getState(uint256 assertionId) external view returns (State) {
        EventAssertion storage assertion = assertions[assertionId];
        if (assertion.asserter == address(0)) return State.Invalid;
        if (assertion.winner != address(0)) return State.Settled;
        if (assertion.disputer != address(0)) return State.Disputed;
        if (assertion.proposer == address(0)) {
            return block.timestamp > assertion.endTime ? State.Expired : State.Asserted;
        }
        return block.timestamp > assertion.endTime ? State.Settled : State.Proposed;
    }

    function getResolution(uint256 assertionId) external view returns (bool) {
        EventAssertion storage assertion = assertions[assertionId];
        if (assertion.asserter == address(0)) revert AssertionNotFound();
        if (assertion.proposer == address(0)) revert NotProposedAssertion();

        if (assertion.disputer == address(0)) {
            if (block.timestamp <= assertion.endTime) revert InvalidTime();
            return assertion.proposedOutcome;
        } else {
            if (assertion.winner == address(0)) revert AwaitingDecider();
            return assertion.resolvedOutcome;
        }
    }
}
