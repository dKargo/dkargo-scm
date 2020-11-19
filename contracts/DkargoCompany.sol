// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "./DkargoPrefix.sol";
import "./authority/Operatorship.sol";
import "./introspection/ERC165/ERC165.sol";
import "./libs/Address.sol";
import "./libs/math/SafeMath256.sol";

/// @title DkargoCompany
/// @notice 물류사 컨트랙트 정의
/// @author jhhong
contract DkargoCompany is Operatorship, ERC165, DkargoPrefix {
    using Address for address;
    using SafeMath256 for uint256;

    /// @dev 변수 선언
    string private _name; // 물류사 이름
    string private _url; // 물류사 상세정보 URL
    address private _recipient; // 인센티브 수취인 주소
    address private _service; // 서비스 컨트랙트 주소
    mapping(address => mapping(uint256 => bool)) private _todolist; // 접수되어 처리해야 할 주문정보

    /// @notice 물류사 이름변경 이벤트
    /// @param oldName 물류사 이전 이름
    /// @param newName 물류사 변경된 이름
    event CompanyNameSet(string oldName, string newName);

    /// @notice 물류사 URL변경 이벤트
    /// @param oldUrl 물류사 이전 URL
    /// @param newUrl 물류사 변경된 URL
    event CompanyUrlSet(string oldUrl, string newUrl);

    /// @notice 물류사 수취인주소 변경 이벤트
    /// @param oldRecipient 물류사 이전 수취인주소
    /// @param newRecipient 물류사 변경된 수취인주소
    event CompanyRecipientSet(address oldRecipient, address newRecipient);

    /// @notice 컨트랙트 생성자이다.
    /// @param name 물류사 이름
    /// @param url 물류사 상세정보가 저장된 URL (string)
    /// @param recipient 인센티브 수취인 주소
    /// @param service 서비스 컨트랙트 주소
    constructor(string memory name, string memory url, address recipient, address service) {
        _setDkargoPrefix("company"); // 프리픽스 설정
        _registerInterface(0x946edbed); // INTERFACE ID 등록 (getDkargoPrefix)
        _name = name;
        _url = url;
        _recipient = recipient;
        _service = service;
    }

    /// @notice 주문을 접수한다.
    /// @dev 주문접수(todolist 갱신), 주문이 물류사 체인에 없으면 등록
    /// @param order 주문 컨트랙트 주소
    /// @param transportid 운송번호 (구간배송번호)
    function launch(address order, uint256 transportid) onlyOperator public {
        _todolist[order][transportid] = true; // 주문접수(todolist 갱신)
    }

    /// @notice 주문 상태코드를 갱신한다.
    /// @dev 담당 구간 배송 종료(완료/실패) -> 다음 담당 물류사에게 알람
    /// @param order 주문 컨트랙트 주소
    /// @param transportid 운송번호 (구간배송번호)
    /// @param code 배송상태 코드 번호
    function updateOrderCode(address order, uint256 transportid, uint256 code) onlyOperator public {
        //// 물류사 관할 주문인지 아닌지 체크 (실수로 launch과정을 생략하였다면 여기서 revert될 것임)
        require(_todolist[order][transportid] == true, "DkargoCompany: unlaunched order");
        _submitUpdate(order, code);
        if(_isOrderLastMile(order) == true) { // "LastMile 배송 -> 배송완료" 구간은 동일 물류사 이므로 Launch 수행을 생략한다.
            uint256 tidLastmile = _getOrderCurTransportId(order);
            _todolist[order][tidLastmile] = true;
        }
    }

    /// @notice 물류사 이름을 설정한다.
    /// @dev onlyOwner
    /// @param name 물류사 이름
    function setName(string memory name) onlyOwner public {
        emit CompanyNameSet(_name, name);
        _name = name;
    }

    /// @notice 물류사 URL을 설정한다.
    /// @dev onlyOwner
    /// @param url 물류사 URL
    function setUrl(string memory url) onlyOwner public {
        emit CompanyUrlSet(_url, url);
        _url = url;
    }

    /// @notice 물류사의 수취인 주소를 설정한다.
    /// @dev onlyOwner
    /// @param recipient 물류사 수취인 주소
    function setRecipient(address recipient) onlyOwner public {
        emit CompanyRecipientSet(_recipient, recipient);
        _recipient = recipient;
    }

    /// @notice 주문 구간배송이 물류사에 접수되었는지 확인한다.
    /// @param order 주문 컨트랙트 주소
    /// @param transportid 운송번호 (구간배송번호)
    /// @return 주문 접수여부 (bool)
    function isLaunched(address order, uint256 transportid) public view returns(bool) {
        return _todolist[order][transportid];
    }

    /// @notice 물류사 이름을 반환한다.
    /// @return 물류사 이름 (string)
    function name() public view returns(string memory) {
        return _name;
    }

    /// @notice 물류사의 수취인 주소를 반환한다.
    /// @return 물류사의 수취인 주소 (address)
    function recipient() public view returns(address) {
        return _recipient;
    }

    /// @notice 서비스 컨트랙트 주소를 반환한다.
    /// @return 서비스 컨트랙트 주소 (address)
    function service() public view returns(address) {
        return _service;
    }

    /// @notice 물류사 URL을 반환한다.
    /// @return 물류사 URL (string)
    function url() public view returns(string memory) {
        return _url;
    }

    /// @notice 주문 컨트랙트가 현재 LastMile 상태인지 여부를 얻어온다.
    /// @param order 주문 컨트랙트 주소
    /// @return LastMile 상태 여부 (Boolean)
    function _isOrderLastMile(address order) private view returns(bool) {
        bytes memory data = address(order)._vcall(abi.encodeWithSignature("isLastMile()"));
        return abi.decode(data, (bool));
    }

    /// @notice 주문 컨트랙트의 현재 운송번호를 얻어온다.
    /// @dev 주문 컨트랙트의 현재 운송번호 == 주문 컨트랙트의 현재 상태 인덱스
    /// @param order 주문 컨트랙트 주소
    /// @return 주문 컨트랙트의 현재 운송번호 (uint256)
    function _getOrderCurTransportId(address order) private view returns(uint256) {
        bytes memory data = address(order)._vcall(abi.encodeWithSignature("currentStep()"));
        return abi.decode(data, (uint256));
    }

    /// @notice 주문 상태갱신 알림을 위해 주문 컨트랙트의 submitUpdate를 호출한다.
    /// @param order 주문 컨트랙트 주소
    /// @param code 배송상태 코드 번호
    function _submitUpdate(address order, uint256 code) private {
        bytes memory cmd = abi.encodeWithSignature("submitOrderUpdate(uint64,uint256)", block.timestamp, code);
        address(order)._call(cmd); // 주문 컨트랙트에 트래킹 정보 기록
    }
}