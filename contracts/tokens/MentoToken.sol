// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "openzeppelin-contracts-next/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract MentoToken is ERC20, ERC20Burnable {
    constructor(address vestingContract, address airgrabContract, address treasuryContract, address emissionContract)
        ERC20("Mento Token", "MENTO") 
    {
        uint256 initialSupply= 1_000_000_000 * 10 ** decimals();
        
        uint256 vestingSupply = initialSupply / 5; // 20%
        uint256 airgrabSupply =  initialSupply / 20; // 5%
        uint256 treasurySupply = initialSupply / 10; // 10%
        uint256 emissionSupply = (initialSupply * 65 ) / 100; // 65%

        _mint(vestingContract, vestingSupply);
        _mint(airgrabContract, airgrabSupply);
        _mint(treasuryContract, treasurySupply);
        _mint(emissionContract, emissionSupply);
    }
}