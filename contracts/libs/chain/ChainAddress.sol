// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.7.0;

import "./Typedef.sol";
import "../math/SafeMath256.sol";

/// @title ChainAddress
/// @notice Address Chain 라이브러리 정의
/// @author jhhong
library ChainAddress {
    using SafeMath256 for uint256;

    /// @notice 체인의 첫번째 노드 인덱스를 반환한다.
    /// @param list Address Chain List
    /// @return 체인의 첫번째 노드 인덱스 (address)
    function first(Typedef.AddressList storage list) internal view returns(address) {
        return list.head;
    }

    /// @notice 체인의 마지막 노드 인덱스를 반환한다.
    /// @param list Address Chain List
    /// @return 체인의 마지막 노드 인덱스 (address)
    function last(Typedef.AddressList storage list) internal view returns(address) {
        return list.tail;
    }

    /// @notice 체인에 등록된 엘리먼트 총 개수를 반환한다.
    /// @param list Address Chain List
    /// @return 체인에 등록된 엘리먼트 총 개수 (uint256)
    function size(Typedef.AddressList storage list) internal view returns(uint256) {
        return list.count;
    }

    /// @notice node의 다음 노드 인덱스를 반환한다.
    /// @param list Address Chain List
    /// @param node 노드 인덱스
    /// @return node의 다음 노드 인덱스
    function nextOf(Typedef.AddressList storage list, address node) internal view returns(address) {
        return list.map[node].next;
    }

    /// @notice node의 이전 노드 인덱스를 반환한다.
    /// @param list Address Chain List
    /// @param node 노드 인덱스
    /// @return node의 이전 노드 인덱스
    function prevOf(Typedef.AddressList storage list, address node) internal view returns(address) {
        return list.map[node].prev;
    }

    /// @notice node가 체인에 연결된 상태인지를 확인한다.
    /// @param list Address Chain List
    /// @param node 체인 연결 여부를 확인할 노드 인덱스
    /// @return 연결 여부 (boolean), true: 연결됨(linked), false: 연결되지 않음(unlinked)
    function isLinked(Typedef.AddressList storage list, address node) internal view returns (bool) {
        if(list.count == 1 && list.head == node && list.tail == node) {
            return true;
        } else {
            return (list.map[node].prev == address(0) && list.map[node].next == address(0))? (false) :(true);
        }
    }

    /// @notice 새로운 노드 정보를 노드 체인에 연결한다.
    /// @param list Address Chain List
    /// @param node 노드 체인에 연결할 노드 인덱스
    function linkChain(Typedef.AddressList storage list, address node) internal {
        require(node != address(0), "ChainAddress: the node cannot be the zero");
        require(!isLinked(list, node), "ChainAddress: the node is aleady linked");
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
    /// @param list Address Chain List
    /// @param node 노드 체인에서 연결 해제할 노드 인덱스
    function unlinkChain(Typedef.AddressList storage list, address node) internal {
        require(node != address(0), "ChainAddress: the node cannot be the zero");
        require(isLinked(list, node), "ChainAddress: the node is aleady unlinked");
        address tempPrev = list.map[node].prev;
        address tempNext = list.map[node].next;
        if (list.head == node) {
            list.head = tempNext;
        }
        if (list.tail == node) {
            list.tail = tempPrev;
        }
        if (tempPrev != address(0)) {
            list.map[tempPrev].next = tempNext;
            list.map[node].prev = address(0);
        }
        if (tempNext != address(0)) {
            list.map[tempNext].prev = tempPrev;
            list.map[node].next = address(0);
        }
        list.count = list.count.sub(1);
    }
}
