// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "./DkargoPrefix.sol";
import "./authority/Ownership.sol";
import "./introspection/ERC165/ERC165.sol";
import "./libs/Address.sol";
import "./libs/chain/ChainAddress.sol";
import "./libs/chain/Typedef.sol";
import "./libs/math/SafeMath256.sol";

/// @title DkargoService
/// @notice 서비스 컨트랙트 정의
/// @author jhhong
contract DkargoService is Ownership, ERC165, DkargoPrefix {
    using Address for address;
    using ChainAddress for Typedef.AddressList;
    using SafeMath256 for uint256;

    /// @dev 구조체 정의
    struct Degree { // 물류사가 수행한 주문 처리 결과 누계 저장용 구조체
        bool applied; // 반영 여부 플래그 (주문 하나에 대해 여러 배송구간을 한 개의 물류사가 처리할 경우 중복처리 방지용)
        uint256 success; // 배송 완료한 주문 개수
        uint256 totals; // 담당 주문 총 개수
    }
    struct Incentive { // 인센티브 정보
        uint256 totals; // 현재 받을 수 있는 인센티브 금액
        uint256 settlements; // 정산 수행 시 지급될 실제 인센티브 금액
    }

    /// @dev 변수 선언(주문)
    uint256 private _ordercnt; // 등록된 주문 컨트랙트 개수
    mapping(uint256 => address) private _orders; // "주문번호" <-> "주문 컨트랙트 주소" 매핑변수

    /// @dev 변수 선언(물류사)
    mapping(address => Degree) private _degree; // "물류사주소" <-> "물류사평점" 매핑변수
    Typedef.AddressList private _companychain; // 물류사 체인

    /// @dev 변수 선언(인센티브)
    mapping(address => Incentive) private _incentives; // "참여자주소" <-> "인센티브 정보" 매핑변수 (참여자: 인센티브 수령대상자들 (화주+물류사수취인))
    Typedef.AddressList private _recipientchain; // 인센티브 수령 대상자 체인

    /// @notice 물류사 등록 이벤트
    /// @param company 물류사 컨트랙트 주소
    event CompanyRegistered(address indexed company);

    /// @notice 물류사 등록해제 이벤트
    /// @param company 물류사 컨트랙트 주소
    event CompanyUnregistered(address indexed company);

    /// @notice 주문 생성완료 이벤트, 주문이 정상 승인되어 주문번호를 할당받으면 이벤트가 발생된다.
    /// @param order 주문 컨트랙트 주소
    /// @param id 주문번호
    event OrderCreated(address indexed order, uint256 id);

    /// @notice 주문 상태갱신 이벤트
    /// @dev 다음 구간 담당자가 launch를 수행할 수 있도록 알림
    /// @param order 주문 컨트랙트 주소
    /// @param from 배송 완료한 현재 구간 담당자
    /// @param to 다음 배송 구간 담당자
    /// @param transportid 운송번호 (구간배송번호)
    event OrderTransferred(address indexed order, address indexed from, address indexed to, uint256 transportid);

    /// @notice 인센티브 업데이트 이벤트
    /// @param addr 인센티브 지급 주소
    /// @param value 업데이트될 양
    event IncentiveUpdated(address indexed addr, uint256 value);

    /// @notice 인센티브 정산 이벤트
    /// @param addr 인센티브 지급 주소
    /// @param value 지급액
    /// @param rests 잔여 인센티브
    event Settled(address indexed addr, uint256 value, uint256 rests);

    /// @notice 컨트랙트 생성자이다.
    constructor() {
        _setDkargoPrefix("service"); // 프리픽스 설정
        _registerInterface(0x946edbed); // INTERFACE ID 등록 (getDkargoPrefix)
    }

    /// @notice 주문 생성을 승인한다.
    /// @dev 주문의 적합성을 검사하여 주문을 최종 승인하고 플랫폼의 주문 리스트에 등록시켜 주문번호를 발행하는 역할을 수행한다.
    /// @dev 호출주체: 주문 컨트랙트 (DkargoOrder)
    /// @param order 주문 컨트랙트 주소
    /// @param reporter 보고자 주소(화주)
    function approveOrderCreate(address order, address reporter) public {
        uint256 trackingcnt = _getTrackingCount(order);
        require(trackingcnt > 1, "DkargoService: the order has too few members"); // 최소 트래킹 개수는 2!!(화주+물류사1)
        require(msg.sender == order, "DkargoService: only the order itself can call");
        for(uint256 idx = 1; idx < trackingcnt; idx++) { // 각 트래킹 정보들에 대한 validation 체크
            (address company,) = _getTracking(order, idx);
            if (_companychain.isLinked(company) == false) { // 물류사가 등록된 물류사인지 체크
                revert("DkargoService: the order has unregistered company");
            }
            if (_degree[company].applied == false) {
                _degree[company].applied = true;
            }
        }
        for(uint256 idx = 1; idx < trackingcnt; idx++) { // 각 물류사의 담당 주문 총 개수 갱신
            (address company,) = _getTracking(order, idx);
            if (_degree[company].applied == true) {
                _degree[company].totals = _degree[company].totals.add(1);
                _degree[company].applied = false;
            }
        }
        _ordercnt = _ordercnt.add(1); // 주문 컨트랙트 개수 갱신, 이 값이 현재 주문의 "주문번호"가 됨
        _orders[_ordercnt] = order; // "주문번호"에 해당하는 매퍼에 주문 컨트랙트 주소 등록
        _setOrderId(order, _ordercnt); // 주문 컨트랙트에 주문번호를 부여
        emit OrderCreated(order, _ordercnt); // 이벤트 발생: 주문생성
        address nextMember = _getCurrentTracking(order); // 주문의 다음 배송 담당자 값 획득
        emit OrderTransferred(order, reporter, nextMember, 1); // 이벤트 발생: 주문 상태갱신
    }

    /// @notice 주문 상태갱신을 승인한다.
    /// @dev 주문 상태갱신 이벤트 발생, 주문 종료시 갱신될 데이터: 물류사들의 평점, 참여자 인센티브 갱신
    /// 호출주체: 주문 컨트랙트(DkargoOrder): 물류사 컨트랙트.updateOrderCode -> 주문 컨트랙트.submitOrderUpdate -> approveOrderUpdate
    /// 호출시점: 매 주문 갱신이 발생할 때마다 호출됨
    /// @param order 주문 컨트랙트 주소
    /// @param reporter 보고자 주소(물류사)
    /// @param transportid 운송번호 (구간배송번호)
    function approveOrderUpdate(address order, address reporter, uint256 transportid) public {
        require(msg.sender == order, "DkargoService: only the order itself can call");
        uint256 trackingcnt = _getTrackingCount(order);
        require(trackingcnt > 1, "DkargoService: the order has too few members"); // 최소 트래킹 개수는 2!!(화주+물류사1)
        address nextMember = _getCurrentTracking(order); // 주문의 다음 배송 담당자 값 획득
        if(_isOrderFailed(order) == false) { // 차후 배송실패에 따른 패널티 적용 정책이 확정되면 _isOrderFailed(order) == true일 때의 코드 작업 추가 필요
            emit OrderTransferred(order, reporter, nextMember, transportid); // 이벤트 발생: 주문 상태갱신
            if(_isOrderComplete(order) == true) { // 성공적으로 배송완료된 주문: 인센티브 갱신 + 물류사 평점 갱신
                //// 화주 인센티브 갱신
                (address shipper, uint256 incentive) = _getTracking(order, 0); // 화주의 주소와 인센티브 정보 추출
                if(incentive > 0) {
                    _incentives[shipper].totals = (_incentives[shipper].totals).add(incentive); // 화주의 인센티브 갱신
                    emit IncentiveUpdated(shipper, incentive); // 이벤트 발생: 인센티브 갱신 (화주)
                    if (_recipientchain.isLinked(shipper) == false && _incentives[shipper].totals > 0) {
                        _recipientchain.linkChain(shipper); // 인센티브 수령대상자 체인 연결
                    }
                }
                //// 물류사 인센티브 갱신 + 물류사 평점 갱신
                for(uint256 idx = 1; idx < trackingcnt; idx++) { // 배송에 참여한 모든 물류사들에 대해서
                    (address company, uint256 incentivee) = _getTracking(order, idx); // 물류사 주소와 인센티브 정보 추출
                    if(incentivee > 0) {
                        address recipient = _getRecipient(company); // 물류사의 수취인 주소 추출
                        _incentives[recipient].totals = (_incentives[recipient].totals).add(incentivee); // 물류사 인센티브 갱신
                        emit IncentiveUpdated(recipient, incentivee); // 이벤트 발생: 인센티브 갱신 (물류사)
                        if (_recipientchain.isLinked(recipient) == false && _incentives[recipient].totals > 0) {
                            _recipientchain.linkChain(recipient); // 인센티브 수령대상자 체인 연결
                        }
                        if (_degree[company].applied == false) {
                            _degree[company].applied = true;
                        }
                    }
                }
                for(uint256 idx = 1; idx < trackingcnt; idx++) { // 배송에 참여한 모든 물류사들에 대해서
                    (address company,) = _getTracking(order, idx);
                    if (_degree[company].applied == true) {
                        _degree[company].success = _degree[company].success.add(1);
                        _degree[company].applied = false;
                    }
                }
            }
        }
    }

    /// @notice 물류사를 디카르고 플랫폼의 멤버로 등록한다.
    /// @dev 물류사의 스테이킹 과정 확인 / 정립 필요, 현재는 onlyOwner...
    /// 궁극적으로는 DkargoCompany 컨트랙트에서 staking 수행 시 본 함수가 연계되는 구조로 가야 할 것 (DkargoOrder가 주문등록을 위해 approve를 호출하듯이..)
    /// @param company 물류사 컨트랙트 주소
    function register(address company) onlyOwner public {
        //// Staking 등록절차 확인: AUGUR 동작방식 분석 / 적용 필요
        _companychain.linkChain(company); // 물류사 등록
        emit CompanyRegistered(company); // 이벤트 발생: 물류사 등록
    }

    /// @notice 물류사를 디카르고 플랫폼의 멤버에서 등록해제한다.
    /// @dev 물류사의 스테이킹 과정 확인 / 정립 필요, 현재는 onlyOwner...
    /// 궁극적으로는 DkargoCompany 컨트랙트에서 staking 수행 시 본 함수가 연계되는 구조로 가야 할 것 (DkargoOrder가 주문등록을 위해 approve를 호출하듯이..)
    /// @param company 물류사 컨트랙트 주소
    function unregister(address company) onlyOwner public {
        //// Staking 해제절차 확인: AUGUR 동작방식 분석 / 적용 필요
        _companychain.unlinkChain(company); // 물류사 등록해제
        emit CompanyUnregistered(company); // 이벤트 발생: 물류사 등록해제
    }

    /// @notice 주소(참여자)가 받아야 할 인센티브를 정산한다.
    /// @dev onlyOwner, 매 settle 수행 시 settlements만큼 지급되고 totals = totals-settlements로 갱신됨
    /// @param addr 인센티브를 받을 주소 (화주주소, 물류사의 수취인주소)
    function settle(address addr) onlyOwner public {
        uint256 value = _incentives[addr].settlements;
        _incentives[addr].totals = _incentives[addr].totals.sub(_incentives[addr].settlements); // totals값 갱신
        _incentives[addr].settlements = _incentives[addr].totals; // settlements값 갱신
        if(_incentives[addr].totals == 0 && _recipientchain.isLinked(addr) == true) {
            _recipientchain.unlinkChain(addr); // 인센티브 수령대상자 체인 연결해제
        }
        emit Settled(addr, value, _incentives[addr].totals);
    }

    /// @notice 디카르고 플랫폼에 등록된 물류사의 "배송완료 주문 총 개수"를 반환한다.
    /// @dev 현재는 success 하나뿐이지만, 향후 항목이 늘어나면 array type의 return이 되어야 할 것
    /// @param company 물류사 컨트랙트 주소
    /// @return 물류사의 "배송완료 주문 총 개수" (uint256)
    function completeOrders(address company) public view returns(uint256) {
        return _degree[company].success;
    }

    /// @notice 디카르고 플랫폼에 등록된 물류사의 "담당한 주문 총 개수"를 반환한다.
    /// @dev 현재는 success 하나뿐이지만, 향후 항목이 늘어나면 array type의 return이 되어야 할 것
    /// @param company 물류사 컨트랙트 주소
    /// @return 물류사의 "담당한 주문 총 개수" (uint256)
    function totalOrders(address company) public view returns(uint256) {
        return _degree[company].totals;
    }

    /// @notice 주소의 인센티브 수령 정보를 반환한다. (totals, settlements)
    /// @dev totals: 수령가능한 총 인센티브양, settlements: 다음 settle때 수령하게 될 인센티브양
    /// @param addr 인센티브 수취인 주소
    /// @return totals: 수령가능한 총 인센티브양, settlements: 다음 settle때 수령하게 될 인센티브양 (uint256,uint256)
    function incentives(address addr) public view returns(uint256, uint256) {
        return (_incentives[addr].totals, _incentives[addr].settlements);
    }

    /// @notice 디카르고 플랫폼에 등록된 물류사인지의 여부를 반환한다.
    /// @param company 물류사 컨트랙트 주소
    /// @return 디카르고 플랫폼에 등록된 물류사인지의 여부(bool)
    function isMember(address company) public view returns(bool) {
        return _companychain.isLinked(company);
    }

    /// @notice 등록된 첫번째 물류사 컨트랙트 주소를 반환한다.
    /// @return 등록된 첫번째 물류사 컨트랙트 주소 (address)
    function firstCompany() public view returns(address) {
        return _companychain.first();
    }

    /// @notice 등록된 마지막 물류사 컨트랙트 주소를 반환한다.
    /// @return 등록된 마지막 물류사 컨트랙트 주소 (address)
    function lastCompany() public view returns(address) {
        return _companychain.last();
    }

    /// @notice 디카르고 플랫폼에 등록된 주문의 총 개수를 반환한다.
    /// @return 주문의 총 개수 (uint256)
    function companyCount() public view returns(uint256) {
        return _companychain.size();
    }

    /// @notice 등록된 물류사 중 company 바로 다음의 물류사 컨트랙트 주소를 반환한다.
    /// @param company 물류사 컨트랙트 주소
    /// @return company 바로 다음의 물류사 컨트랙트 주소 (address)
    function nextCompany(address company) public view returns(address) {
        return _companychain.nextOf(company);
    }

    /// @notice 등록된 물류사 중 company 바로 이전의 물류사 컨트랙트 주소를 반환한다.
    /// @param company 물류사 컨트랙트 주소
    /// @return company 바로 이전의 물류사 컨트랙트 주소 (address)
    function prevCompany(address company) public view returns(address) {
        return _companychain.prevOf(company);
    }

    /// @notice 첫번째 인센티브 수여자 주소를 반환한다.
    /// @return 첫번째 인센티브 수여자 주소 (address)
    function firstRecipient() public view returns(address) {
        return _recipientchain.first();
    }

    /// @notice 마지막 인센티브 수여자 주소를 반환한다.
    /// @return 마지막 인센티브 수여자 주소 (address)
    function lastRecipient() public view returns(address) {
        return _recipientchain.last();
    }

    /// @notice 인센티브 수여자 수를 반환한다.
    /// @return 인센티브 수여자 수 (uint256)
    function recipientCount() public view returns(uint256) {
        return _recipientchain.size();
    }

    /// @notice recipient 바로 다음의 인센티브 수여자 주소를 반환한다.
    /// @param recipient 인센티브 수여자 주소
    /// @return recipient 바로 다음의 인센티브 수여자 주소 (address)
    function nextRecipient(address recipient) public view returns(address) {
        return _recipientchain.nextOf(recipient);
    }

    /// @notice recipient 바로 이전의 인센티브 수여자 주소를 반환한다.
    /// @param recipient 인센티브 수여자 주소
    /// @return recipient 바로 이전의 인센티브 수여자 주소 (address)
    function prevRecipient(address recipient) public view returns(address) {
        return _recipientchain.prevOf(recipient);
    }

    /// @notice 주문번호에 해당하는 주문 컨트랙트 주소를 반환한다.
    /// @return 주문번호에 해당하는 주문 컨트랙트 주소 (address)
    function orders(uint256 id) public view returns(address) {
        return _orders[id];
    }

    /// @notice 디카르고 플랫폼에 등록된 주문의 총 개수를 반환한다.
    /// @return 주문의 총 개수 (uint256)
    function orderCount() public view returns(uint256) {
        return _ordercnt;
    }

    /// @notice 주문 컨트랙트의 현재 트래킹 정보를 얻어온다.
    /// @dev 현재 다른 정보는 사용되지 않으므로 addr만 반환함
    /// @param order 주문 컨트랙트 주소
    /// @return addr 주문의 현재 배송 담당자
    function _getCurrentTracking(address order) private view returns(address addr) {
        bytes memory data = address(order)._vcall(abi.encodeWithSignature("currentTracking()"));
        (,addr,,) = abi.decode(data, (uint64, address, uint256, uint256));
    }

    /// @notice 물류사 컨트랙트에 문의하여 수취인 주소를 얻어온다.
    /// @return 수취인 주소 (address)
    function _getRecipient(address company) private view returns(address) {
        bytes memory data = address(company)._vcall(abi.encodeWithSignature("recipient()"));
        return abi.decode(data, (address));
    }

    /// @notice 주문 컨트랙트의 트래킹 정보 중 index에 해당하는 트래킹 정보를 얻어온다.
    /// @dev 현재 다른 정보는 사용되지 않으므로 addr, incentive만 반환함
    /// @param order 주문 컨트랙트 주소
    /// @param index 트래킹 인덱스
    /// @return addr 트래킹을 추가한 주소(address)
    /// @return incentive 인센티브(uint256)
    function _getTracking(address order, uint256 index) private view returns(address addr, uint256 incentive) {
        bytes memory data = address(order)._vcall(abi.encodeWithSignature("tracking(uint256)", index));
        (,addr,, incentive) = abi.decode(data, (uint64, address, uint256, uint256));
    }

    /// @notice 주문 컨트랙트의 트래킹 정보 총 개수를 얻어온다.
    /// @param order 주문 컨트랙트 주소
    /// @return 주문 컨트랙트 주소
    function _getTrackingCount(address order) private view returns(uint256) {
        bytes memory data = address(order)._vcall(abi.encodeWithSignature("trackingCount()"));
        return abi.decode(data, (uint256));
    }

    /// @notice 배송이 성공적으로 완료된 주문 컨트랙트인지 확인
    /// @param order 주문 컨트랙트 주소
    /// @return 배송이 성공적으로 완료되었는지의 여부
    function _isOrderComplete(address order) private view returns(bool) {
        bytes memory data = address(order)._vcall(abi.encodeWithSignature("isComplete()"));
        return abi.decode(data, (bool));
    }

    /// @notice 배송이 종료된 주문 컨트랙트인지 확인
    /// @param order 주문 컨트랙트 주소
    /// @return 배송이 성공적으로 완료되었는지의 여부
    function _isOrderFailed(address order) private view returns(bool) {
        bytes memory data = address(order)._vcall(abi.encodeWithSignature("isFailed()"));
        return abi.decode(data, (bool));
    }

    /// @notice 주문 컨트랙트에 주문번호를 부여한다.
    /// @dev 주문 컨트랙트에서의 setOrderId 절차가 정상적이지 않을 경우 Revert된다.
    /// @param order 주문 컨트랙트 주소
    /// @param id 부여될 주문번호
    function _setOrderId(address order, uint256 id) private {
        bytes memory cmd = abi.encodeWithSignature("setOrderId(uint256)", id);
        address(order)._call(cmd); // 주문 컨트랙트에 주문번호를 부여
    }
}