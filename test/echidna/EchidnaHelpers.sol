pragma solidity ^0.5.13;

contract EchidnaHelpers {
  /* ==================== Helper Functions ==================== */

  /**
   * @notice Checks if a given number falls within a specified range.
   * @param num The number to be checked.
   * @param lower The lower boundary of the range.
   * @param upper The upper boundary of the range.
   * @return The number if it falls within the range, the closest boundary otherwise.
   */
  function between(uint256 num, uint256 lower, uint256 upper) public pure returns (uint256) {
    num = lower + (num % (upper - lower));
    return num;
  }


  function areClose(uint256 num1, uint256 num2, uint256 precision) public view returns (bool) {
    if(num1 >= num2) {
      return num1 - num2 <= precision;
    } else {
      return num2 - num1 <= precision;
    }
  }
}
