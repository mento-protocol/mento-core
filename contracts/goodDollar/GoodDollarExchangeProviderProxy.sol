// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {
  TransparentUpgradeableProxy
} from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract GoodDollarExchangeProviderProxy is TransparentUpgradeableProxy {
  constructor(
    address _logic,
    address admin_,
    bytes memory _data
  ) payable TransparentUpgradeableProxy(_logic, admin_, _data) {}
}
