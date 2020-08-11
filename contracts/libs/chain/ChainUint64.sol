// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "./Typedef.sol";
import "../math/SafeMath256.sol";

/// @title ChainUint64
/// @notice 주소체인 라이브러리 정의
/// @author jhhong
library ChainUint64 {
    using SafeMath256 for uint256;

    /// @notice 체인의 첫번째 노드 인덱스를 반환한다.
    /// @param list Uint64 Chain List
    /// @return 체인의 첫번째 노드 인덱스 (uint64)
    function first(Typedef.Uint64List storage list) internal view returns(uint64) {
        return list.head;
    }

    /// @notice 체인의 마지막 노드 인덱스를 반환한다.
    /// @param list Uint64 Chain List
    /// @return 체인의 마지막 노드 인덱스 (uint64)
    function last(Typedef.Uint64List storage list) internal view returns(uint64) {
        return list.tail;
    }

    /// @notice 체인에 등록된 엘리먼트 총 개수를 반환한다.
    /// @param list Uint64 Chain List
    /// @return 체인에 등록된 엘리먼트 총 개수 (uint256)
    function size(Typedef.Uint64List storage list) internal view returns(uint256) {
        return list.count;
    }

    /// @notice node의 다음 노드 인덱스를 반환한다.
    /// @param list Uint64 Chain List
    /// @param node 노드 인덱스
    /// @return node의 다음 노드 인덱스
    function nextOf(Typedef.Uint64List storage list, uint64 node) internal view returns(uint64) {
        return list.map[node].next;
    }

    /// @notice node의 이전 노드 인덱스를 반환한다.
    /// @param list Uint64 Chain List
    /// @param node 노드 인덱스
    /// @return node의 이전 노드 인덱스
    function prevOf(Typedef.Uint64List storage list, uint64 node) internal view returns(uint64) {
        return list.map[node].prev;
    }

    /// @notice node가 체인에 연결된 상태인지를 확인한다.
    /// @param list Uint64 Chain List
    /// @param node 체인 연결 여부를 확인할 노드 인덱스
    /// @return 연결 여부 (boolean), true: 연결됨(linked), false: 연결되지 않음(unlinked)
    function isLinked(Typedef.Uint64List storage list, uint64 node) internal view returns (bool) {
        if(list.count == 1 && list.head == node && list.tail == node) {
            return true;
        } else {
            return (list.map[node].prev == uint64(0) && list.map[node].next == uint64(0))? (false) :(true);
        }
    }

    /// @notice 새로운 노드 정보를 노드 체인에 연결한다.
    /// @param list Uint64 Chain List
    /// @param node 노드 체인에 연결할 노드 인덱스
    function linkChain(Typedef.Uint64List storage list, uint64 node) internal {
        require(!isLinked(list, node), "ChainUint64: the node is aleady linked");
        if(list.count == 0) {
            list.head = list.tail = node;
        } else {
            list.map[node].prev = list.tail;
            list.map[list.tail].next = node;
            list.tail = node;
        }
        list.count = list.count.add(1);
    }

    /// @notice node 노드를 체인에서 연결 해제한다.
    /// @param list Uint64 Chain List
    /// @param node 노드 체인에서 연결 해제할 노드 인덱스
    function unlinkChain(Typedef.Uint64List storage list, uint64 node) internal {
        require(isLinked(list, node), "ChainUint64: the node is aleady unlinked");
        uint64 tempPrev = list.map[node].prev;
        uint64 tempNext = list.map[node].next;
        if (list.head == node) {
            list.head = tempNext;
        }
        if (list.tail == node) {
            list.tail = tempPrev;
        }
        if (tempPrev != uint64(0)) {
            list.map[tempPrev].next = tempNext;
            list.map[node].prev = uint64(0);
        }
        if (tempNext != uint64(0)) {
            list.map[tempNext].prev = tempPrev;
            list.map[node].next = uint64(0);
        }
        list.count = list.count.sub(1);
    }
}
