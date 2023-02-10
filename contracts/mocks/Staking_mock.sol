// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.3;
import "../interfaces/StakingInterface.sol";

/// @author The Moonbeam Team
/// @title Pallet Parachain Staking Interface
/// @dev The interface through which solidity contracts will interact with Parachain Staking
/// We follow this same interface including four-byte function selectors, in the precompile that
/// wraps the pallet
/// @custom:address 0x0000000000000000000000000000000000000800
contract Staking_mock is ParachainStaking {
    uint256 MINIMUM_DELEGATION = 50;

    mapping(address => bool) candidates;
    mapping(address => bool) selected;
    address[] selectedArray;
    mapping(address => address) requests;
    mapping(address => mapping(address => uint256)) delegations;
    mapping(address => uint256) totalDelegaitons;
    mapping(address => mapping(address => uint256)) scheduledBondLess;
    mapping(address => mapping(address => bool)) scheduledRevoke;

    /// @dev Check whether the specified address is currently a staking delegator
    /// @custom:selector fd8ab482
    /// @param delegator the address that we want to confirm is a delegator
    /// @return A boolean confirming whether the address is a delegator
    function isDelegator(address delegator) external view returns (bool) {
        // NOT USED
        return false;
    }

    /// @dev Check whether the specified address is currently a collator candidate
    /// @custom:selector d51b9e93
    /// @param candidate the address that we want to confirm is a collator andidate
    /// @return A boolean confirming whether the address is a collator candidate
    function isCandidate(address candidate) external view returns (bool) {
        return candidates[candidate];
    }

    /// @dev Check whether the specifies address is currently a part of the active set
    /// @custom:selector 740d7d2a
    /// @param candidate the address that we want to confirm is a part of the active set
    /// @return A boolean confirming whether the address is a part of the active set
    function isSelectedCandidate(address candidate)
        external
        view
        returns (bool)
    {
        return selected[candidate];
    }

    /// @dev Total points awarded to all collators in a particular round
    /// @custom:selector 9799b4e7
    /// @param round the round for which we are querying the points total
    /// @return The total points awarded to all collators in the round
    function points(uint256 round) external view returns (uint256) {
        return 0;
    }

    /// @dev The amount delegated in support of the candidate by the delegator
    /// @custom:selector a73e51bc
    /// @param delegator Who made this delegation
    /// @param candidate The candidate for which the delegation is in support of
    /// @return The amount of the delegation in support of the candidate by the delegator
    function delegationAmount(address delegator, address candidate)
        external
        view
        returns (uint256)
    {
        return delegations[delegator][candidate];
    }

    /// @dev Whether the delegation is in the top delegations
    /// @custom:selector 91cc8657
    /// @param delegator Who made this delegation
    /// @param candidate The candidate for which the delegation is in support of
    /// @return If delegation is in top delegations (is counted)
    function isInTopDelegations(address delegator, address candidate)
        external
        view
        returns (bool)
    {
        return true;
    }

    /// @dev Get the minimum delegation amount
    /// @custom:selector 02985992
    /// @return The minimum delegation amount
    function minDelegation() external view returns (uint256) {
        return 5 ether;
    }

    /// @dev Get the CandidateCount weight hint
    /// @custom:selector a9a981a3
    /// @return The CandidateCount weight hint
    function candidateCount() external view returns (uint256) {
        return 1;
    }

    /// @dev Get the current round number
    /// @custom:selector 146ca531
    /// @return The current round number
    function round() external view returns (uint256) {
        return (block.number + 10) / 10;
    }

    /// @dev Get the CandidateDelegationCount weight hint
    /// @custom:selector 2ec087eb
    /// @param candidate The address for which we are querying the nomination count
    /// @return The number of nominations backing the collator
    function candidateDelegationCount(address candidate)
        external
        view
        returns (uint32)
    {
        return 1;
    }

    /// @dev Get the CandidateAutoCompoundingDelegationCount weight hint
    /// @custom:selector 905f0806
    /// @param candidate The address for which we are querying the auto compounding
    ///     delegation count
    /// @return The number of auto compounding delegations
    function candidateAutoCompoundingDelegationCount(address candidate)
        external
        view
        returns (uint32)
    {
        return 1;
    }

    /// @dev Get the DelegatorDelegationCount weight hint
    /// @custom:selector 067ec822
    /// @param delegator The address for which we are querying the delegation count
    /// @return The number of delegations made by the delegator
    function delegatorDelegationCount(address delegator)
        external
        view
        returns (uint256)
    {
        return 1;
    }

    /// @dev Get the selected candidates for the current round
    /// @custom:selector bcf868a6
    /// @return The selected candidate accounts
    function selectedCandidates() external view returns (address[] memory) {
        return selectedArray;
    }

    /// @dev Whether there exists a pending request for a delegation made by a delegator
    /// @custom:selector 3b16def8
    /// @param delegator the delegator that made the delegation
    /// @param candidate the candidate for which the delegation was made
    /// @return Whether a pending request exists for such delegation
    function delegationRequestIsPending(address delegator, address candidate)
        external
        view
        returns (bool)
    {
        return requests[delegator] == candidate;
    }

    /// @dev Whether there exists a pending exit for candidate
    /// @custom:selector 43443682
    /// @param candidate the candidate for which the exit request was made
    /// @return Whether a pending request exists for such delegation
    function candidateExitIsPending(address candidate)
        external
        view
        returns (bool)
    {
        return false;
    }

    /// @dev Whether there exists a pending bond less request made by a candidate
    /// @custom:selector d0deec11
    /// @param candidate the candidate which made the request
    /// @return Whether a pending bond less request was made by the candidate
    function candidateRequestIsPending(address candidate)
        external
        view
        returns (bool)
    {
        return false;
    }

    /// @dev Returns the percent value of auto-compound set for a delegation
    /// @custom:selector b4d4c7fd
    /// @param delegator the delegator that made the delegation
    /// @param candidate the candidate for which the delegation was made
    /// @return Percent of rewarded amount that is auto-compounded on each payout
    function delegationAutoCompound(address delegator, address candidate)
        external
        view
        returns (uint8)
    {
        return 0;
    }

    /// @dev Join the set of collator candidates
    /// @custom:selector 1f2f83ad
    /// @param amount The amount self-bonded by the caller to become a collator candidate
    /// @param candidateCount The number of candidates in the CandidatePool
    function joinCandidates(uint256 amount, uint256 candidateCount) external {
        candidates[msg.sender] = true;
        selected[msg.sender] = true;
        selectedArray.push(msg.sender);
    }

    /// @dev Request to leave the set of collator candidates
    /// @custom:selector b1a3c1b7
    /// @param candidateCount The number of candidates in the CandidatePool
    function scheduleLeaveCandidates(uint256 candidateCount) external {}

    /// @dev Execute due request to leave the set of collator candidates
    /// @custom:selector 3867f308
    /// @param candidate The candidate address for which the pending exit request will be executed
    /// @param candidateDelegationCount The number of delegations for the candidate to be revoked
    function executeLeaveCandidates(
        address candidate,
        uint256 candidateDelegationCount
    ) external {
        delete candidates[msg.sender];
        delete selected[msg.sender];
        uint256 length = selectedArray.length;
        uint256 index = type(uint256).max;
        for (uint256 i = 0; i < length; ++i) {
            if (selectedArray[i] == candidate) {
                index = i;
                break;
            }
        }
        if (index == type(uint256).max) {
            return;
        }
        uint256 last = selectedArray.length - 1;
        if (index != last) selectedArray[index] = selectedArray[last];
        selectedArray.pop();
    }

    /// @dev Cancel request to leave the set of collator candidates
    /// @custom:selector 9c76ebb4
    /// @param candidateCount The number of candidates in the CandidatePool
    function cancelLeaveCandidates(uint256 candidateCount) external {}

    /// @dev Temporarily leave the set of collator candidates without unbonding
    /// @custom:selector a6485ccd
    function goOffline() external {}

    /// @dev Rejoin the set of collator candidates if previously had called `goOffline`
    /// @custom:selector 6e5b676b
    function goOnline() external {}

    /// @dev Request to bond more for collator candidates
    /// @custom:selector a52c8643
    /// @param more The additional amount self-bonded
    function candidateBondMore(uint256 more) external {}

    /// @dev Request to bond less for collator candidates
    /// @custom:selector 60744ae0
    /// @param less The amount to be subtracted from self-bond and unreserved
    function scheduleCandidateBondLess(uint256 less) external {}

    /// @dev Execute pending candidate bond request
    /// @custom:selector 2e290290
    /// @param candidate The address for the candidate for which the request will be executed
    function executeCandidateBondLess(address candidate) external {}

    /// @dev Cancel pending candidate bond request
    /// @custom:selector b5ad5f07
    function cancelCandidateBondLess() external {}

    /// @dev Make a delegation in support of a collator candidate
    /// @custom:selector 829f5ee3
    /// @param candidate The address of the supported collator candidate
    /// @param amount The amount bonded in support of the collator candidate
    /// @param candidateDelegationCount The number of delegations in support of the candidate
    /// @param delegatorDelegationCount The number of existing delegations by the caller
    function delegate(
        address candidate,
        uint256 amount,
        uint256 candidateDelegationCount,
        uint256 delegatorDelegationCount
    ) external {
        if (delegations[msg.sender][candidate] == 0) {
            require(amount >= MINIMUM_DELEGATION, "DELEGATION_BELOW_MIN");
        }
        delegations[msg.sender][candidate] += amount;
        totalDelegaitons[msg.sender] += amount;
    }

    /// @dev Make a delegation in support of a collator candidate
    /// @custom:selector 4b8bc9bf
    /// @param candidate The address of the supported collator candidate
    /// @param amount The amount bonded in support of the collator candidate
    /// @param autoCompound The percent of reward that should be auto-compounded
    /// @param candidateDelegationCount The number of delegations in support of the candidate
    /// @param candidateAutoCompoundingDelegationCount The number of auto-compounding delegations
    /// in support of the candidate
    /// @param delegatorDelegationCount The number of existing delegations by the caller
    function delegateWithAutoCompound(
        address candidate,
        uint256 amount,
        uint8 autoCompound,
        uint256 candidateDelegationCount,
        uint256 candidateAutoCompoundingDelegationCount,
        uint256 delegatorDelegationCount
    ) external {}

    /// @notice DEPRECATED use batch util with scheduleRevokeDelegation for all delegations
    /// @dev Request to leave the set of delegators
    /// @custom:selector f939dadb
    function scheduleLeaveDelegators() external {}

    /// @notice DEPRECATED use batch util with executeDelegationRequest for all delegations
    /// @dev Execute request to leave the set of delegators and revoke all delegations
    /// @custom:selector fb1e2bf9
    /// @param delegator The leaving delegator
    /// @param delegatorDelegationCount The number of active delegations to be revoked by delegator
    function executeLeaveDelegators(
        address delegator,
        uint256 delegatorDelegationCount
    ) external {}

    /// @notice DEPRECATED use batch util with cancelDelegationRequest for all delegations
    /// @dev Cancel request to leave the set of delegators
    /// @custom:selector f7421284
    function cancelLeaveDelegators() external {}

    /// @dev Request to revoke an existing delegation
    /// @custom:selector 1a1c740c
    /// @param candidate The address of the collator candidate which will no longer be supported
    function scheduleRevokeDelegation(address candidate) external {
        require(!scheduledRevoke[msg.sender][candidate], "ALREADY_SCHEDULED");
        scheduledRevoke[msg.sender][candidate] = true;
    }

    /// @dev Bond more for delegators with respect to a specific collator candidate
    /// @custom:selector 0465135b
    /// @param candidate The address of the collator candidate for which delegation shall increase
    /// @param more The amount by which the delegation is increased
    function delegatorBondMore(address candidate, uint256 more) external {
        require(delegations[msg.sender][candidate] > 0, "NOT_A_DELEGATOR");
        delegations[msg.sender][candidate] += more;
        totalDelegaitons[msg.sender] += more;
    }

    /// @dev Request to bond less for delegators with respect to a specific collator candidate
    /// @custom:selector c172fd2b
    /// @param candidate The address of the collator candidate for which delegation shall decrease
    /// @param less The amount by which the delegation is decreased (upon execution)
    function scheduleDelegatorBondLess(address candidate, uint256 less)
        external
    {
        require(
            scheduledBondLess[msg.sender][candidate] == 0,
            "ALREADY_SCHEDULED"
        );
        require(
            delegations[msg.sender][candidate] - less >= MINIMUM_DELEGATION,
            "BELOW_MIN"
        );
        scheduledBondLess[msg.sender][candidate] = less;
    }

    /// @dev Execute pending delegation request (if exists && is due)
    /// @custom:selector e98c8abe
    /// @param delegator The address of the delegator
    /// @param candidate The address of the candidate
    function executeDelegationRequest(address delegator, address candidate)
        external
    {
        require(
            scheduledBondLess[delegator][candidate] > 0 ||
                scheduledRevoke[delegator][candidate],
            "NO_PENDING"
        );
        if (scheduledBondLess[delegator][candidate] > 0) {
            delegations[delegator][candidate] -= scheduledBondLess[delegator][
                candidate
            ];
            totalDelegaitons[delegator] -= scheduledBondLess[delegator][
                candidate
            ];
            delete scheduledBondLess[delegator][candidate];
        } else if (scheduledRevoke[delegator][candidate]) {
            totalDelegaitons[delegator] -= delegations[delegator][candidate];
            delegations[delegator][candidate] = 0;
            delete scheduledRevoke[delegator][candidate];
        }
    }

    /// @dev Cancel pending delegation request (already made in support of input by caller)
    /// @custom:selector c90eee83
    /// @param candidate The address of the candidate
    function cancelDelegationRequest(address candidate) external {
        require(
            scheduledBondLess[msg.sender][candidate] > 0 ||
                scheduledRevoke[msg.sender][candidate],
            "NO_PENDING"
        );
        if (scheduledBondLess[msg.sender][candidate] > 0) {
            delete scheduledBondLess[msg.sender][candidate];
        } else if (scheduledRevoke[msg.sender][candidate]) {
            delete scheduledRevoke[msg.sender][candidate];
        }
    }

    /// @dev Sets an auto-compound value for a delegation
    /// @custom:selector faa1786f
    /// @param candidate The address of the supported collator candidate
    /// @param value The percent of reward that should be auto-compounded
    /// @param candidateAutoCompoundingDelegationCount The number of auto-compounding delegations
    /// in support of the candidate
    /// @param delegatorDelegationCount The number of existing delegations by the caller
    function setAutoCompound(
        address candidate,
        uint8 value,
        uint256 candidateAutoCompoundingDelegationCount,
        uint256 delegatorDelegationCount
    ) external {}

    /// @dev Fetch the total staked amount of a delegator, regardless of the
    /// candidate.
    /// @custom:selector e6861713
    /// @param delegator Address of the delegator.
    /// @return Total amount of stake.
    function getDelegatorTotalStaked(address delegator)
        external
        view
        returns (uint256)
    {
        return totalDelegaitons[delegator];
    }

    /// @dev Fetch the total staked towards a candidate.
    /// @custom:selector bc5a1043
    /// @param candidate Address of the candidate.
    /// @return Total amount of stake.
    function getCandidateTotalCounted(address candidate)
        external
        view
        returns (uint256)
    {
        return 1;
    }
}
