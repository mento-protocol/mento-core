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
    if (num < lower) {
      return lower;
    } else if (num > upper) {
      return upper;
    } else {
      return num;
    }
  }
}
