// SPDX-License-Identifier: BUSL-1.1
// solhint-disable gas-custom-errors
pragma solidity 0.8.18;

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";

/**
 * @title Temporary implementation for StableTokenV2.
 * @dev Has a name update function and name variable in the same slot as the original
 *      implementation.
 */
contract TempStable is Ownable {
  // slot 0 = Ownable._owner
  // slither-disable-next-line constable-states
  address public slot1; // slot 1
  string private _name; // slot 2

  function setName(string calldata newName) external onlyOwner {
    _name = newName;
  }

  function name() public view returns (string memory) {
    return _name;
  }
}
