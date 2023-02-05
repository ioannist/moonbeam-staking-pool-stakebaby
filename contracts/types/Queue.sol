// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/**
 * @title Queue
 * @author Erick Dagenais (https://github.com/edag94)
 * @dev Implementation of the queue data structure, providing a library with struct definition for queue storage in consuming contracts.
 */
library Queue {

    struct WhoAmount {
        address who;
        uint256 amount;
        uint256 round;
    }

    struct QueueStorage {
        mapping(int256 => WhoAmount) _data;
        int256 _first;
        int256 _last;
    }

    modifier isNotEmpty(QueueStorage storage queue) {
        require(!isEmpty(queue), "Queue is empty.");
        _;
    }

    /**
     * @dev Sets the queue's initial state, with a queue size of 0.
     * @param queue QueueStorage struct from contract.
     */
    function initialize(QueueStorage storage queue) external {
        queue._first = 1;
        queue._last = 0;
    }

    function reset(QueueStorage storage queue) public {
        for (int256 i = queue._first; i <= queue._last; i++) {
            delete queue._data[i];
        }
        queue._first = 1;
        queue._last = 0;
    }

    /**
     * @dev Gets the number of elements in the queue. O(1)
     * @param queue QueueStorage struct from contract.
     */
    function length(QueueStorage storage queue) public view returns (uint256) {
        if (queue._last < queue._first) {
            return 0;
        }
        return uint256(queue._last - queue._first + 1); // always positive
    }

    /**
     * @dev Returns if queue is empty. O(1)
     * @param queue QueueStorage struct from contract.
     */
    function isEmpty(QueueStorage storage queue) public view returns (bool) {
        return length(queue) == 0;
    }

    /**
     * @dev Adds an element to the back of the queue. O(1)
     * @param queue QueueStorage struct from contract.
     * @param data The added element's data.
     */
    function pushBack(QueueStorage storage queue, WhoAmount calldata data)
        public
    {
        queue._data[++queue._last] = data;
    }

    function pushFront(QueueStorage storage queue, WhoAmount calldata data)
        public
    {
        queue._data[--queue._first] = data;
    }

    /**
     * @dev Removes an element from the front of the queue and returns it. O(1)
     * @param queue QueueStorage struct from contract.
     */
    function popFront(QueueStorage storage queue)
        public
        isNotEmpty(queue)
        returns (WhoAmount memory data)
    {
        data = queue._data[queue._first];
        delete queue._data[queue._first++];
    }

    function popBack(QueueStorage storage queue)
        public
        isNotEmpty(queue)
        returns (WhoAmount memory data)
    {
        data = queue._data[queue._last];
        delete queue._data[queue._last--];
    }

    /**
     * @dev Returns the data from the front of the queue, without removing it. O(1)
     * @param queue QueueStorage struct from contract.
     */
    function peekFront(QueueStorage storage queue)
        public
        view
        isNotEmpty(queue)
        returns (WhoAmount memory data)
    {
        return queue._data[queue._first];
    }

    /**
     * @dev Returns the data from the back of the queue. O(1)
     * @param queue QueueStorage struct from contract.
     */
    function peekBack(QueueStorage storage queue)
        public
        view
        isNotEmpty(queue)
        returns (WhoAmount memory data)
    {
        return queue._data[queue._last];
    }
}
