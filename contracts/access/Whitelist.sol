// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.7.0;

import "../authority/Ownership.sol";
import "../libs/Roles.sol";

/// @title Whitelist
/// @dev 화이트리스트 컨트랙트 정의
/// @author jhhong
contract Whitelist is Ownership {
    using Roles for Roles.Role;

    Roles.Role private _whitelist; // whitelist 정보 저장을 위한 변수 (Roles.Role)

    // 이벤트 선언
    event WhitelistAdded(address indexed account);
    event WhitelistRemoved(address indexed account);

    /// @notice 화이트리스트 맴버들만 접근할 수 있음을 명시한다.
    modifier onlyWhitelist() {
        require(isWhitelist(msg.sender) == true, "Whitelist: caller is not the Whitelist");
        _;
    }

    /// @notice 화이트리스트 맴버를 추가한다.
    /// @param account 추가할 운영자 계정
    function addWhitelist(address account) external onlyOwner {
        _whitelist.add(account);
        emit WhitelistAdded(account);
    }

    /// @notice 화이트리스트 맴버를 삭제한다.
    /// @param account 삭제할 운영자 계정
    function removeWhitelist(address account) external onlyOwner {
        _whitelist.remove(account);
        emit WhitelistRemoved(account);
    }

    /// @notice 화이트리스트 맴버인지 확인한다.
    /// @param account 확인할 계정
    /// @return 확인 결과 (boolean)
    function isWhitelist(address account) public view returns (bool) {
        return _whitelist.has(account);
    }
}