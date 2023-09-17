// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ECDSA } from "openzeppelin-contracts-next/contracts/utils/cryptography/ECDSA.sol";
import { Airdrop_Test } from "./Base.t.sol";

contract IsValidKyc_Airdrop_Test is Airdrop_Test {
  uint8 kycType = 1;
  uint8 countryOfResidence = 2;

  function setUp() public override {
    super.setUp();
    initAirdrop();
  }

  /// @notice When kycType = 1 and countryOfResidence != 7, returns true
  function test_IsValidKyc_whenValid() public {
    assertEq(airdrop.isValidKyc(1, 2), true);
  }

  /// @notice When kycType != 1, returns false
  function test_IsValidKyc_whenKycTypeInvalid() public {
    assertEq(airdrop.isValidKyc(2, 2), false);
  }

  /// @notice When country of residence is invalid, returns false
  function test_IsValidKyc_whenCountryOfResidenceIsInvalid() public {
    assertEq(airdrop.isValidKyc(1, 7), false);
    assertEq(airdrop.isValidKyc(1, 9), false);
    assertEq(airdrop.isValidKyc(1, 0), false);
  }
}
