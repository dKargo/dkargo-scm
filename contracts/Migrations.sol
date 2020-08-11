// SPDX-License-Identifier: MIT
pragma solidity >=0.4.21; // jhhong modified: solc v0.7.0으로 업그레이드

contract Migrations {
  address public owner;
  uint public last_completed_migration;

  constructor() { // jhhong modified: solc v0.7.0 -> constructor에 visibility를 명시하지 않는다.
    owner = msg.sender;
  }

  modifier restricted() {
    if (msg.sender == owner) _;
  }

  function setCompleted(uint completed) public restricted {
    last_completed_migration = completed;
  }
}
