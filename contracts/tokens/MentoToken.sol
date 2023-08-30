// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";

contract MentoToken is ERC20 {
    constructor() ERC20("Mento Token", "MENTO") {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }
}