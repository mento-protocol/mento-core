// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { console } from "forge-std-next/console.sol";
import { Test } from "forge-std-next/Test.sol";
import { Arrays } from "test/utils/Arrays.sol";

import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";
import { Airgrab } from "contracts/governance/Airgrab.sol";

/**
 * A merkle tree was generated based on the following CSV file:
 * -----
 * 0x547a9687D36e51DA064eE7C6ac82590E344C4a0e,100000000000000000000
 * 0x6B70014D9c0BF1F53695a743Fe17996f132e9482,20000000000000000000000
 * ----
 * Merkle Root: 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809
 * Proof[0x5..] = [ 0xf213211627972cf2d02a11f800ed3f60110c1d11d04ec1ea8cb1366611efdaa3 ]
 * Proof[0x6..] = [ 0x0294d3fc355e136dd6fea7f5c2934dd7cb67c2b4607110780e5fbb23d65d7ac4 ]
 */
contract Airgrab_Base_Test is Test {
  uint32 public constant MAX_CLIFF_PERIOD = 103;
  uint32 public constant MAX_SLOPE_PERIOD = 104;

  string constant EXPECTED_CREDENTIAL = 
    "I authorize Mento (dc3aa1910acbb7ff4d22c07e43a6926adc3a81305a9355a304410048c9a91afd) to get a proof from Fractal that:\n"
    "- I passed KYC level plus+liveness\n"
    "- I am not a citizen of the following countries: Germany (DE)\n"
    "- I am not a resident of the following countries: Germany (DE)";

  string constant OTHER_CREDENTIAL =
    "I authorize Mento (dc3aa1910acbb7ff4d22c07e43a6926adc3a81305a9355a304410048c9a91afd) to get a proof from Fractal that:\n"
    "- I passed KYC level plus\n"
    "- I am not a citizen of the following countries: Germany (DE)";


  Airgrab public airgrab;
  ERC20 public token;

  address payable public treasury = payable(makeAddr("Treasury"));
  address public fractalIssuer = makeAddr("FractalIssuer");
  address public lockingContract = makeAddr("LockingContract");
  address public tokenAddress;

  bytes32 public merkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809;
  address public invalidClaimer = makeAddr("InvalidClaimer");
  address public claimer0 = 0x547a9687D36e51DA064eE7C6ac82590E344C4a0e;
  uint256 public claimer0Amount = 100000000000000000000;
  bytes32[] public claimer0Proof = Arrays.bytes32s(0xf213211627972cf2d02a11f800ed3f60110c1d11d04ec1ea8cb1366611efdaa3);
  address public claimer1 = 0x6B70014D9c0BF1F53695a743Fe17996f132e9482;
  uint256 public claimer1Amount = 20000000000000000000000;
  bytes32[] public claimer1Proof = Arrays.bytes32s(0x0294d3fc355e136dd6fea7f5c2934dd7cb67c2b4607110780e5fbb23d65d7ac4);

  uint256 public endTimestamp = block.timestamp + 1 days;

  uint256 basePercentage = 20 * 1e16; // 20% with 1e18 precission
  uint256 lockPercentage = 10 * 1e16; // 10% with 1e18 precision
  uint256 cliffPercentage = 30 * 1e16; // 30% with 1e18 precision
  uint256 slopePercentage = 40 * 1e16; // 40% with 1e18 precision

  uint32 requiredCliffPeriod = 14; // 14 weeks ~= 3months
  uint32 requiredSlopePeriod = 14; // 14 weeks ~= 3months

  function setUp() public virtual {
    vm.label(claimer0, "Claimer0");
    vm.label(claimer1, "Claimer1");
    token = new ERC20("Mento Token", "MENTO");
    tokenAddress = address(token);
    vm.label(tokenAddress, "MENTO");
  }

  /// @notice Create a new Airgrab, but don't initialize it.
  function newAirgrab() internal {
    airgrab = new Airgrab(
      merkleRoot,
      fractalIssuer,
      lockingContract,
      treasury,
      endTimestamp,
      basePercentage,
      lockPercentage,
      cliffPercentage,
      slopePercentage,
      requiredCliffPeriod,
      requiredSlopePeriod
    );
  }

  /// @notice Create and initialize an Airgrab.
  function initAirgrab() internal {
    newAirgrab();
    airgrab.initialize(tokenAddress);
  }
}
