// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.7.0;

/// @title Typedef
/// @dev 각 Chain 라이브러리에서 다룰 data type 정의
/// @author jhhong
library Typedef {

    // 구조체 : Address Type 노드 정보
    struct AddressElmt {
        address prev; // 이전 노드
        address next; // 다음 노드
    }
    // 구조체 : Address Type 노드 체인
    struct AddressList {
        uint256 count; // 노드의 총 개수
        address head; // 체인의 머리
        address tail; // 체인의 꼬리
        mapping(address => AddressElmt) map; // 계정에 대한 노드 정보 매핑
    }

    // 구조체 : Bytes32 Type 노드 정보
    struct Bytes32Elmt {
        bytes32 prev; // 이전 노드
        bytes32 next; // 다음 노드
    }
    // 구조체 : Bytes32 Type 노드 체인
    struct Bytes32List {
        uint256 count; // 노드의 총 개수
        bytes32 head; // 체인의 머리
        bytes32 tail; // 체인의 꼬리
        mapping(bytes32 => Bytes32Elmt) map; // 계정에 대한 노드 정보 매핑
    }

    // 구조체 : Uint64 Type 노드 정보
    struct Uint64Elmt {
        uint64 prev; // 이전 노드
        uint64 next; // 다음 노드
    }
    // 구조체 : Uint64 Type 노드 체인
    struct Uint64List {
        uint256 count; // 노드의 총 개수
        uint64 head; // 체인의 머리
        uint64 tail; // 체인의 꼬리
        mapping(uint64 => Uint64Elmt) map; // 계정에 대한 노드 정보 매핑
    }
}