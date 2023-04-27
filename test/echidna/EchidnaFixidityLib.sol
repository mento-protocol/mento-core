pragma solidity ^0.5.13;
import "../../contracts/common/FixidityLib.sol";

// solhint-disable-next-line max-line-length
//echidna ./test/echidna/EchidnaFixidityLib.sol --contract EchidnaFixidityLib --config ./echidna.yaml --test-mode assertion

contract EchidnaFixidityLib {
  function wrapUnwrap(uint256 a) public returns (bool) {
    FixidityLib.Fraction memory fraction = FixidityLib.wrap(a);
    uint256 r = FixidityLib.unwrap(fraction);
    assert(r == a);
  }

  function integerFractional(uint256 a) public returns (bool) {
    FixidityLib.Fraction memory fraction = FixidityLib.Fraction(a);
    FixidityLib.Fraction memory integer = FixidityLib.integer(fraction);
    FixidityLib.Fraction memory fractional = FixidityLib.fractional(fraction);
    assert(fraction.value == integer.value + fractional.value);
  }

  function addSubtract(uint256 a, uint256 b) public returns (bool) {
    FixidityLib.Fraction memory fraction1 = FixidityLib.Fraction(a);
    FixidityLib.Fraction memory fraction2 = FixidityLib.Fraction(b);
    FixidityLib.Fraction memory sum = FixidityLib.add(fraction1, fraction2);
    FixidityLib.Fraction memory result = FixidityLib.subtract(sum, fraction2);
    uint256 r = FixidityLib.unwrap(result);
    assert(r == a);
  }
}
