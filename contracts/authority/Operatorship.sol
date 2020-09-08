// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "./Ownership.sol";
import "../libs/Roles.sol";

/// @title Operatorship
/// @dev 운영자 (Operator) 리스트 관리 및 운영자 여부 확인
/// @author jhhong
contract Operatorship is Ownership {
    using Roles for Roles.Role;

    Roles.Role private _operators; // operator 정보 저장을 위한 변수 (Roles.Role)

    /// @notice 운영자 추가 이벤트
    /// @param account 추가될 운영자 주소
    event OperatorAdded(address indexed account);

    /// @notice 운영자 제거 이벤트
    /// @param account 제거될 운영자 주소
    event OperatorRemoved(address indexed account);

    /// @notice 운영자만 접근할 수 있음을 명시한다.
    modifier onlyOperator() {
        require(isOperator(msg.sender), "Operatorship: only the operator can call");
        _;
    }

    /// @notice 컨트랙트 생성자이다.
    constructor() {
        _operators.add(msg.sender);
        emit OperatorAdded(msg.sender);
    }

    /// @notice 운영자를 추가한다.
    /// @dev 오너에 의해서만 호출 가능
    /// @param account 추가할 운영자 계정
    function addOperator(address account) public onlyOwner {
        require(account != address(0), "Operatorship: the address cannot be zero");
        _operators.add(account);
        emit OperatorAdded(account);
    }

    /// @notice 운영자를 삭제한다.
    /// @dev 소유자에 의해서만 호출 가능
    /// @param account 삭제할 운영자 계정
    function removeOperator(address account) public onlyOwner {
        require(account != address(0), "Operatorship: the address cannot be zero");
        require(msg.sender != account, "Operatorship: the owner cannot be removed from operator group");
        _operators.remove(account);
        emit OperatorRemoved(account);
    }

    /// @notice 소유권을 넘겨준다.
    /// @dev 새 오너에게 관리자 권한 부여하고, 기존 오너에게서 관리자 권한 해제해야 한다.
    /// @param expected 새로운 오너 계정
    function transferOwnership(address expected) public override {
        super.transferOwnership(expected);
        if(isOperator(expected) == false) {
            _operators.add(expected);
            emit OperatorAdded(expected);
        }
        _operators.remove(msg.sender);
        emit OperatorRemoved(msg.sender);
    }

    /// @notice 운영자인지 확인한다.
    /// @param account 확인할 계정
    /// @return 확인 결과 (boolean)
    function isOperator(address account) public view returns (bool) {
        return _operators.has(account);
    }
}