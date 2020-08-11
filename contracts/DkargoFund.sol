// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "./DkargoPrefix.sol";
import "./authority/Ownership.sol";
import "./introspection/ERC165/ERC165.sol";
import "./libs/Address.sol";
import "./libs/chain/ChainUint64.sol";
import "./libs/chain/Typedef.sol";
import "./libs/math/SafeMath256.sol";

/// @title DkargoFund
/// @notice 디카르고 펀드 컨트랙트 정의
/// @author jhhong
contract DkargoFund is Ownership, ERC165, DkargoPrefix {
    using Address for address;
    using SafeMath256 for uint256;
    using ChainUint64 for Typedef.Uint64List;

    /// @dev 변수 선언
    address private _beneficier; // 수취인 주소
    address private _token; // 토큰 컨트랙트 주소
    uint256 private _totals; // 플랜에 기록된 총 인출량, 펀드의 보유 토큰량을 초과할 수 없다.
    mapping(uint64 => uint256) private _plans; // 락업 플랜
    Typedef.Uint64List private _planchain; // 락업 플랜 체인

    /// @notice 수취인 주소 업데이트 이벤트
    /// @param beneficier 수취인 주소
    event BeneficierUpdated(address indexed beneficier);

    /// @notice lock-up 플랜 설정 이벤트
    /// @dev amount = 0이면 lock-up 플랜 제거 이벤트이다.
    /// @param time unlock될 시각 (epoch time)
    /// @param amount unlock될 양
    event PlanSet(uint64 time, uint256 amount);

    /// @notice 인출 이벤트
    /// @param amount 인출 금액
    event Withdraw(uint256 amount);

    /// @notice 컨트랙트 생성자이다.
    /// @param token 토큰 컨트랙트 주소
    /// @param beneficier 수취인 주소
    constructor(address token, address beneficier) {
        require(token != address(0), "DkargoFund: token is null");
        require(beneficier != address(0), "DkargoFund: beneficier is null");
        _setDkargoPrefix("fund"); // 프리픽스 설정 (fund)
        _registerInterface(0x946edbed); // INTERFACE ID 등록 (getDkargoPrefix)
        _token = token;
        _beneficier = beneficier;
    }

    /// @notice 인출금액 수취인을 설정한다.
    /// @dev 수취인 주소로 EOA, CA 다 설정 가능하다.
    /// @param beneficier 설정할 수취인 주소 (address)
    function setBeneficier(address beneficier) onlyOwner public {
        require(beneficier != address(0), "DkargoFund: beneficier is null");
        require(beneficier != _beneficier, "DkargoFund: should be not equal");
        _beneficier = beneficier;
        emit BeneficierUpdated(beneficier);
    }

    /// @notice 인출 플랜을 추가한다.
    /// @dev amount!=0이면 새 플랜을 추가한다는 의미이다. linkChain 과정이 수행된다. 기존에 설정된 플랜이 있을 경우 덮어쓴다.
    /// amount=0이면 플랜을 삭제한다는 의미이다. unlinkChain 과정이 수행된다. 기존에 설정된 플랜이 없을 경우 revert된다.
    /// time은 현재 시각(block.timestamp)보다 큰 값이어야 한다.
    /// 설정된 플랜들의 모든 amount의 합은 balanceOf(fundCA)를 초과할 수 없다.
    /// @param time 인출 가능한 시각
    /// @param amount 인출 가능한 금액
    function setPlan(uint64 time, uint256 amount) onlyOwner public {
        require(time > block.timestamp, "DkargoFund: invalid time");
        _totals = _totals.add(amount); // 추가될 플랜 금액을 총 플랜금액에 합산
        _totals = _totals.sub(_plans[time]); // 총 플랜금액에서 기존 설정된 금액을 차감
        require(_totals <= fundAmount(), "DkargoFund: over the limit"); // 총 플랜금액 체크
        _plans[time] = amount; // 플랜 금액 갱신
        emit PlanSet(time, amount); // 이벤트 발생
        if(amount == 0) { // 체인정보 갱신
            _planchain.unlinkChain(time); // 기존에 설정되지 않았을 경우, revert("AddressChain: the node is aleady unlinked")
        } else if(_planchain.isLinked(time) == false) { // 새 설정일 경우에만 체인추가, 기존 설정이 있을 경우, 값만 갱신하고 체인 정보는 갱신하지 않음
            _planchain.linkChain(time);
        }
    }

    /// @notice 토큰을 지정된 수취인에게로 인출한다.
    /// @dev 만료되지 않은 index는 인출 불가능하다. revert!
    /// 설정되지 않은 (혹은 해제된) 플랜 인덱스에 대해서는 revert!
    /// @param index 플랜 인덱스, setPlan에서 넣어줬던 인출 가능 시각이다.
    function withdraw(uint64 index) onlyOwner public {
        require(index <= block.timestamp, "DkargoFund: an unexpired plan");
        require(_plans[index] > 0, "DkargoFund: plan is not set");
        bytes memory cmd = abi.encodeWithSignature("transfer(address,uint256)", _beneficier, _plans[index]);
        bytes memory data = address(_token)._call(cmd);
        bool result = abi.decode(data, (bool));
        require(result == true, "DkargoFund: failed to proceed raw-data");
        _totals = _totals.sub(_plans[index]); // 총 플랜금액에서 기존 설정된 금액을 차감
        emit Withdraw(_plans[index]);
        _plans[index] = 0;
        _planchain.unlinkChain(index);
    }

    /// @notice Fund 컨트랙트의 밸런스를 확인한다.
    /// @return Fund 컨트랙트의 밸런스 (uint256)
    function fundAmount() public view returns(uint256) {
        bytes memory data = address(_token)._vcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        return abi.decode(data, (uint256));
    }

    /// @notice 플랜에 기록된 총 금액을 확인한다.
    /// @return 플랜에 기록된 총 금액 (uint256)
    function totalPlannedAmount() public view returns(uint256) {
        return _totals;
    }

    /// @notice 플랜 인덱스에 해당하는 인출 금액을 확인한다.
    /// @param index 플랜 인덱스, setPlan에서 넣어줬던 인출 가능 시각이다.
    /// @return 플랜 인덱스에 해당하는 인출 금액 (uint256)
    function plannedAmountOf(uint64 index) public view returns(uint256) {
        return _plans[index];
    }

    /// @notice 수취인 주소를 확인한다.
    /// @return 수취인 주소 (address)
    function beneficier() public view returns(address) {
        return _beneficier;
    }

    /// @notice 토큰(ERC-20) 주소를 확인한다.
    /// @return 토큰 주소 (address)
    function token() public view returns(address) {
        return _token;
    }
}