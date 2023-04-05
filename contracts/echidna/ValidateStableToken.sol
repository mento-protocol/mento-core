pragma solidity ^0.5.13;

import {StableToken} from "../StableToken.sol";

contract EchidnaValidateStabletoken {
    StableToken public testee;

    constructor() public {
        testee = new StableToken(true);
        testee.initialize("Celo Dollar", "cUSD", 18, address(2000), 1e24, 1 weeks, new address[](0), new uint256[](0),"Exchange");
        
    }

    function crytic_ZeroAlwaysEmptyERC20Properties() public returns(bool){
        return testee.balanceOf(address(0x0)) == 0;
    }
    /*
    function crytic_totalSupply_consistant_ERC20Properties() public returns(bool){
        return testee.balanceOf(crytic_owner) + testee.balanceOf(crytic_user) + testee.balanceOf(crytic_attacker) <= testee.totalSupply();
    }

    function crytic_transfer_to_other_ERC20PropertiesTransferable() public returns(bool){
        uint balance = testee.balanceOf(msg.sender);
        address other = crytic_user;
        if (other == msg.sender) {
            other = crytic_owner;
        }
        if (balance >= 1) {
            bool transfer_other = testee.transfer(other, 1);
            return (testee.balanceOf(msg.sender) == balance-1) && (testee.balanceOf(other) >= 1) && transfer_other;
        }
        return true;
    }*/
}