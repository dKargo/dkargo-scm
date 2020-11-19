// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "./DkargoPrefix.sol";
import "./introspection/ERC165/ERC165.sol";
import "./libs/Address.sol";
import "./libs/math/SafeMath256.sol";

/// @title DkargoOrder
/// @notice 주문 컨트랙트 정의
/// @dev to-do.list
/// 1. 주문 취소 기능 구현 필요 여부 확인 / 구현 방안 (어느단계까지 취소 가능 / 취소 시 반품은 어떻게 할지)
/// 2. 배송 트래킹 추가 시 multi-signature 필요 여부 확인 (현재는 넘겨주는 쪽에서 단독으로 트래킹 추가, 물건을 받는 쪽에서의 multi-signature가 필요해 보임)
/// 3. 트래킹 정보 수정 기능 추가 필요 여부 확인 (수정을 해도 그 내역은 블록체인에 기록됨)
/// @author jhhong
contract DkargoOrder is ERC165, DkargoPrefix {
    using Address for address;
    using SafeMath256 for uint256;

    /// @dev Tracking 구조체 정의
    struct Tracking {
        uint64 time; // 갱신 시각
        address member; // 물류 수행자의 주소
        uint256 code; // 배송 상태
        uint256 incentive; // 인센티브
    }

    /// @dev 변수 선언
    bool private _done; // 배송종료 여부
    uint256 private _orderid; // 주문번호
    uint256 private _curstep; // 현재 배송 step
    uint256 private _totalIncentives; // 참여자들에게 배분할 인센티브 총합
    string private _url; // 상세 URL 정보
    address private _service; // 서비스 컨트랙트 주소
    Tracking[] private _tracking; // 주문 트래킹 정보들을 담을 배열

    /// @dev 배송 상태코드 정의 상수
    uint256 constant private TRACKCODE_INIT = 10; // 주문 생성
    uint256 constant private TRACKCODE_CANCEL = 14; // 주문 취소
    uint256 constant private TRACKCODE_LAUNCH = 15; // 출발지 운송 시작
    uint256 constant private TRACKCODE_WAREHOUSING = 20; // 집하지 입고
    uint256 constant private TRACKCODE_RELEASED = 30; // 정상 출고
    uint256 constant private TRACKCODE_FLIGHT = 40; // 항공
    uint256 constant private TRACKCODE_LASTMILE = 60; // 도착지 운송 시작
    uint256 constant private TRACKCODE_COMPLETE = 70; // 배송 완료
    uint256 constant private TRACKCODE_FAILED = 99; // 배송 실패 (차후 실패 이유에 따른 코드 분리 고려)

    /// @notice 주문 상세정보 URL변경 이벤트
    /// @param oldUrl 주문 상세정보 이전 URL
    /// @param newUrl 주문 상세정보 변경된 URL
    event OrderUrlSet(string oldUrl, string newUrl);

    /// @notice 컨트랙트 생성자이다.
    /// @param url 물류 상세정보가 저장된 URL (string)
    /// @param service 서비스 컨트랙트 주소
    /// @param members 물류수행 참여자 주소 배열
    /// @param codes 물류 트래킹 코드 배열
    /// @param incentives 각 구간에서의 물류수행 완료 시 받는 인센티브 배열
    constructor(string memory url,
                address service,
                address[] memory members,
                uint256[] memory codes,
                uint256[] memory incentives) {
        require(service != address(0), "DkargoOrder: the service cannot be the zero");
        require(service.isContract() == true, "DkargoOrder: the service is not contract");
        require(members.length > 1, "DkargoOrder: too few members");
        require(members.length == codes.length, "DkargoOrder: out of sync(1)");
        require(members.length == incentives.length, "DkargoOrder: out of sync(2)");
        require(msg.sender == members[0], "DkargoOrder: only shipper can create order");
        _setDkargoPrefix("order"); // 프리픽스 설정
        _registerInterface(0x946edbed); // INTERFACE ID 등록 (getDkargoPrefix)
        _url = url; // URL 저장
        _service = service; // 서비스 컨트랙트 주소 저장
        _tracking.push(Tracking({time: 0, member: members[0], code: codes[0], incentive: incentives[0]})); // 화주 정보 추가
        _totalIncentives = _totalIncentives.add(incentives[0]);
        for(uint256 i = 1; i < members.length; i++) { // 물류사 정보 세팅
            _tracking.push(Tracking({time: 0, member: members[i], code: codes[i], incentive: incentives[i]})); // 물류사 정보 추가
            _totalIncentives = _totalIncentives.add(incentives[0]);
        }
    }

    /// @notice 주문 번호를 설정한다.
    /// @dev submitOrderCreate 수행 시 service.approveOrderCreate 내부에서만 호출됨
    /// @param id 주문 번호
    function setOrderId(uint256 id) public {
        require(msg.sender == _service, "DkargoOrder: only service can call"); // 서비스 컨트랙트의 approve() 내부에서만 호출됨
        _orderid = id;
    }

    /// @notice URL 정보를 갱신한다.
    /// @dev 호출 권한: 화주, 정상적인 운용 Flow에서는 호출되지 않는다.(서버 이전 / 재구축등의 사고로 인한 URL 갱신때만 호출)
    /// @param url 갱신될 URL
    function setUrl(string memory url) public {
        require(msg.sender == _tracking[0].member, "DkargoOrder: only shipper can call");
        emit OrderUrlSet(_url, url);
        _url = url;
    }

    /// @notice 주문 심사요청을 위해 주문을 서비스 컨트랙트에 제출한다.
    /// @dev 호출 권한: 화주
    function submitOrderCreate() public {
        require(msg.sender == _tracking[0].member, "DkargoOrder: only shipper can call");
        _tracking[0].time = uint64(block.timestamp); // 첫번째 배송상태 갱신 (from. 화주)
        _curstep = _curstep.add(1); // 배송 step 한단계 증가 (다음 step)
        _approveOrderCreate(msg.sender); // 서비스 컨트랙트로부터의 승인(approveOrderCreate) 요청
    }

    /// @notice 배송 트래킹 정보를 기록한다.
    /// @dev 물류사가 호출한다. 주문이 종료되면(done == true), 더 이상 본 함수 호출을 허용하지 않는다.
    /// @param time 상태 갱신 시각
    /// @param code 배송 상태
    function submitOrderUpdate(uint64 time, uint256 code) public {
        require(msg.sender == _tracking[_curstep].member, "DkargoOrder: unauthorized caller");
        require(_done == false, "DkargoOrder: the order has aleady been completed.");
        _onlyValidCode(code);
        if(code == TRACKCODE_FAILED) { // 배송 실패 처리
            _tracking[_curstep].code = TRACKCODE_FAILED;
            _done = true;
        } else { // 정상 배송완료 처리
            require(_tracking[_curstep].code == code, "DkargoOrder: code is out of order");
            _tracking[_curstep].time = time;
            _curstep = _curstep.add(1); // 배송 step 한단계 증가 (다음 step)
            if(_curstep == _tracking.length) { // 배송 종료 시 처리
                _done = true;
            }
        }
        _approveOrderUpdate(msg.sender, _curstep); // 서비스 컨트랙트로부터의 승인(approveOrderUpdate) 요청
    }

    /// @notice 주문이 배송실패 되었는지의 여부를 확인한다.
    /// @dev 배송종료(_done == true) 상태이고, 마지막 트래킹 코드가 TRACKCODE_FAILED 여야 한다.
    /// @return 주문의 배송실패 여부 (bool), true: O, false: X
    function isFailed() public view returns(bool) {
        return ((_done == true) && (_curstep < _tracking.length))? (true) : (false);
    }

    /// @notice 주문이 정상적으로 배송완료 되었는지의 여부를 확인한다.
    /// @dev 배송종료(_done == true) 상태이고, 모든 트래킹이 수행 완료되어야 한다. (_curstep == _tracking.length)
    /// @return 주문의 정상 배송완료 여부 (bool), true: O, false: X
    function isComplete() public view returns(bool) {
        return ((_done == true) && (_curstep == _tracking.length))? (true) : (false);
    }

    /// @notice 주문이 현재 LastMile 상태인지 여부를 확인한다.
    /// @dev LastMile: 수취인에게 배송 중인 상태 (배송의 마지막 단계)
    /// @return LastMile 상태 여부 (bool), true: O, false: X
    function isLastMile() public view returns(bool) {
        return ((_done == false) && (_tracking[_curstep].code == TRACKCODE_COMPLETE))? (true) : (false);
    }

    /// @notice 주문이 현재 처리되고 있는 구간 인덱스를 얻어온다.
    /// @return 주문이 현재 처리되고 있는 구간 인덱스
    function currentStep() public view returns(uint256) {
        return _curstep;
    }

    /// @notice 주문이 현재 처리되고 있는 구간의 추적 정보를 얻어온다.
    /// @return time 트래킹 시각
    /// @return addr 트래킹 수행주체
    /// @return code 배송상태 코드
    /// @return incentive 배송 인센티브
    function currentTracking() public view returns(uint64 time, address addr, uint256 code, uint256 incentive) {
        if(_curstep < _tracking.length) {
            time = _tracking[_curstep].time;
            addr = _tracking[_curstep].member;
            code = _tracking[_curstep].code;
            incentive = _tracking[_curstep].incentive;
        } else {
            time = 0;
            addr = address(0);
            code = 0;
            incentive = 0;
        }
    }

    /// @notice 주문번호를 얻어온다.
    /// @return 주문번호 (uint256)
    function orderid() public view returns(uint256) {
        return _orderid;
    }

    /// @notice 서비스 컨트랙트 주소를 얻어온다.
    /// @return 서비스 컨트랙트 주소 (address)
    function service() public view returns(address) {
        return _service;
    }

    /// @notice 주문의 총 인센티브 합을 얻어온다.
    /// @return 주문의 총 인센티브 합 (uint256)
    function totalIncentive() public view returns(uint256) {
        return _totalIncentives;
    }

    /// @notice index에 매핑되는 주문 추적 정보를 얻어온다.
    /// @param index Traking 인덱스
    /// @return time 트래킹 시각
    /// @return addr 트래킹 수행주체
    /// @return code 배송상태 코드
    /// @return incentive 배송 인센티브
    function tracking(uint256 index) public view returns(uint64 time, address addr, uint256 code, uint256 incentive) {
        if(index < _tracking.length) {
            time = _tracking[index].time;
            addr = _tracking[index].member;
            code = _tracking[index].code;
            incentive = _tracking[index].incentive;
        } else {
            time = 0;
            addr = address(0);
            code = 0;
            incentive = 0;
        }
    }

    /// @notice 주문에 대한 Tracking 총 수를 얻어온다.
    /// @return Tracking 총 수 (uint256)
    function trackingCount() public view returns(uint256) {
        return _tracking.length;
    }

    /// @notice URL 정보를 얻어온다.
    /// @return URL (string)
    function url() public view returns(string memory) {
        return _url;
    }

    /// @notice 물류사 컨트랙트에 문의하여 수취인 주소를 얻어온다.
    /// @return 수취인 주소 (address)
    function _getRecipient(address company) private view returns(address) {
        bytes memory data = address(company)._vcall(abi.encodeWithSignature("recipient()"));
        return abi.decode(data, (address));
    }

    /// @notice 서비스 컨트랙트에 문의하여 인센티브 토큰주소를 얻어온다.
    /// @return 인센티브 토큰주소 (address)
    function _getTokenAddress() private view returns(address) {
        bytes memory data = address(_service)._vcall(abi.encodeWithSignature("token()"));
        return abi.decode(data, (address));
    }

    /// @notice 주문 승인을 위해 서비스 컨트랙트의 approveOrderCreate를 호출한다.
    /// @param reporter 보고자 주소(화주)
    function _approveOrderCreate(address reporter) private {
        bytes memory cmd = abi.encodeWithSignature("approveOrderCreate(address,address)", address(this), reporter);
        address(_service)._call(cmd); // 서비스 컨트랙트에 "주문승인" 요청 -> 주문번호 할당받음, 이벤트 로그 발생
    }

    /// @notice 주문 상태갱신 알림을 위해 서비스 컨트랙트의 approveOrderUpdate를 호출한다.
    /// @param reporter 보고자 주소(물류사)
    /// @param transportid 운송번호 (구간배송번호)
    function _approveOrderUpdate(address reporter, uint256 transportid) private {
        bytes memory cmd = abi.encodeWithSignature("approveOrderUpdate(address,address,uint256)", address(this), reporter, transportid);
        address(_service)._call(cmd); // 서비스 컨트랙트에 "주문상태갱신" 요청 -> 이벤트 로그 발생
    }

    /// @notice 주어진 코드 번호가 가용한 코드인지 체크하고 가용하지 않을 경우 REVERT를 수행한다.
    /// @param code 코드 번호
    function _onlyValidCode(uint256 code) private pure {
        bool valid = true;
        do {
            if(code == TRACKCODE_INIT) break;
            if(code == TRACKCODE_CANCEL) break;
            if(code == TRACKCODE_LAUNCH) break;
            if(code == TRACKCODE_WAREHOUSING) break;
            if(code == TRACKCODE_RELEASED) break;
            if(code == TRACKCODE_FLIGHT) break;
            if(code == TRACKCODE_LASTMILE) break;
            if(code == TRACKCODE_COMPLETE) break;
            valid = false;
        } while(false);
        if(valid == false) {
            revert("DkargoOrder: the code is not valid");
        }
    }
}