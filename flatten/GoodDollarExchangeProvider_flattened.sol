// SPDX-License-Identifier: MIT
pragma solidity <0.8.19 <0.9 <0.9.0 =0.8.18 >0.5.13 >=0.5.13 >=0.5.17 >=0.8.13 ^0.8.0 ^0.8.1 ^0.8.2;
pragma experimental ABIEncoderV2;

// lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol

// OpenZeppelin Contracts (last updated v4.8.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}

// contracts/goodDollar/BancorFormula.sol

// solhint-disable function-max-lines, max-line-length, code-complexity, reason-string

/**
 * @title BancorFormula contract by Bancor
 * @dev https://github.com/bancorprotocol/contracts-solidity/blob/v0.6.39/solidity/contracts/converter/BancorFormula.sol
 *
 * Modified from the original by MentoLabs Team
 * - bumped solidity version to 0.8.18 and removed SafeMath
 * - removed unused functions and variables
 * - scaled max weight from 1e6 to 1e8 reran all const python scripts for increased precision
 * - added the saleCost() function that returns the amounIn of tokens required to receive a given amountOut of reserve tokens
 *
 */

contract BancorFormula {
  uint256 private constant ONE = 1;

  uint32 public constant MAX_WEIGHT = 100000000;
  uint8 private constant MIN_PRECISION = 32;
  uint8 private constant MAX_PRECISION = 127;

  // Auto-generated via 'PrintIntScalingFactors.py'
  uint256 private constant FIXED_1 = 0x080000000000000000000000000000000;
  uint256 private constant FIXED_2 = 0x100000000000000000000000000000000;
  uint256 private constant MAX_NUM = 0x200000000000000000000000000000000;

  // Auto-generated via 'PrintLn2ScalingFactors.py'
  uint256 private constant LN2_NUMERATOR = 0x3f80fe03f80fe03f80fe03f80fe03f8;
  uint256 private constant LN2_DENOMINATOR = 0x5b9de1d10bf4103d647b0955897ba80;

  // Auto-generated via 'PrintFunctionOptimalLog.py' and 'PrintFunctionOptimalExp.py'
  uint256 private constant OPT_LOG_MAX_VAL = 0x15bf0a8b1457695355fb8ac404e7a79e3;
  uint256 private constant OPT_EXP_MAX_VAL = 0x800000000000000000000000000000000;

  // Auto-generated via 'PrintMaxExpArray.py'
  uint256[128] private maxExpArray;

  function initMaxExpArray() private {
    //  maxExpArray[  0] = 0x6bffffffffffffffffffffffffffffffff;
    //  maxExpArray[  1] = 0x67ffffffffffffffffffffffffffffffff;
    //  maxExpArray[  2] = 0x637fffffffffffffffffffffffffffffff;
    //  maxExpArray[  3] = 0x5f6fffffffffffffffffffffffffffffff;
    //  maxExpArray[  4] = 0x5b77ffffffffffffffffffffffffffffff;
    //  maxExpArray[  5] = 0x57b3ffffffffffffffffffffffffffffff;
    //  maxExpArray[  6] = 0x5419ffffffffffffffffffffffffffffff;
    //  maxExpArray[  7] = 0x50a2ffffffffffffffffffffffffffffff;
    //  maxExpArray[  8] = 0x4d517fffffffffffffffffffffffffffff;
    //  maxExpArray[  9] = 0x4a233fffffffffffffffffffffffffffff;
    //  maxExpArray[ 10] = 0x47165fffffffffffffffffffffffffffff;
    //  maxExpArray[ 11] = 0x4429afffffffffffffffffffffffffffff;
    //  maxExpArray[ 12] = 0x415bc7ffffffffffffffffffffffffffff;
    //  maxExpArray[ 13] = 0x3eab73ffffffffffffffffffffffffffff;
    //  maxExpArray[ 14] = 0x3c1771ffffffffffffffffffffffffffff;
    //  maxExpArray[ 15] = 0x399e96ffffffffffffffffffffffffffff;
    //  maxExpArray[ 16] = 0x373fc47fffffffffffffffffffffffffff;
    //  maxExpArray[ 17] = 0x34f9e8ffffffffffffffffffffffffffff;
    //  maxExpArray[ 18] = 0x32cbfd5fffffffffffffffffffffffffff;
    //  maxExpArray[ 19] = 0x30b5057fffffffffffffffffffffffffff;
    //  maxExpArray[ 20] = 0x2eb40f9fffffffffffffffffffffffffff;
    //  maxExpArray[ 21] = 0x2cc8340fffffffffffffffffffffffffff;
    //  maxExpArray[ 22] = 0x2af09481ffffffffffffffffffffffffff;
    //  maxExpArray[ 23] = 0x292c5bddffffffffffffffffffffffffff;
    //  maxExpArray[ 24] = 0x277abdcdffffffffffffffffffffffffff;
    //  maxExpArray[ 25] = 0x25daf6657fffffffffffffffffffffffff;
    //  maxExpArray[ 26] = 0x244c49c65fffffffffffffffffffffffff;
    //  maxExpArray[ 27] = 0x22ce03cd5fffffffffffffffffffffffff;
    //  maxExpArray[ 28] = 0x215f77c047ffffffffffffffffffffffff;
    //  maxExpArray[ 29] = 0x1fffffffffffffffffffffffffffffffff;
    //  maxExpArray[ 30] = 0x1eaefdbdabffffffffffffffffffffffff;
    //  maxExpArray[ 31] = 0x1d6bd8b2ebffffffffffffffffffffffff;
    maxExpArray[32] = 0x1c35fedd14ffffffffffffffffffffffff;
    maxExpArray[33] = 0x1b0ce43b323fffffffffffffffffffffff;
    maxExpArray[34] = 0x19f0028ec1ffffffffffffffffffffffff;
    maxExpArray[35] = 0x18ded91f0e7fffffffffffffffffffffff;
    maxExpArray[36] = 0x17d8ec7f0417ffffffffffffffffffffff;
    maxExpArray[37] = 0x16ddc6556cdbffffffffffffffffffffff;
    maxExpArray[38] = 0x15ecf52776a1ffffffffffffffffffffff;
    maxExpArray[39] = 0x15060c256cb2ffffffffffffffffffffff;
    maxExpArray[40] = 0x1428a2f98d72ffffffffffffffffffffff;
    maxExpArray[41] = 0x13545598e5c23fffffffffffffffffffff;
    maxExpArray[42] = 0x1288c4161ce1dfffffffffffffffffffff;
    maxExpArray[43] = 0x11c592761c666fffffffffffffffffffff;
    maxExpArray[44] = 0x110a688680a757ffffffffffffffffffff;
    maxExpArray[45] = 0x1056f1b5bedf77ffffffffffffffffffff;
    maxExpArray[46] = 0x0faadceceeff8bffffffffffffffffffff;
    maxExpArray[47] = 0x0f05dc6b27edadffffffffffffffffffff;
    maxExpArray[48] = 0x0e67a5a25da4107fffffffffffffffffff;
    maxExpArray[49] = 0x0dcff115b14eedffffffffffffffffffff;
    maxExpArray[50] = 0x0d3e7a392431239fffffffffffffffffff;
    maxExpArray[51] = 0x0cb2ff529eb71e4fffffffffffffffffff;
    maxExpArray[52] = 0x0c2d415c3db974afffffffffffffffffff;
    maxExpArray[53] = 0x0bad03e7d883f69bffffffffffffffffff;
    maxExpArray[54] = 0x0b320d03b2c343d5ffffffffffffffffff;
    maxExpArray[55] = 0x0abc25204e02828dffffffffffffffffff;
    maxExpArray[56] = 0x0a4b16f74ee4bb207fffffffffffffffff;
    maxExpArray[57] = 0x09deaf736ac1f569ffffffffffffffffff;
    maxExpArray[58] = 0x0976bd9952c7aa957fffffffffffffffff;
    maxExpArray[59] = 0x09131271922eaa606fffffffffffffffff;
    maxExpArray[60] = 0x08b380f3558668c46fffffffffffffffff;
    maxExpArray[61] = 0x0857ddf0117efa215bffffffffffffffff;
    maxExpArray[62] = 0x07ffffffffffffffffffffffffffffffff;
    maxExpArray[63] = 0x07abbf6f6abb9d087fffffffffffffffff;
    maxExpArray[64] = 0x075af62cbac95f7dfa7fffffffffffffff;
    maxExpArray[65] = 0x070d7fb7452e187ac13fffffffffffffff;
    maxExpArray[66] = 0x06c3390ecc8af379295fffffffffffffff;
    maxExpArray[67] = 0x067c00a3b07ffc01fd6fffffffffffffff;
    maxExpArray[68] = 0x0637b647c39cbb9d3d27ffffffffffffff;
    maxExpArray[69] = 0x05f63b1fc104dbd39587ffffffffffffff;
    maxExpArray[70] = 0x05b771955b36e12f7235ffffffffffffff;
    maxExpArray[71] = 0x057b3d49dda84556d6f6ffffffffffffff;
    maxExpArray[72] = 0x054183095b2c8ececf30ffffffffffffff;
    maxExpArray[73] = 0x050a28be635ca2b888f77fffffffffffff;
    maxExpArray[74] = 0x04d5156639708c9db33c3fffffffffffff;
    maxExpArray[75] = 0x04a23105873875bd52dfdfffffffffffff;
    maxExpArray[76] = 0x0471649d87199aa990756fffffffffffff;
    maxExpArray[77] = 0x04429a21a029d4c1457cfbffffffffffff;
    maxExpArray[78] = 0x0415bc6d6fb7dd71af2cb3ffffffffffff;
    maxExpArray[79] = 0x03eab73b3bbfe282243ce1ffffffffffff;
    maxExpArray[80] = 0x03c1771ac9fb6b4c18e229ffffffffffff;
    maxExpArray[81] = 0x0399e96897690418f785257fffffffffff;
    maxExpArray[82] = 0x0373fc456c53bb779bf0ea9fffffffffff;
    maxExpArray[83] = 0x034f9e8e490c48e67e6ab8bfffffffffff;
    maxExpArray[84] = 0x032cbfd4a7adc790560b3337ffffffffff;
    maxExpArray[85] = 0x030b50570f6e5d2acca94613ffffffffff;
    maxExpArray[86] = 0x02eb40f9f620fda6b56c2861ffffffffff;
    maxExpArray[87] = 0x02cc8340ecb0d0f520a6af58ffffffffff;
    maxExpArray[88] = 0x02af09481380a0a35cf1ba02ffffffffff;
    maxExpArray[89] = 0x0292c5bdd3b92ec810287b1b3fffffffff;
    maxExpArray[90] = 0x0277abdcdab07d5a77ac6d6b9fffffffff;
    maxExpArray[91] = 0x025daf6654b1eaa55fd64df5efffffffff;
    maxExpArray[92] = 0x0244c49c648baa98192dce88b7ffffffff;
    maxExpArray[93] = 0x022ce03cd5619a311b2471268bffffffff;
    maxExpArray[94] = 0x0215f77c045fbe885654a44a0fffffffff;
    maxExpArray[95] = 0x01ffffffffffffffffffffffffffffffff;
    maxExpArray[96] = 0x01eaefdbdaaee7421fc4d3ede5ffffffff;
    maxExpArray[97] = 0x01d6bd8b2eb257df7e8ca57b09bfffffff;
    maxExpArray[98] = 0x01c35fedd14b861eb0443f7f133fffffff;
    maxExpArray[99] = 0x01b0ce43b322bcde4a56e8ada5afffffff;
    maxExpArray[100] = 0x019f0028ec1fff007f5a195a39dfffffff;
    maxExpArray[101] = 0x018ded91f0e72ee74f49b15ba527ffffff;
    maxExpArray[102] = 0x017d8ec7f04136f4e5615fd41a63ffffff;
    maxExpArray[103] = 0x016ddc6556cdb84bdc8d12d22e6fffffff;
    maxExpArray[104] = 0x015ecf52776a1155b5bd8395814f7fffff;
    maxExpArray[105] = 0x015060c256cb23b3b3cc3754cf40ffffff;
    maxExpArray[106] = 0x01428a2f98d728ae223ddab715be3fffff;
    maxExpArray[107] = 0x013545598e5c23276ccf0ede68034fffff;
    maxExpArray[108] = 0x01288c4161ce1d6f54b7f61081194fffff;
    maxExpArray[109] = 0x011c592761c666aa641d5a01a40f17ffff;
    maxExpArray[110] = 0x0110a688680a7530515f3e6e6cfdcdffff;
    maxExpArray[111] = 0x01056f1b5bedf75c6bcb2ce8aed428ffff;
    maxExpArray[112] = 0x00faadceceeff8a0890f3875f008277fff;
    maxExpArray[113] = 0x00f05dc6b27edad306388a600f6ba0bfff;
    maxExpArray[114] = 0x00e67a5a25da41063de1495d5b18cdbfff;
    maxExpArray[115] = 0x00dcff115b14eedde6fc3aa5353f2e4fff;
    maxExpArray[116] = 0x00d3e7a3924312399f9aae2e0f868f8fff;
    maxExpArray[117] = 0x00cb2ff529eb71e41582cccd5a1ee26fff;
    maxExpArray[118] = 0x00c2d415c3db974ab32a51840c0b67edff;
    maxExpArray[119] = 0x00bad03e7d883f69ad5b0a186184e06bff;
    maxExpArray[120] = 0x00b320d03b2c343d4829abd6075f0cc5ff;
    maxExpArray[121] = 0x00abc25204e02828d73c6e80bcdb1a95bf;
    maxExpArray[122] = 0x00a4b16f74ee4bb2040a1ec6c15fbbf2df;
    maxExpArray[123] = 0x009deaf736ac1f569deb1b5ae3f36c130f;
    maxExpArray[124] = 0x00976bd9952c7aa957f5937d790ef65037;
    maxExpArray[125] = 0x009131271922eaa6064b73a22d0bd4f2bf;
    maxExpArray[126] = 0x008b380f3558668c46c91c49a2f8e967b9;
    maxExpArray[127] = 0x00857ddf0117efa215952912839f6473e6;
  }

  /**
   * @dev should be executed after construction (too large for the constructor)
   */
  function init() public {
    initMaxExpArray();
  }

  /**
   * @dev given a token supply, reserve balance, weight and a deposit amount (in the reserve token),
   * calculates the target amount for a given conversion (in the main token)
   *
   * Formula:
   * return = _supply * ((1 + _amount / _reserveBalance) ^ (_reserveWeight / 1000000) - 1)
   *
   * @param _supply          liquid token supply
   * @param _reserveBalance  reserve balance
   * @param _reserveWeight   reserve weight, represented in ppm (1-1000000)
   * @param _amount          amount of reserve tokens to get the target amount for
   *
   * @return target
   */
  function purchaseTargetAmount(
    uint256 _supply,
    uint256 _reserveBalance,
    uint32 _reserveWeight,
    uint256 _amount
  ) internal view returns (uint256) {
    // validate input
    require(_supply > 0, "ERR_INVALID_SUPPLY");
    require(_reserveBalance > 0, "ERR_INVALID_RESERVE_BALANCE");
    require(_reserveWeight > 0 && _reserveWeight <= MAX_WEIGHT, "ERR_INVALID_RESERVE_WEIGHT");

    // special case for 0 deposit amount
    if (_amount == 0) return 0;

    // special case if the weight = 100%
    if (_reserveWeight == MAX_WEIGHT) return (_supply * _amount) / _reserveBalance;

    uint256 result;
    uint8 precision;
    uint256 baseN = _amount + _reserveBalance;
    (result, precision) = power(baseN, _reserveBalance, _reserveWeight, MAX_WEIGHT);
    uint256 temp = (_supply * result) >> precision;
    return temp - _supply;
  }

  /**
   * @dev given a token supply, reserve balance, weight and a sell amount (in the main token),
   * calculates the target amount for a given conversion (in the reserve token)
   *
   * Formula:
   * return = _reserveBalance * (1 - (1 - _amount / _supply) ^ (MAX_WEIGHT / _reserveWeight))
   *
   * @dev by MentoLabs: This function actually calculates a different formula that is equivalent to the one above.
   * But ensures the base of the power function is larger than 1, which is required by the power function.
   * The formula is:
   *                    = reserveBalance * ( -1 + (tokenSupply/(tokenSupply - amountIn ))^(MAX_WEIGHT/reserveRatio))
   * formula: amountOut = ----------------------------------------------------------------------------------
   *                    =          (tokenSupply/(tokenSupply - amountIn ))^(MAX_WEIGHT/reserveRatio)
   *
   *
   * @param _supply          liquid token supply
   * @param _reserveBalance  reserve balance
   * @param _reserveWeight   reserve weight, represented in ppm (1-1000000)
   * @param _amount          amount of liquid tokens to get the target amount for
   *
   * @return reserve token amount
   */
  function saleTargetAmount(
    uint256 _supply,
    uint256 _reserveBalance,
    uint32 _reserveWeight,
    uint256 _amount
  ) internal view returns (uint256) {
    // validate input
    require(_supply > 0, "ERR_INVALID_SUPPLY");
    require(_reserveBalance > 0, "ERR_INVALID_RESERVE_BALANCE");
    require(_reserveWeight > 0 && _reserveWeight <= MAX_WEIGHT, "ERR_INVALID_RESERVE_WEIGHT");
    require(_amount <= _supply, "ERR_INVALID_AMOUNT");

    // special case for 0 sell amount
    if (_amount == 0) return 0;

    // special case for selling the entire supply
    if (_amount == _supply) return _reserveBalance;

    // special case if the weight = 100%
    if (_reserveWeight == MAX_WEIGHT) return (_reserveBalance * _amount) / _supply;

    uint256 result;
    uint8 precision;
    uint256 baseD = _supply - _amount;
    (result, precision) = power(_supply, baseD, MAX_WEIGHT, _reserveWeight);
    uint256 temp1 = _reserveBalance * result;
    uint256 temp2 = _reserveBalance << precision;
    return (temp1 - temp2) / result;
  }

  /**
   * @dev given a pool token supply, reserve balance, reserve ratio and an amount of requested pool tokens,
   * calculates the amount of reserve tokens required for purchasing the given amount of pool tokens
   *
   * Formula:
   * return = _reserveBalance * (((_supply + _amount) / _supply) ^ (MAX_WEIGHT / _reserveRatio) - 1)
   *
   * @param _supply          pool token supply
   * @param _reserveBalance  reserve balance
   * @param _reserveRatio    reserve ratio, represented in ppm (2-2000000)
   * @param _amount          requested amount of pool tokens
   *
   * @return reserve token amount
   */
  function fundCost(
    uint256 _supply,
    uint256 _reserveBalance,
    uint32 _reserveRatio,
    uint256 _amount
  ) internal view returns (uint256) {
    // validate input
    require(_supply > 0, "ERR_INVALID_SUPPLY");
    require(_reserveBalance > 0, "ERR_INVALID_RESERVE_BALANCE");
    require(_reserveRatio > 1 && _reserveRatio <= MAX_WEIGHT * 2, "ERR_INVALID_RESERVE_RATIO");

    // special case for 0 amount
    if (_amount == 0) return 0;

    // special case if the reserve ratio = 100%
    if (_reserveRatio == MAX_WEIGHT) return (_amount * _reserveBalance - 1) / _supply + 1;

    uint256 result;
    uint8 precision;
    uint256 baseN = _supply + _amount;
    (result, precision) = power(baseN, _supply, MAX_WEIGHT, _reserveRatio);
    uint256 temp = ((_reserveBalance * result - 1) >> precision) + 1;
    return temp - _reserveBalance;
  }

  /**
   * Added by MentoLabs:
   * @notice This function calculates the amount of tokens required to purchase a given amount of reserve tokens.
   * @dev this formula was derived from the actual saleTargetAmount() function, and also ensures that the base of the power function is larger than 1.
   *
   *
   *                     =   tokenSupply * (-1 + (reserveBalance / (reserveBalance - amountOut)  )^(reserveRatio/MAX_WEIGHT) )
   * Formula: amountIn = ------------------------------------------------------------------------------------------------
   *                     =       (reserveBalance / (reserveBalance - amountOut)  )^(reserveRatio/MAX_WEIGHT)
   *
   *
   * @param _supply          pool token supply
   * @param _reserveBalance  reserve balance
   * @param _reserveWeight   reserve weight, represented in ppm
   * @param _amount          amount of reserve tokens to get the target amount for
   *
   * @return reserve token amount
   */
  function saleCost(
    uint256 _supply,
    uint256 _reserveBalance,
    uint32 _reserveWeight,
    uint256 _amount
  ) internal view returns (uint256) {
    // validate input
    require(_supply > 0, "ERR_INVALID_SUPPLY");
    require(_reserveBalance > 0, "ERR_INVALID_RESERVE_BALANCE");
    require(_reserveWeight > 0 && _reserveWeight <= MAX_WEIGHT, "ERR_INVALID_RESERVE_WEIGHT");

    require(_amount <= _reserveBalance, "ERR_INVALID_AMOUNT");

    // special case for 0 sell amount
    if (_amount == 0) return 0;

    // special case for selling the entire supply
    if (_amount == _reserveBalance) return _supply;

    // special case if the weight = 100%
    // base formula can be simplified to:
    // Formula: amountIn = amountOut * supply / reserveBalance
    // the +1 and -1 are to ensure that this function rounds up which is required to prevent protocol loss.
    if (_reserveWeight == MAX_WEIGHT) return (_supply * _amount - 1) / _reserveBalance + 1;

    uint256 result;
    uint8 precision;
    uint256 baseD = _reserveBalance - _amount;
    (result, precision) = power(_reserveBalance, baseD, _reserveWeight, MAX_WEIGHT);
    uint256 temp1 = _supply * result;
    uint256 temp2 = _supply << precision;
    return (temp1 - temp2 - 1) / result + 1;
  }

  /**
   * @dev General Description:
   *     Determine a value of precision.
   *     Calculate an integer approximation of (_baseN / _baseD) ^ (_expN / _expD) * 2 ^ precision.
   *     Return the result along with the precision used.
   *
   * Detailed Description:
   *     Instead of calculating "base ^ exp", we calculate "e ^ (log(base) * exp)".
   *     The value of "log(base)" is represented with an integer slightly smaller than "log(base) * 2 ^ precision".
   *     The larger "precision" is, the more accurately this value represents the real value.
   *     However, the larger "precision" is, the more bits are required in order to store this value.
   *     And the exponentiation function, which takes "x" and calculates "e ^ x", is limited to a maximum exponent (maximum value of "x").
   *     This maximum exponent depends on the "precision" used, and it is given by "maxExpArray[precision] >> (MAX_PRECISION - precision)".
   *     Hence we need to determine the highest precision which can be used for the given input, before calling the exponentiation function.
   *     This allows us to compute "base ^ exp" with maximum accuracy and without exceeding 256 bits in any of the intermediate computations.
   *     This functions assumes that "_expN < 2 ^ 256 / log(MAX_NUM - 1)", otherwise the multiplication should be replaced with a "safeMul".
   *     Since we rely on unsigned-integer arithmetic and "base < 1" ==> "log(base) < 0", this function does not support "_baseN < _baseD".
   */
  function power(uint256 _baseN, uint256 _baseD, uint32 _expN, uint32 _expD) internal view returns (uint256, uint8) {
    require(_baseN < MAX_NUM);

    uint256 baseLog;
    uint256 base = (_baseN * FIXED_1) / _baseD;
    if (base < OPT_LOG_MAX_VAL) {
      baseLog = optimalLog(base);
    } else {
      baseLog = generalLog(base);
    }

    uint256 baseLogTimesExp = (baseLog * _expN) / _expD;
    if (baseLogTimesExp < OPT_EXP_MAX_VAL) {
      return (optimalExp(baseLogTimesExp), MAX_PRECISION);
    } else {
      uint8 precision = findPositionInMaxExpArray(baseLogTimesExp);
      return (generalExp(baseLogTimesExp >> (MAX_PRECISION - precision), precision), precision);
    }
  }

  /**
   * @dev computes log(x / FIXED_1) * FIXED_1.
   * This functions assumes that "x >= FIXED_1", because the output would be negative otherwise.
   */
  function generalLog(uint256 x) internal pure returns (uint256) {
    uint256 res = 0;

    // If x >= 2, then we compute the integer part of log2(x), which is larger than 0.
    if (x >= FIXED_2) {
      uint8 count = floorLog2(x / FIXED_1);
      x >>= count; // now x < 2
      res = count * FIXED_1;
    }

    // If x > 1, then we compute the fraction part of log2(x), which is larger than 0.
    if (x > FIXED_1) {
      for (uint8 i = MAX_PRECISION; i > 0; --i) {
        x = (x * x) / FIXED_1; // now 1 < x < 4
        if (x >= FIXED_2) {
          x >>= 1; // now 1 < x < 2
          res += ONE << (i - 1);
        }
      }
    }

    return (res * LN2_NUMERATOR) / LN2_DENOMINATOR;
  }

  /**
   * @dev computes the largest integer smaller than or equal to the binary logarithm of the input.
   */
  function floorLog2(uint256 _n) internal pure returns (uint8) {
    uint8 res = 0;

    if (_n < 256) {
      // At most 8 iterations
      while (_n > 1) {
        _n >>= 1;
        res += 1;
      }
    } else {
      // Exactly 8 iterations
      for (uint8 s = 128; s > 0; s >>= 1) {
        if (_n >= (ONE << s)) {
          _n >>= s;
          res |= s;
        }
      }
    }

    return res;
  }

  /**
   * @dev the global "maxExpArray" is sorted in descending order, and therefore the following statements are equivalent:
   * - This function finds the position of [the smallest value in "maxExpArray" larger than or equal to "x"]
   * - This function finds the highest position of [a value in "maxExpArray" larger than or equal to "x"]
   */
  function findPositionInMaxExpArray(uint256 _x) internal view returns (uint8 position) {
    uint8 lo = MIN_PRECISION;
    uint8 hi = MAX_PRECISION;

    while (lo + 1 < hi) {
      uint8 mid = (lo + hi) / 2;
      if (maxExpArray[mid] >= _x) lo = mid;
      else hi = mid;
    }

    if (maxExpArray[hi] >= _x) return hi;
    if (maxExpArray[lo] >= _x) return lo;

    require(false);
  }

  /**
   * @dev this function can be auto-generated by the script 'PrintFunctionGeneralExp.py'.
   * it approximates "e ^ x" via maclaurin summation: "(x^0)/0! + (x^1)/1! + ... + (x^n)/n!".
   * it returns "e ^ (x / 2 ^ precision) * 2 ^ precision", that is, the result is upshifted for accuracy.
   * the global "maxExpArray" maps each "precision" to "((maximumExponent + 1) << (MAX_PRECISION - precision)) - 1".
   * the maximum permitted value for "x" is therefore given by "maxExpArray[precision] >> (MAX_PRECISION - precision)".
   */
  function generalExp(uint256 _x, uint8 _precision) internal pure returns (uint256) {
    uint256 xi = _x;
    uint256 res = 0;

    xi = (xi * _x) >> _precision;
    res += xi * 0x3442c4e6074a82f1797f72ac0000000; // add x^02 * (33! / 02!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x116b96f757c380fb287fd0e40000000; // add x^03 * (33! / 03!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x045ae5bdd5f0e03eca1ff4390000000; // add x^04 * (33! / 04!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x00defabf91302cd95b9ffda50000000; // add x^05 * (33! / 05!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x002529ca9832b22439efff9b8000000; // add x^06 * (33! / 06!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x00054f1cf12bd04e516b6da88000000; // add x^07 * (33! / 07!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000a9e39e257a09ca2d6db51000000; // add x^08 * (33! / 08!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x000012e066e7b839fa050c309000000; // add x^09 * (33! / 09!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x000001e33d7d926c329a1ad1a800000; // add x^10 * (33! / 10!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000002bee513bdb4a6b19b5f800000; // add x^11 * (33! / 11!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x00000003a9316fa79b88eccf2a00000; // add x^12 * (33! / 12!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000000048177ebe1fa812375200000; // add x^13 * (33! / 13!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000000005263fe90242dcbacf00000; // add x^14 * (33! / 14!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x000000000057e22099c030d94100000; // add x^15 * (33! / 15!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000000000057e22099c030d9410000; // add x^16 * (33! / 16!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x00000000000052b6b54569976310000; // add x^17 * (33! / 17!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x00000000000004985f67696bf748000; // add x^18 * (33! / 18!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x000000000000003dea12ea99e498000; // add x^19 * (33! / 19!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x00000000000000031880f2214b6e000; // add x^20 * (33! / 20!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x000000000000000025bcff56eb36000; // add x^21 * (33! / 21!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x000000000000000001b722e10ab1000; // add x^22 * (33! / 22!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000000000000000001317c70077000; // add x^23 * (33! / 23!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x00000000000000000000cba84aafa00; // add x^24 * (33! / 24!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x00000000000000000000082573a0a00; // add x^25 * (33! / 25!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x00000000000000000000005035ad900; // add x^26 * (33! / 26!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x000000000000000000000002f881b00; // add x^27 * (33! / 27!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000000000000000000000001b29340; // add x^28 * (33! / 28!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x00000000000000000000000000efc40; // add x^29 * (33! / 29!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000000000000000000000000007fe0; // add x^30 * (33! / 30!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000000000000000000000000000420; // add x^31 * (33! / 31!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000000000000000000000000000021; // add x^32 * (33! / 32!)
    xi = (xi * _x) >> _precision;
    res += xi * 0x0000000000000000000000000000001; // add x^33 * (33! / 33!)

    return res / 0x688589cc0e9505e2f2fee5580000000 + _x + (ONE << _precision); // divide by 33! and then add x^1 / 1! + x^0 / 0!
  }

  /**
   * @dev computes log(x / FIXED_1) * FIXED_1
   * Input range: FIXED_1 <= x <= OPT_LOG_MAX_VAL - 1
   * Auto-generated via 'PrintFunctionOptimalLog.py'
   * Detailed description:
   * - Rewrite the input as a product of natural exponents and a single residual r, such that 1 < r < 2
   * - The natural logarithm of each (pre-calculated) exponent is the degree of the exponent
   * - The natural logarithm of r is calculated via Taylor series for log(1 + x), where x = r - 1
   * - The natural logarithm of the input is calculated by summing up the intermediate results above
   * - For example: log(250) = log(e^4 * e^1 * e^0.5 * 1.021692859) = 4 + 1 + 0.5 + log(1 + 0.021692859)
   */
  // We're choosing to trust Bancor's audited Math
  // slither-disable-start divide-before-multiply
  function optimalLog(uint256 x) internal pure returns (uint256) {
    uint256 res = 0;

    // slither false positive, y is initialized as z = y = ...
    // slither-disable-next-line uninitialized-local
    uint256 y;
    uint256 z;
    uint256 w;

    if (x >= 0xd3094c70f034de4b96ff7d5b6f99fcd8) {
      res += 0x40000000000000000000000000000000;
      x = (x * FIXED_1) / 0xd3094c70f034de4b96ff7d5b6f99fcd8;
    } // add 1 / 2^1
    if (x >= 0xa45af1e1f40c333b3de1db4dd55f29a7) {
      res += 0x20000000000000000000000000000000;
      x = (x * FIXED_1) / 0xa45af1e1f40c333b3de1db4dd55f29a7;
    } // add 1 / 2^2
    if (x >= 0x910b022db7ae67ce76b441c27035c6a1) {
      res += 0x10000000000000000000000000000000;
      x = (x * FIXED_1) / 0x910b022db7ae67ce76b441c27035c6a1;
    } // add 1 / 2^3
    if (x >= 0x88415abbe9a76bead8d00cf112e4d4a8) {
      res += 0x08000000000000000000000000000000;
      x = (x * FIXED_1) / 0x88415abbe9a76bead8d00cf112e4d4a8;
    } // add 1 / 2^4
    if (x >= 0x84102b00893f64c705e841d5d4064bd3) {
      res += 0x04000000000000000000000000000000;
      x = (x * FIXED_1) / 0x84102b00893f64c705e841d5d4064bd3;
    } // add 1 / 2^5
    if (x >= 0x8204055aaef1c8bd5c3259f4822735a2) {
      res += 0x02000000000000000000000000000000;
      x = (x * FIXED_1) / 0x8204055aaef1c8bd5c3259f4822735a2;
    } // add 1 / 2^6
    if (x >= 0x810100ab00222d861931c15e39b44e99) {
      res += 0x01000000000000000000000000000000;
      x = (x * FIXED_1) / 0x810100ab00222d861931c15e39b44e99;
    } // add 1 / 2^7
    if (x >= 0x808040155aabbbe9451521693554f733) {
      res += 0x00800000000000000000000000000000;
      x = (x * FIXED_1) / 0x808040155aabbbe9451521693554f733;
    } // add 1 / 2^8

    z = y = x - FIXED_1;
    w = (y * y) / FIXED_1;
    res += (z * (0x100000000000000000000000000000000 - y)) / 0x100000000000000000000000000000000;
    z = (z * w) / FIXED_1; // add y^01 / 01 - y^02 / 02
    res += (z * (0x0aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa - y)) / 0x200000000000000000000000000000000;
    z = (z * w) / FIXED_1; // add y^03 / 03 - y^04 / 04
    res += (z * (0x099999999999999999999999999999999 - y)) / 0x300000000000000000000000000000000;
    z = (z * w) / FIXED_1; // add y^05 / 05 - y^06 / 06
    res += (z * (0x092492492492492492492492492492492 - y)) / 0x400000000000000000000000000000000;
    z = (z * w) / FIXED_1; // add y^07 / 07 - y^08 / 08
    res += (z * (0x08e38e38e38e38e38e38e38e38e38e38e - y)) / 0x500000000000000000000000000000000;
    z = (z * w) / FIXED_1; // add y^09 / 09 - y^10 / 10
    res += (z * (0x08ba2e8ba2e8ba2e8ba2e8ba2e8ba2e8b - y)) / 0x600000000000000000000000000000000;
    z = (z * w) / FIXED_1; // add y^11 / 11 - y^12 / 12
    res += (z * (0x089d89d89d89d89d89d89d89d89d89d89 - y)) / 0x700000000000000000000000000000000;
    z = (z * w) / FIXED_1; // add y^13 / 13 - y^14 / 14
    res += (z * (0x088888888888888888888888888888888 - y)) / 0x800000000000000000000000000000000; // add y^15 / 15 - y^16 / 16

    return res;
  }

  /**
   * @dev computes e ^ (x / FIXED_1) * FIXED_1
   * input range: 0 <= x <= OPT_EXP_MAX_VAL - 1
   * auto-generated via 'PrintFunctionOptimalExp.py'
   * Detailed description:
   * - Rewrite the input as a sum of binary exponents and a single residual r, as small as possible
   * - The exponentiation of each binary exponent is given (pre-calculated)
   * - The exponentiation of r is calculated via Taylor series for e^x, where x = r
   * - The exponentiation of the input is calculated by multiplying the intermediate results above
   * - For example: e^5.521692859 = e^(4 + 1 + 0.5 + 0.021692859) = e^4 * e^1 * e^0.5 * e^0.021692859
   */
  function optimalExp(uint256 x) internal pure returns (uint256) {
    uint256 res = 0;

    // slither false positive, y is initialized as z = y = ...
    // slither-disable-next-line uninitialized-local
    uint256 y;
    uint256 z;

    z = y = x % 0x10000000000000000000000000000000; // get the input modulo 2^(-3)
    z = (z * y) / FIXED_1;
    res += z * 0x10e1b3be415a0000; // add y^02 * (20! / 02!)
    z = (z * y) / FIXED_1;
    res += z * 0x05a0913f6b1e0000; // add y^03 * (20! / 03!)
    z = (z * y) / FIXED_1;
    res += z * 0x0168244fdac78000; // add y^04 * (20! / 04!)
    z = (z * y) / FIXED_1;
    res += z * 0x004807432bc18000; // add y^05 * (20! / 05!)
    z = (z * y) / FIXED_1;
    res += z * 0x000c0135dca04000; // add y^06 * (20! / 06!)
    z = (z * y) / FIXED_1;
    res += z * 0x0001b707b1cdc000; // add y^07 * (20! / 07!)
    z = (z * y) / FIXED_1;
    res += z * 0x000036e0f639b800; // add y^08 * (20! / 08!)
    z = (z * y) / FIXED_1;
    res += z * 0x00000618fee9f800; // add y^09 * (20! / 09!)
    z = (z * y) / FIXED_1;
    res += z * 0x0000009c197dcc00; // add y^10 * (20! / 10!)
    z = (z * y) / FIXED_1;
    res += z * 0x0000000e30dce400; // add y^11 * (20! / 11!)
    z = (z * y) / FIXED_1;
    res += z * 0x000000012ebd1300; // add y^12 * (20! / 12!)
    z = (z * y) / FIXED_1;
    res += z * 0x0000000017499f00; // add y^13 * (20! / 13!)
    z = (z * y) / FIXED_1;
    res += z * 0x0000000001a9d480; // add y^14 * (20! / 14!)
    z = (z * y) / FIXED_1;
    res += z * 0x00000000001c6380; // add y^15 * (20! / 15!)
    z = (z * y) / FIXED_1;
    res += z * 0x000000000001c638; // add y^16 * (20! / 16!)
    z = (z * y) / FIXED_1;
    res += z * 0x0000000000001ab8; // add y^17 * (20! / 17!)
    z = (z * y) / FIXED_1;
    res += z * 0x000000000000017c; // add y^18 * (20! / 18!)
    z = (z * y) / FIXED_1;
    res += z * 0x0000000000000014; // add y^19 * (20! / 19!)
    z = (z * y) / FIXED_1;
    res += z * 0x0000000000000001; // add y^20 * (20! / 20!)
    res = res / 0x21c3677c82b40000 + y + FIXED_1; // divide by 20! and then add y^1 / 1! + y^0 / 0!

    if ((x & 0x010000000000000000000000000000000) != 0)
      res = (res * 0x1c3d6a24ed82218787d624d3e5eba95f9) / 0x18ebef9eac820ae8682b9793ac6d1e776; // multiply by e^2^(-3)
    if ((x & 0x020000000000000000000000000000000) != 0)
      res = (res * 0x18ebef9eac820ae8682b9793ac6d1e778) / 0x1368b2fc6f9609fe7aceb46aa619baed4; // multiply by e^2^(-2)
    if ((x & 0x040000000000000000000000000000000) != 0)
      res = (res * 0x1368b2fc6f9609fe7aceb46aa619baed5) / 0x0bc5ab1b16779be3575bd8f0520a9f21f; // multiply by e^2^(-1)
    if ((x & 0x080000000000000000000000000000000) != 0)
      res = (res * 0x0bc5ab1b16779be3575bd8f0520a9f21e) / 0x0454aaa8efe072e7f6ddbab84b40a55c9; // multiply by e^2^(+0)
    if ((x & 0x100000000000000000000000000000000) != 0)
      res = (res * 0x0454aaa8efe072e7f6ddbab84b40a55c5) / 0x00960aadc109e7a3bf4578099615711ea; // multiply by e^2^(+1)
    if ((x & 0x200000000000000000000000000000000) != 0)
      res = (res * 0x00960aadc109e7a3bf4578099615711d7) / 0x0002bf84208204f5977f9a8cf01fdce3d; // multiply by e^2^(+2)
    if ((x & 0x400000000000000000000000000000000) != 0)
      res = (res * 0x0002bf84208204f5977f9a8cf01fdc307) / 0x0000003c6ab775dd0b95b4cbee7e65d11; // multiply by e^2^(+3)

    return res;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
// slither-disable-end divide-before-multiply

// lib/prb-math/src/Common.sol

/// Common mathematical functions used in both SD59x18 and UD60x18. Note that these global functions do not
/// always operate with SD59x18 and UD60x18 numbers.

/*//////////////////////////////////////////////////////////////////////////
                                CUSTOM ERRORS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Emitted when the ending result in the fixed-point version of `mulDiv` would overflow uint256.
error PRBMath_MulDiv18_Overflow(uint256 x, uint256 y);

/// @notice Emitted when the ending result in `mulDiv` would overflow uint256.
error PRBMath_MulDiv_Overflow(uint256 x, uint256 y, uint256 denominator);

/// @notice Emitted when attempting to run `mulDiv` with one of the inputs `type(int256).min`.
error PRBMath_MulDivSigned_InputTooSmall();

/// @notice Emitted when the ending result in the signed version of `mulDiv` would overflow int256.
error PRBMath_MulDivSigned_Overflow(int256 x, int256 y);

/*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
//////////////////////////////////////////////////////////////////////////*/

/// @dev The maximum value an uint128 number can have.
uint128 constant MAX_UINT128 = type(uint128).max;

/// @dev The maximum value an uint40 number can have.
uint40 constant MAX_UINT40 = type(uint40).max;

/// @dev How many trailing decimals can be represented.
uint256 constant UNIT_0 = 1e18;

/// @dev Largest power of two that is a divisor of `UNIT`.
uint256 constant UNIT_LPOTD = 262144;

/// @dev The `UNIT` number inverted mod 2^256.
uint256 constant UNIT_INVERSE = 78156646155174841979727994598816262306175212592076161876661_508869554232690281;

/*//////////////////////////////////////////////////////////////////////////
                                    FUNCTIONS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Finds the zero-based index of the first one in the binary representation of x.
/// @dev See the note on msb in the "Find First Set" Wikipedia article https://en.wikipedia.org/wiki/Find_first_set
///
/// Each of the steps in this implementation is equivalent to this high-level code:
///
/// ```solidity
/// if (x >= 2 ** 128) {
///     x >>= 128;
///     result += 128;
/// }
/// ```
///
/// Where 128 is swapped with each respective power of two factor. See the full high-level implementation here:
/// https://gist.github.com/PaulRBerg/f932f8693f2733e30c4d479e8e980948
///
/// A list of the Yul instructions used below:
/// - "gt" is "greater than"
/// - "or" is the OR bitwise operator
/// - "shl" is "shift left"
/// - "shr" is "shift right"
///
/// @param x The uint256 number for which to find the index of the most significant bit.
/// @return result The index of the most significant bit as an uint256.
function msb(uint256 x) pure returns (uint256 result) {
    // 2^128
    assembly ("memory-safe") {
        let factor := shl(7, gt(x, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^64
    assembly ("memory-safe") {
        let factor := shl(6, gt(x, 0xFFFFFFFFFFFFFFFF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^32
    assembly ("memory-safe") {
        let factor := shl(5, gt(x, 0xFFFFFFFF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^16
    assembly ("memory-safe") {
        let factor := shl(4, gt(x, 0xFFFF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^8
    assembly ("memory-safe") {
        let factor := shl(3, gt(x, 0xFF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^4
    assembly ("memory-safe") {
        let factor := shl(2, gt(x, 0xF))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^2
    assembly ("memory-safe") {
        let factor := shl(1, gt(x, 0x3))
        x := shr(factor, x)
        result := or(result, factor)
    }
    // 2^1
    // No need to shift x any more.
    assembly ("memory-safe") {
        let factor := gt(x, 0x1)
        result := or(result, factor)
    }
}

/// @notice Calculates floor(x*y÷denominator) with full precision.
///
/// @dev Credits to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv.
///
/// Requirements:
/// - The denominator cannot be zero.
/// - The result must fit within uint256.
///
/// Caveats:
/// - This function does not work with fixed-point numbers.
///
/// @param x The multiplicand as an uint256.
/// @param y The multiplier as an uint256.
/// @param denominator The divisor as an uint256.
/// @return result The result as an uint256.
function mulDiv(uint256 x, uint256 y, uint256 denominator) pure returns (uint256 result) {
    // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
    // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
    // variables such that product = prod1 * 2^256 + prod0.
    uint256 prod0; // Least significant 256 bits of the product
    uint256 prod1; // Most significant 256 bits of the product
    assembly ("memory-safe") {
        let mm := mulmod(x, y, not(0))
        prod0 := mul(x, y)
        prod1 := sub(sub(mm, prod0), lt(mm, prod0))
    }

    // Handle non-overflow cases, 256 by 256 division.
    if (prod1 == 0) {
        unchecked {
            return prod0 / denominator;
        }
    }

    // Make sure the result is less than 2^256. Also prevents denominator == 0.
    if (prod1 >= denominator) {
        revert PRBMath_MulDiv_Overflow(x, y, denominator);
    }

    ///////////////////////////////////////////////
    // 512 by 256 division.
    ///////////////////////////////////////////////

    // Make division exact by subtracting the remainder from [prod1 prod0].
    uint256 remainder;
    assembly ("memory-safe") {
        // Compute remainder using the mulmod Yul instruction.
        remainder := mulmod(x, y, denominator)

        // Subtract 256 bit number from 512 bit number.
        prod1 := sub(prod1, gt(remainder, prod0))
        prod0 := sub(prod0, remainder)
    }

    // Factor powers of two out of denominator and compute largest power of two divisor of denominator. Always >= 1.
    // See https://cs.stackexchange.com/q/138556/92363.
    unchecked {
        // Does not overflow because the denominator cannot be zero at this stage in the function.
        uint256 lpotdod = denominator & (~denominator + 1);
        assembly ("memory-safe") {
            // Divide denominator by lpotdod.
            denominator := div(denominator, lpotdod)

            // Divide [prod1 prod0] by lpotdod.
            prod0 := div(prod0, lpotdod)

            // Flip lpotdod such that it is 2^256 / lpotdod. If lpotdod is zero, then it becomes one.
            lpotdod := add(div(sub(0, lpotdod), lpotdod), 1)
        }

        // Shift in bits from prod1 into prod0.
        prod0 |= prod1 * lpotdod;

        // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
        // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
        // four bits. That is, denominator * inv = 1 mod 2^4.
        uint256 inverse = (3 * denominator) ^ 2;

        // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
        // in modular arithmetic, doubling the correct bits in each step.
        inverse *= 2 - denominator * inverse; // inverse mod 2^8
        inverse *= 2 - denominator * inverse; // inverse mod 2^16
        inverse *= 2 - denominator * inverse; // inverse mod 2^32
        inverse *= 2 - denominator * inverse; // inverse mod 2^64
        inverse *= 2 - denominator * inverse; // inverse mod 2^128
        inverse *= 2 - denominator * inverse; // inverse mod 2^256

        // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
        // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
        // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
        // is no longer required.
        result = prod0 * inverse;
    }
}

/// @notice Calculates floor(x*y÷1e18) with full precision.
///
/// @dev Variant of `mulDiv` with constant folding, i.e. in which the denominator is always 1e18. Before returning the
/// final result, we add 1 if `(x * y) % UNIT >= HALF_UNIT`. Without this adjustment, 6.6e-19 would be truncated to 0
/// instead of being rounded to 1e-18. See "Listing 6" and text above it at https://accu.org/index.php/journals/1717.
///
/// Requirements:
/// - The result must fit within uint256.
///
/// Caveats:
/// - The body is purposely left uncommented; to understand how this works, see the NatSpec comments in `mulDiv`.
/// - It is assumed that the result can never be `type(uint256).max` when x and y solve the following two equations:
///     1. x * y = type(uint256).max * UNIT
///     2. (x * y) % UNIT >= UNIT / 2
///
/// @param x The multiplicand as an unsigned 60.18-decimal fixed-point number.
/// @param y The multiplier as an unsigned 60.18-decimal fixed-point number.
/// @return result The result as an unsigned 60.18-decimal fixed-point number.
function mulDiv18(uint256 x, uint256 y) pure returns (uint256 result) {
    uint256 prod0;
    uint256 prod1;
    assembly ("memory-safe") {
        let mm := mulmod(x, y, not(0))
        prod0 := mul(x, y)
        prod1 := sub(sub(mm, prod0), lt(mm, prod0))
    }

    if (prod1 >= UNIT_0) {
        revert PRBMath_MulDiv18_Overflow(x, y);
    }

    uint256 remainder;
    assembly ("memory-safe") {
        remainder := mulmod(x, y, UNIT_0)
    }

    if (prod1 == 0) {
        unchecked {
            return prod0 / UNIT_0;
        }
    }

    assembly ("memory-safe") {
        result := mul(
            or(
                div(sub(prod0, remainder), UNIT_LPOTD),
                mul(sub(prod1, gt(remainder, prod0)), add(div(sub(0, UNIT_LPOTD), UNIT_LPOTD), 1))
            ),
            UNIT_INVERSE
        )
    }
}

/// @notice Calculates floor(x*y÷denominator) with full precision.
///
/// @dev An extension of `mulDiv` for signed numbers. Works by computing the signs and the absolute values separately.
///
/// Requirements:
/// - None of the inputs can be `type(int256).min`.
/// - The result must fit within int256.
///
/// @param x The multiplicand as an int256.
/// @param y The multiplier as an int256.
/// @param denominator The divisor as an int256.
/// @return result The result as an int256.
function mulDivSigned(int256 x, int256 y, int256 denominator) pure returns (int256 result) {
    if (x == type(int256).min || y == type(int256).min || denominator == type(int256).min) {
        revert PRBMath_MulDivSigned_InputTooSmall();
    }

    // Get hold of the absolute values of x, y and the denominator.
    uint256 absX;
    uint256 absY;
    uint256 absD;
    unchecked {
        absX = x < 0 ? uint256(-x) : uint256(x);
        absY = y < 0 ? uint256(-y) : uint256(y);
        absD = denominator < 0 ? uint256(-denominator) : uint256(denominator);
    }

    // Compute the absolute value of (x*y)÷denominator. The result must fit within int256.
    uint256 rAbs = mulDiv(absX, absY, absD);
    if (rAbs > uint256(type(int256).max)) {
        revert PRBMath_MulDivSigned_Overflow(x, y);
    }

    // Get the signs of x, y and the denominator.
    uint256 sx;
    uint256 sy;
    uint256 sd;
    assembly ("memory-safe") {
        // This works thanks to two's complement.
        // "sgt" stands for "signed greater than" and "sub(0,1)" is max uint256.
        sx := sgt(x, sub(0, 1))
        sy := sgt(y, sub(0, 1))
        sd := sgt(denominator, sub(0, 1))
    }

    // XOR over sx, sy and sd. What this does is to check whether there are 1 or 3 negative signs in the inputs.
    // If there are, the result should be negative. Otherwise, it should be positive.
    unchecked {
        result = sx ^ sy ^ sd == 0 ? -int256(rAbs) : int256(rAbs);
    }
}

/// @notice Calculates the binary exponent of x using the binary fraction method.
/// @dev Has to use 192.64-bit fixed-point numbers.
/// See https://ethereum.stackexchange.com/a/96594/24693.
/// @param x The exponent as an unsigned 192.64-bit fixed-point number.
/// @return result The result as an unsigned 60.18-decimal fixed-point number.
function prbExp2(uint256 x) pure returns (uint256 result) {
    unchecked {
        // Start from 0.5 in the 192.64-bit fixed-point format.
        result = 0x800000000000000000000000000000000000000000000000;

        // Multiply the result by root(2, 2^-i) when the bit at position i is 1. None of the intermediary results overflows
        // because the initial result is 2^191 and all magic factors are less than 2^65.
        if (x & 0xFF00000000000000 > 0) {
            if (x & 0x8000000000000000 > 0) {
                result = (result * 0x16A09E667F3BCC909) >> 64;
            }
            if (x & 0x4000000000000000 > 0) {
                result = (result * 0x1306FE0A31B7152DF) >> 64;
            }
            if (x & 0x2000000000000000 > 0) {
                result = (result * 0x1172B83C7D517ADCE) >> 64;
            }
            if (x & 0x1000000000000000 > 0) {
                result = (result * 0x10B5586CF9890F62A) >> 64;
            }
            if (x & 0x800000000000000 > 0) {
                result = (result * 0x1059B0D31585743AE) >> 64;
            }
            if (x & 0x400000000000000 > 0) {
                result = (result * 0x102C9A3E778060EE7) >> 64;
            }
            if (x & 0x200000000000000 > 0) {
                result = (result * 0x10163DA9FB33356D8) >> 64;
            }
            if (x & 0x100000000000000 > 0) {
                result = (result * 0x100B1AFA5ABCBED61) >> 64;
            }
        }

        if (x & 0xFF000000000000 > 0) {
            if (x & 0x80000000000000 > 0) {
                result = (result * 0x10058C86DA1C09EA2) >> 64;
            }
            if (x & 0x40000000000000 > 0) {
                result = (result * 0x1002C605E2E8CEC50) >> 64;
            }
            if (x & 0x20000000000000 > 0) {
                result = (result * 0x100162F3904051FA1) >> 64;
            }
            if (x & 0x10000000000000 > 0) {
                result = (result * 0x1000B175EFFDC76BA) >> 64;
            }
            if (x & 0x8000000000000 > 0) {
                result = (result * 0x100058BA01FB9F96D) >> 64;
            }
            if (x & 0x4000000000000 > 0) {
                result = (result * 0x10002C5CC37DA9492) >> 64;
            }
            if (x & 0x2000000000000 > 0) {
                result = (result * 0x1000162E525EE0547) >> 64;
            }
            if (x & 0x1000000000000 > 0) {
                result = (result * 0x10000B17255775C04) >> 64;
            }
        }

        if (x & 0xFF0000000000 > 0) {
            if (x & 0x800000000000 > 0) {
                result = (result * 0x1000058B91B5BC9AE) >> 64;
            }
            if (x & 0x400000000000 > 0) {
                result = (result * 0x100002C5C89D5EC6D) >> 64;
            }
            if (x & 0x200000000000 > 0) {
                result = (result * 0x10000162E43F4F831) >> 64;
            }
            if (x & 0x100000000000 > 0) {
                result = (result * 0x100000B1721BCFC9A) >> 64;
            }
            if (x & 0x80000000000 > 0) {
                result = (result * 0x10000058B90CF1E6E) >> 64;
            }
            if (x & 0x40000000000 > 0) {
                result = (result * 0x1000002C5C863B73F) >> 64;
            }
            if (x & 0x20000000000 > 0) {
                result = (result * 0x100000162E430E5A2) >> 64;
            }
            if (x & 0x10000000000 > 0) {
                result = (result * 0x1000000B172183551) >> 64;
            }
        }

        if (x & 0xFF00000000 > 0) {
            if (x & 0x8000000000 > 0) {
                result = (result * 0x100000058B90C0B49) >> 64;
            }
            if (x & 0x4000000000 > 0) {
                result = (result * 0x10000002C5C8601CC) >> 64;
            }
            if (x & 0x2000000000 > 0) {
                result = (result * 0x1000000162E42FFF0) >> 64;
            }
            if (x & 0x1000000000 > 0) {
                result = (result * 0x10000000B17217FBB) >> 64;
            }
            if (x & 0x800000000 > 0) {
                result = (result * 0x1000000058B90BFCE) >> 64;
            }
            if (x & 0x400000000 > 0) {
                result = (result * 0x100000002C5C85FE3) >> 64;
            }
            if (x & 0x200000000 > 0) {
                result = (result * 0x10000000162E42FF1) >> 64;
            }
            if (x & 0x100000000 > 0) {
                result = (result * 0x100000000B17217F8) >> 64;
            }
        }

        if (x & 0xFF00000000 > 0) {
            if (x & 0x80000000 > 0) {
                result = (result * 0x10000000058B90BFC) >> 64;
            }
            if (x & 0x40000000 > 0) {
                result = (result * 0x1000000002C5C85FE) >> 64;
            }
            if (x & 0x20000000 > 0) {
                result = (result * 0x100000000162E42FF) >> 64;
            }
            if (x & 0x10000000 > 0) {
                result = (result * 0x1000000000B17217F) >> 64;
            }
            if (x & 0x8000000 > 0) {
                result = (result * 0x100000000058B90C0) >> 64;
            }
            if (x & 0x4000000 > 0) {
                result = (result * 0x10000000002C5C860) >> 64;
            }
            if (x & 0x2000000 > 0) {
                result = (result * 0x1000000000162E430) >> 64;
            }
            if (x & 0x1000000 > 0) {
                result = (result * 0x10000000000B17218) >> 64;
            }
        }

        if (x & 0xFF0000 > 0) {
            if (x & 0x800000 > 0) {
                result = (result * 0x1000000000058B90C) >> 64;
            }
            if (x & 0x400000 > 0) {
                result = (result * 0x100000000002C5C86) >> 64;
            }
            if (x & 0x200000 > 0) {
                result = (result * 0x10000000000162E43) >> 64;
            }
            if (x & 0x100000 > 0) {
                result = (result * 0x100000000000B1721) >> 64;
            }
            if (x & 0x80000 > 0) {
                result = (result * 0x10000000000058B91) >> 64;
            }
            if (x & 0x40000 > 0) {
                result = (result * 0x1000000000002C5C8) >> 64;
            }
            if (x & 0x20000 > 0) {
                result = (result * 0x100000000000162E4) >> 64;
            }
            if (x & 0x10000 > 0) {
                result = (result * 0x1000000000000B172) >> 64;
            }
        }

        if (x & 0xFF00 > 0) {
            if (x & 0x8000 > 0) {
                result = (result * 0x100000000000058B9) >> 64;
            }
            if (x & 0x4000 > 0) {
                result = (result * 0x10000000000002C5D) >> 64;
            }
            if (x & 0x2000 > 0) {
                result = (result * 0x1000000000000162E) >> 64;
            }
            if (x & 0x1000 > 0) {
                result = (result * 0x10000000000000B17) >> 64;
            }
            if (x & 0x800 > 0) {
                result = (result * 0x1000000000000058C) >> 64;
            }
            if (x & 0x400 > 0) {
                result = (result * 0x100000000000002C6) >> 64;
            }
            if (x & 0x200 > 0) {
                result = (result * 0x10000000000000163) >> 64;
            }
            if (x & 0x100 > 0) {
                result = (result * 0x100000000000000B1) >> 64;
            }
        }

        if (x & 0xFF > 0) {
            if (x & 0x80 > 0) {
                result = (result * 0x10000000000000059) >> 64;
            }
            if (x & 0x40 > 0) {
                result = (result * 0x1000000000000002C) >> 64;
            }
            if (x & 0x20 > 0) {
                result = (result * 0x10000000000000016) >> 64;
            }
            if (x & 0x10 > 0) {
                result = (result * 0x1000000000000000B) >> 64;
            }
            if (x & 0x8 > 0) {
                result = (result * 0x10000000000000006) >> 64;
            }
            if (x & 0x4 > 0) {
                result = (result * 0x10000000000000003) >> 64;
            }
            if (x & 0x2 > 0) {
                result = (result * 0x10000000000000001) >> 64;
            }
            if (x & 0x1 > 0) {
                result = (result * 0x10000000000000001) >> 64;
            }
        }

        // We're doing two things at the same time:
        //
        //   1. Multiply the result by 2^n + 1, where "2^n" is the integer part and the one is added to account for
        //      the fact that we initially set the result to 0.5. This is accomplished by subtracting from 191
        //      rather than 192.
        //   2. Convert the result to the unsigned 60.18-decimal fixed-point format.
        //
        // This works because 2^(191-ip) = 2^ip / 2^191, where "ip" is the integer part "2^n".
        result *= UNIT_0;
        result >>= (191 - (x >> 64));
    }
}

/// @notice Calculates the square root of x, rounding down if x is not a perfect square.
/// @dev Uses the Babylonian method https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method.
/// Credits to OpenZeppelin for the explanations in code comments below.
///
/// Caveats:
/// - This function does not work with fixed-point numbers.
///
/// @param x The uint256 number for which to calculate the square root.
/// @return result The result as an uint256.
function prbSqrt(uint256 x) pure returns (uint256 result) {
    if (x == 0) {
        return 0;
    }

    // For our first guess, we get the biggest power of 2 which is smaller than the square root of x.
    //
    // We know that the "msb" (most significant bit) of x is a power of 2 such that we have:
    //
    // $$
    // msb(x) <= x <= 2*msb(x)$
    // $$
    //
    // We write $msb(x)$ as $2^k$ and we get:
    //
    // $$
    // k = log_2(x)
    // $$
    //
    // Thus we can write the initial inequality as:
    //
    // $$
    // 2^{log_2(x)} <= x <= 2*2^{log_2(x)+1} \\
    // sqrt(2^k) <= sqrt(x) < sqrt(2^{k+1}) \\
    // 2^{k/2} <= sqrt(x) < 2^{(k+1)/2} <= 2^{(k/2)+1}
    // $$
    //
    // Consequently, $2^{log_2(x) /2}` is a good first approximation of sqrt(x) with at least one correct bit.
    uint256 xAux = uint256(x);
    result = 1;
    if (xAux >= 2 ** 128) {
        xAux >>= 128;
        result <<= 64;
    }
    if (xAux >= 2 ** 64) {
        xAux >>= 64;
        result <<= 32;
    }
    if (xAux >= 2 ** 32) {
        xAux >>= 32;
        result <<= 16;
    }
    if (xAux >= 2 ** 16) {
        xAux >>= 16;
        result <<= 8;
    }
    if (xAux >= 2 ** 8) {
        xAux >>= 8;
        result <<= 4;
    }
    if (xAux >= 2 ** 4) {
        xAux >>= 4;
        result <<= 2;
    }
    if (xAux >= 2 ** 2) {
        result <<= 1;
    }

    // At this point, `result` is an estimation with at least one bit of precision. We know the true value has at
    // most 128 bits, since  it is the square root of a uint256. Newton's method converges quadratically (precision
    // doubles at every iteration). We thus need at most 7 iteration to turn our partial result with one bit of
    // precision into the expected uint128 result.
    unchecked {
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;

        // Round down the result in case x is not a perfect square.
        uint256 roundedDownResult = x / result;
        if (result >= roundedDownResult) {
            result = roundedDownResult;
        }
    }
}

// contracts/interfaces/IBancorExchangeProvider.sol

interface IBancorExchangeProvider {
  struct PoolExchange {
    address reserveAsset;
    address tokenAddress;
    uint256 tokenSupply;
    uint256 reserveBalance;
    uint32 reserveRatio;
    uint32 exitContribution;
  }

  /* ========================================== */
  /* ================= Events ================= */
  /* ========================================== */

  /**
   * @notice Emitted when the broker address is updated.
   * @param newBroker The address of the new broker.
   */
  event BrokerUpdated(address indexed newBroker);

  /**
   * @notice Emitted when the reserve contract is set.
   * @param newReserve The address of the new reserve.
   */
  event ReserveUpdated(address indexed newReserve);

  /**
   * @notice Emitted when a new pool has been created.
   * @param exchangeId The id of the new pool
   * @param reserveAsset The address of the reserve asset
   * @param tokenAddress The address of the token
   */
  event ExchangeCreated(bytes32 indexed exchangeId, address indexed reserveAsset, address indexed tokenAddress);

  /**
   * @notice Emitted when a pool has been destroyed.
   * @param exchangeId The id of the pool to destroy
   * @param reserveAsset The address of the reserve asset
   * @param tokenAddress The address of the token
   */
  event ExchangeDestroyed(bytes32 indexed exchangeId, address indexed reserveAsset, address indexed tokenAddress);

  /**
   * @notice Emitted when the exit contribution for a pool is set.
   * @param exchangeId The id of the pool
   * @param exitContribution The exit contribution
   */
  event ExitContributionSet(bytes32 indexed exchangeId, uint256 exitContribution);

  /* ======================================================== */
  /* ==================== View Functions ==================== */
  /* ======================================================== */

  /**
   * @notice Allows the contract to be upgradable via the proxy.
   * @param _broker The address of the broker contract.
   * @param _reserve The address of the reserve contract.
   */
  function initialize(address _broker, address _reserve) external;

  /**
   * @notice Retrieves the pool with the specified exchangeId.
   * @param exchangeId The ID of the pool to be retrieved.
   * @return exchange The pool with that ID.
   */
  function getPoolExchange(bytes32 exchangeId) external view returns (PoolExchange memory exchange);

  /**
   * @notice Gets all pool IDs.
   * @return exchangeIds List of the pool IDs.
   */
  function getExchangeIds() external view returns (bytes32[] memory exchangeIds);

  /**
   * @notice Gets the current price based of the Bancor formula
   * @param exchangeId The ID of the pool to get the price for
   * @return price The current continuous price of the pool
   */
  function currentPrice(bytes32 exchangeId) external view returns (uint256 price);

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */
  /**
   * @notice Sets the address of the broker contract.
   * @param _broker The new address of the broker contract.
   */
  function setBroker(address _broker) external;

  /**
   * @notice Sets the address of the reserve contract.
   * @param _reserve The new address of the reserve contract.
   */
  function setReserve(address _reserve) external;

  /**
   * @notice Sets the exit contribution for a given pool
   * @param exchangeId The ID of the pool
   * @param exitContribution The exit contribution to be set
   */
  function setExitContribution(bytes32 exchangeId, uint32 exitContribution) external;

  /**
   * @notice Creates a new pool with the given parameters.
   * @param exchange The pool to be created.
   * @return exchangeId The ID of the new pool.
   */
  function createExchange(PoolExchange calldata exchange) external returns (bytes32 exchangeId);

  /**
   * @notice Destroys a pool with the given parameters if it exists.
   * @param exchangeId The ID of the pool to be destroyed.
   * @param exchangeIdIndex The index of the pool in the exchangeIds array.
   * @return destroyed A boolean indicating whether or not the exchange was successfully destroyed.
   */
  function destroyExchange(bytes32 exchangeId, uint256 exchangeIdIndex) external returns (bool destroyed);
}

// contracts/interfaces/IERC20.sol

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see {ERC20Detailed}.
 */
interface IERC20 {
  /**
   * @dev Returns the name of the token.
   */
  function name() external view returns (string memory);

  /**
   * @dev Returns the symbol of the token.
   */
  function symbol() external view returns (string memory);

  /**
   * @dev Returns the decimals places of the token.
   */
  function decimals() external view returns (uint8);

  /**
   * @dev Returns the amount of tokens in existence.
   */
  function totalSupply() external view returns (uint256);

  /**
   * @dev Returns the amount of tokens owned by `account`.
   */
  function balanceOf(address account) external view returns (uint256);

  /**
   * @dev Moves `amount` tokens from the caller's account to `recipient`.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transfer(address recipient, uint256 amount) external returns (bool);

  /**
   * @dev Returns the remaining number of tokens that `spender` will be
   * allowed to spend on behalf of `owner` through {transferFrom}. This is
   * zero by default.
   *
   * This value changes when {approve} or {transferFrom} are called.
   */
  function allowance(address owner, address spender) external view returns (uint256);

  /**
   * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * IMPORTANT: Beware that changing an allowance with this method brings the risk
   * that someone may use both the old and the new allowance by unfortunate
   * transaction ordering. One possible solution to mitigate this race
   * condition is to first reduce the spender's allowance to 0 and set the
   * desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   *
   * Emits an {Approval} event.
   */
  function approve(address spender, uint256 amount) external returns (bool);

  /**
   * @dev Moves `amount` tokens from `sender` to `recipient` using the
   * allowance mechanism. `amount` is then deducted from the caller's
   * allowance.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

  /**
   * @dev Emitted when `value` tokens are moved from one account (`from`) to
   * another (`to`).
   *
   * Note that `value` may be zero.
   */
  event Transfer(address indexed from, address indexed to, uint256 value);

  /**
   * @dev Emitted when the allowance of a `spender` for an `owner` is set by
   * a call to {approve}. `value` is the new allowance.
   */
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

// contracts/interfaces/IExchangeProvider.sol

/**
 * @title ExchangeProvider interface
 * @notice The IExchangeProvider interface is the interface that the Broker uses
 * to communicate with different exchange manager implementations like the BiPoolManager
 */
interface IExchangeProvider {
  /**
   * @notice Exchange - a struct that's used only by UIs (frontends/CLIs)
   * in order to discover what asset swaps are possible within an
   * exchange provider.
   * It's up to the specific exchange provider to convert its internal
   * representation to this universal struct. This conversion should
   * only happen in view calls used for discovery.
   * @param exchangeId The ID of the exchange, used to initiate swaps or get quotes.
   * @param assets An array of addresses of ERC20 tokens that can be swapped.
   */
  struct Exchange {
    bytes32 exchangeId;
    address[] assets;
  }

  /**
   * @notice Get all exchanges supported by the ExchangeProvider.
   * @return exchanges An array of Exchange structs.
   */
  function getExchanges() external view returns (Exchange[] memory exchanges);

  /**
   * @notice Execute a token swap with fixed amountIn
   * @param exchangeId The id of the exchange to use
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param amountIn The amount of tokenIn to be sold
   * @return amountOut The amount of tokenOut to be bought
   */
  function swapIn(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external returns (uint256 amountOut);

  /**
   * @notice Execute a token swap with fixed amountOut
   * @param exchangeId The id of the exchange to use
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param amountOut The amount of tokenOut to be bought
   * @return amountIn The amount of tokenIn to be sold
   */
  function swapOut(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) external returns (uint256 amountIn);

  /**
   * @notice Calculate amountOut of tokenOut received for a given amountIn of tokenIn
   * @param exchangeId The id of the exchange to use
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param amountIn The amount of tokenIn to be sold
   * @return amountOut The amount of tokenOut to be bought
   */
  function getAmountOut(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view returns (uint256 amountOut);

  /**
   * @notice Calculate amountIn of tokenIn needed for a given amountOut of tokenOut
   * @param exchangeId The ID of the pool to use
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param amountOut The amount of tokenOut to be bought
   * @return amountIn The amount of tokenIn to be sold
   */
  function getAmountIn(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) external view returns (uint256 amountIn);
}

// contracts/interfaces/IGoodDollarExchangeProvider.sol

interface IGoodDollarExchangeProvider {
  /* ========================================== */
  /* ================= Events ================= */
  /* ========================================== */

  /**
   * @notice Emitted when the ExpansionController address is updated.
   * @param expansionController The address of the ExpansionController contract.
   */
  event ExpansionControllerUpdated(address indexed expansionController);

  /**
   * @notice Emitted when the GoodDollar DAO address is updated.
   * @param AVATAR The address of the GoodDollar DAO contract.
   */
  // solhint-disable-next-line var-name-mixedcase
  event AvatarUpdated(address indexed AVATAR);

  /**
   * @notice Emitted when the reserve ratio for a pool is updated.
   * @param exchangeId The id of the pool.
   * @param reserveRatio The new reserve ratio.
   */
  event ReserveRatioUpdated(bytes32 indexed exchangeId, uint32 reserveRatio);

  /* =========================================== */
  /* ================ Functions ================ */
  /* =========================================== */

  /**
   * @notice Initializes the contract with the given parameters.
   * @param _broker The address of the Broker contract.
   * @param _reserve The address of the Reserve contract.
   * @param _expansionController The address of the ExpansionController contract.
   * @param _avatar The address of the GoodDollar DAO contract.
   */
  function initialize(address _broker, address _reserve, address _expansionController, address _avatar) external;

  /**
   * @notice Sets the address of the GoodDollar DAO contract.
   * @param _avatar The address of the DAO contract.
   */
  function setAvatar(address _avatar) external;

  /**
   * @notice Sets the address of the Expansion Controller contract.
   * @param _expansionController The address of the Expansion Controller contract.
   */
  function setExpansionController(address _expansionController) external;

  /**
   * @notice Calculates the amount of G$ tokens to be minted as a result of the expansion.
   * @param exchangeId The ID of the pool to calculate the expansion for.
   * @param reserveRatioScalar Scaler for calculating the new reserve ratio.
   * @return amountToMint Amount of G$ tokens to be minted as a result of the expansion.
   */
  function mintFromExpansion(bytes32 exchangeId, uint256 reserveRatioScalar) external returns (uint256 amountToMint);

  /**
   * @notice Calculates the amount of G$ tokens to be minted as a result of the collected reserve interest.
   * @param exchangeId The ID of the pool the collected reserve interest is added to.
   * @param reserveInterest The amount of reserve asset tokens collected from interest.
   * @return amountToMint The amount of G$ tokens to be minted as a result of the collected reserve interest.
   */
  function mintFromInterest(bytes32 exchangeId, uint256 reserveInterest) external returns (uint256 amountToMint);

  /**
   * @notice Calculates the reserve ratio needed to mint the given G$ reward.
   * @param exchangeId The ID of the pool the G$ reward is minted from.
   * @param reward The amount of G$ tokens to be minted as a reward.
   * @param maxSlippagePercentage Maximum allowed percentage difference between new and old reserve ratio (0-1e8).
   */
  function updateRatioForReward(bytes32 exchangeId, uint256 reward, uint256 maxSlippagePercentage) external;

  /**
   * @notice Pauses the Exchange, disabling minting.
   */
  function pause() external;

  /**
   * @notice Unpauses the Exchange, enabling minting again.
   */
  function unpause() external;
}

// contracts/interfaces/IGoodDollarExpansionController.sol

interface IGoodDollarExpansionController {
  /**
   * @notice Struct holding the configuration for the expansion of an exchange.
   * @param expansionRate The rate of expansion in percentage with 1e18 being 100%.
   * @param expansionFrequency The frequency of expansion in seconds.
   * @param lastExpansion The timestamp of the last prior expansion.
   */
  struct ExchangeExpansionConfig {
    uint64 expansionRate;
    uint32 expansionFrequency;
    uint32 lastExpansion;
  }

  /* ------- Events ------- */

  /**
   * @notice Emitted when the GoodDollarExchangeProvider is updated.
   * @param exchangeProvider The address of the new GoodDollarExchangeProvider.
   */
  event GoodDollarExchangeProviderUpdated(address indexed exchangeProvider);

  /**
   * @notice Emitted when the distribution helper is updated.
   * @param distributionHelper The address of the new distribution helper.
   */
  event DistributionHelperUpdated(address indexed distributionHelper);

  /**
   * @notice Emitted when the Reserve address is updated.
   * @param reserve The address of the new Reserve.
   */
  event ReserveUpdated(address indexed reserve);

  /**
   * @notice Emitted when the GoodDollar DAO address is updated.
   * @param avatar The new address of the GoodDollar DAO.
   */
  event AvatarUpdated(address indexed avatar);

  /**
   * @notice Emitted when the expansion config is set for an pool.
   * @param exchangeId The ID of the pool.
   * @param expansionRate The rate of expansion.
   * @param expansionFrequency The frequency of expansion.
   */
  event ExpansionConfigSet(bytes32 indexed exchangeId, uint64 expansionRate, uint32 expansionFrequency);

  /**
   * @notice Emitted when a G$ reward is minted.
   * @param exchangeId The ID of the pool.
   * @param to The address of the recipient.
   * @param amount The amount of G$ tokens minted.
   */
  event RewardMinted(bytes32 indexed exchangeId, address indexed to, uint256 amount);

  /**
   * @notice Emitted when UBI is minted through collecting reserve interest.
   * @param exchangeId The ID of the pool.
   * @param amount The amount of G$ tokens minted.
   */
  event InterestUBIMinted(bytes32 indexed exchangeId, uint256 amount);

  /**
   * @notice Emitted when UBI is minted through expansion.
   * @param exchangeId The ID of the pool.
   * @param amount The amount of G$ tokens minted.
   */
  event ExpansionUBIMinted(bytes32 indexed exchangeId, uint256 amount);

  /* ------- Functions ------- */

  /**
   * @notice Initializes the contract with the given parameters.
   * @param _goodDollarExchangeProvider The address of the GoodDollarExchangeProvider contract.
   * @param _distributionHelper The address of the distribution helper contract.
   * @param _reserve The address of the Reserve contract.
   * @param _avatar The address of the GoodDollar DAO contract.
   */
  function initialize(
    address _goodDollarExchangeProvider,
    address _distributionHelper,
    address _reserve,
    address _avatar
  ) external;

  /**
   * @notice Returns the expansion config for the given exchange.
   * @param exchangeId The id of the exchange to get the expansion config for.
   * @return config The expansion config.
   */
  function getExpansionConfig(bytes32 exchangeId) external returns (ExchangeExpansionConfig memory);

  /**
   * @notice Sets the GoodDollarExchangeProvider address.
   * @param _goodDollarExchangeProvider The address of the GoodDollarExchangeProvider contract.
   */
  function setGoodDollarExchangeProvider(address _goodDollarExchangeProvider) external;

  /**
   * @notice Sets the distribution helper address.
   * @param _distributionHelper The address of the distribution helper contract.
   */
  function setDistributionHelper(address _distributionHelper) external;

  /**
   * @notice Sets the reserve address.
   * @param _reserve The address of the reserve contract.
   */
  function setReserve(address _reserve) external;

  /**
   * @notice Sets the AVATAR address.
   * @param _avatar The address of the AVATAR contract.
   */
  function setAvatar(address _avatar) external;

  /**
   * @notice Sets the expansion config for the given pool.
   * @param exchangeId The ID of the pool to set the expansion config for.
   * @param expansionRate The rate of expansion.
   * @param expansionFrequency The frequency of expansion.
   */
  function setExpansionConfig(bytes32 exchangeId, uint64 expansionRate, uint32 expansionFrequency) external;

  /**
   * @notice Mints UBI as G$ tokens for a given pool from collected reserve interest.
   * @param exchangeId The ID of the pool to mint UBI for.
   * @param reserveInterest The amount of reserve tokens collected from interest.
   * @return amountMinted The amount of G$ tokens minted.
   */
  function mintUBIFromInterest(bytes32 exchangeId, uint256 reserveInterest) external returns (uint256 amountMinted);

  /**
   * @notice Mints UBI as G$ tokens for a given pool by comparing the contract's reserve balance to the virtual balance.
   * @param exchangeId The ID of the pool to mint UBI for.
   * @return amountMinted The amount of G$ tokens minted.
   */
  function mintUBIFromReserveBalance(bytes32 exchangeId) external returns (uint256 amountMinted);

  /**
   * @notice Mints UBI as G$ tokens for a given pool by calculating the expansion rate.
   * @param exchangeId The ID of the pool to mint UBI for.
   * @return amountMinted The amount of G$ tokens minted.
   */
  function mintUBIFromExpansion(bytes32 exchangeId) external returns (uint256 amountMinted);

  /**
   * @notice Mints a reward of G$ tokens for a given pool. Defaults to no slippage protection.
   * @param exchangeId The ID of the pool to mint a G$ reward for.
   * @param to The address of the recipient.
   * @param amount The amount of G$ tokens to mint.
   */
  function mintRewardFromReserveRatio(bytes32 exchangeId, address to, uint256 amount) external;

  /**
   * @notice Mints a reward of G$ tokens for a given pool.
   * @param exchangeId The ID of the pool to mint a G$ reward for.
   * @param to The address of the recipient.
   * @param amount The amount of G$ tokens to mint.
   * @param maxSlippagePercentage Maximum allowed percentage difference between new and old reserve ratio (0-100).
   */
  function mintRewardFromReserveRatio(
    bytes32 exchangeId,
    address to,
    uint256 amount,
    uint256 maxSlippagePercentage
  ) external;
}

// contracts/interfaces/IReserve.sol

interface IReserve {
  function setTobinTaxStalenessThreshold(uint256) external;

  function addToken(address) external returns (bool);

  function removeToken(address, uint256) external returns (bool);

  function transferGold(address payable, uint256) external returns (bool);

  function transferExchangeGold(address payable, uint256) external returns (bool);

  function transferCollateralAsset(address collateralAsset, address payable to, uint256 value) external returns (bool);

  function getReserveGoldBalance() external view returns (uint256);

  function getUnfrozenReserveGoldBalance() external view returns (uint256);

  function getOrComputeTobinTax() external returns (uint256, uint256);

  function getTokens() external view returns (address[] memory);

  function getReserveRatio() external view returns (uint256);

  function addExchangeSpender(address) external;

  function removeExchangeSpender(address, uint256) external;

  function addSpender(address) external;

  function removeSpender(address) external;

  function isStableAsset(address) external view returns (bool);

  function isCollateralAsset(address) external view returns (bool);

  function getDailySpendingRatioForCollateralAsset(address collateralAsset) external view returns (uint256);

  function isExchangeSpender(address exchange) external view returns (bool);

  function addCollateralAsset(address asset) external returns (bool);

  function transferExchangeCollateralAsset(
    address collateralAsset,
    address payable to,
    uint256 value
  ) external returns (bool);

  function initialize(
    address registryAddress,
    uint256 _tobinTaxStalenessThreshold,
    uint256 _spendingRatioForCelo,
    uint256 _frozenGold,
    uint256 _frozenDays,
    bytes32[] calldata _assetAllocationSymbols,
    uint256[] calldata _assetAllocationWeights,
    uint256 _tobinTax,
    uint256 _tobinTaxReserveRatio,
    address[] calldata _collateralAssets,
    uint256[] calldata _collateralAssetDailySpendingRatios
  ) external;

  /// @notice IOwnable:
  function transferOwnership(address newOwner) external;

  function renounceOwnership() external;

  function owner() external view returns (address);

  /// @notice Getters:
  function registry() external view returns (address);

  function tobinTaxStalenessThreshold() external view returns (uint256);

  function tobinTax() external view returns (uint256);

  function tobinTaxReserveRatio() external view returns (uint256);

  function getDailySpendingRatio() external view returns (uint256);

  function checkIsCollateralAsset(address collateralAsset) external view returns (bool);

  function isToken(address) external view returns (bool);

  function getOtherReserveAddresses() external view returns (address[] memory);

  function getAssetAllocationSymbols() external view returns (bytes32[] memory);

  function getAssetAllocationWeights() external view returns (uint256[] memory);

  function collateralAssetSpendingLimit(address) external view returns (uint256);

  function getExchangeSpenders() external view returns (address[] memory);

  function getUnfrozenBalance() external view returns (uint256);

  function isOtherReserveAddress(address otherReserveAddress) external view returns (bool);

  function isSpender(address spender) external view returns (bool);

  /// @notice Setters:
  function setRegistry(address) external;

  function setTobinTax(uint256) external;

  function setTobinTaxReserveRatio(uint256) external;

  function setDailySpendingRatio(uint256 spendingRatio) external;

  function setDailySpendingRatioForCollateralAssets(
    address[] calldata _collateralAssets,
    uint256[] calldata collateralAssetDailySpendingRatios
  ) external;

  function setFrozenGold(uint256 frozenGold, uint256 frozenDays) external;

  function setAssetAllocations(bytes32[] calldata symbols, uint256[] calldata weights) external;

  function removeCollateralAsset(address collateralAsset, uint256 index) external returns (bool);

  function addOtherReserveAddress(address otherReserveAddress) external returns (bool);

  function removeOtherReserveAddress(address otherReserveAddress, uint256 index) external returns (bool);

  function collateralAssets(uint256 index) external view returns (address);

  function collateralAssetLastSpendingDay(address collateralAsset) external view returns (uint256);
}

// lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol

// OpenZeppelin Contracts (last updated v4.8.1) (proxy/utils/Initializable.sol)

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint8 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that functions marked with `initializer` can be nested in the context of a
     * constructor.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: setting the version to 255 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized < type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint8) {
        return _initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

// lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol

// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

// lib/openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol

// OpenZeppelin Contracts (last updated v4.7.0) (security/Pausable.sol)

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    function __Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal onlyInitializing {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

// lib/prb-math/src/sd1x18/Casting.sol

/// @notice Casts an SD1x18 number into SD59x18.
/// @dev There is no overflow check because the domain of SD1x18 is a subset of SD59x18.
function intoSD59x18_0(SD1x18 x) pure returns (SD59x18 result) {
    result = SD59x18.wrap(int256(SD1x18.unwrap(x)));
}

/// @notice Casts an SD1x18 number into UD2x18.
/// - x must be positive.
function intoUD2x18_0(SD1x18 x) pure returns (UD2x18 result) {
    int64 xInt = SD1x18.unwrap(x);
    if (xInt < 0) {
        revert PRBMath_SD1x18_ToUD2x18_Underflow(x);
    }
    result = UD2x18.wrap(uint64(xInt));
}

/// @notice Casts an SD1x18 number into UD60x18.
/// @dev Requirements:
/// - x must be positive.
function intoUD60x18_0(SD1x18 x) pure returns (UD60x18 result) {
    int64 xInt = SD1x18.unwrap(x);
    if (xInt < 0) {
        revert PRBMath_SD1x18_ToUD60x18_Underflow(x);
    }
    result = UD60x18.wrap(uint64(xInt));
}

/// @notice Casts an SD1x18 number into uint256.
/// @dev Requirements:
/// - x must be positive.
function intoUint256_0(SD1x18 x) pure returns (uint256 result) {
    int64 xInt = SD1x18.unwrap(x);
    if (xInt < 0) {
        revert PRBMath_SD1x18_ToUint256_Underflow(x);
    }
    result = uint256(uint64(xInt));
}

/// @notice Casts an SD1x18 number into uint128.
/// @dev Requirements:
/// - x must be positive.
function intoUint128_0(SD1x18 x) pure returns (uint128 result) {
    int64 xInt = SD1x18.unwrap(x);
    if (xInt < 0) {
        revert PRBMath_SD1x18_ToUint128_Underflow(x);
    }
    result = uint128(uint64(xInt));
}

/// @notice Casts an SD1x18 number into uint40.
/// @dev Requirements:
/// - x must be positive.
/// - x must be less than or equal to `MAX_UINT40`.
function intoUint40_0(SD1x18 x) pure returns (uint40 result) {
    int64 xInt = SD1x18.unwrap(x);
    if (xInt < 0) {
        revert PRBMath_SD1x18_ToUint40_Underflow(x);
    }
    if (xInt > int64(uint64(MAX_UINT40))) {
        revert PRBMath_SD1x18_ToUint40_Overflow(x);
    }
    result = uint40(uint64(xInt));
}

/// @notice Alias for the `wrap` function.
function sd1x18(int64 x) pure returns (SD1x18 result) {
    result = SD1x18.wrap(x);
}

/// @notice Unwraps an SD1x18 number into int64.
function unwrap_0(SD1x18 x) pure returns (int64 result) {
    result = SD1x18.unwrap(x);
}

/// @notice Wraps an int64 number into the SD1x18 value type.
function wrap_0(int64 x) pure returns (SD1x18 result) {
    result = SD1x18.wrap(x);
}

// lib/prb-math/src/sd59x18/Casting.sol

/// @notice Casts an SD59x18 number into int256.
/// @dev This is basically a functional alias for the `unwrap` function.
function intoInt256(SD59x18 x) pure returns (int256 result) {
    result = SD59x18.unwrap(x);
}

/// @notice Casts an SD59x18 number into SD1x18.
/// @dev Requirements:
/// - x must be greater than or equal to `uMIN_SD1x18`.
/// - x must be less than or equal to `uMAX_SD1x18`.
function intoSD1x18_0(SD59x18 x) pure returns (SD1x18 result) {
    int256 xInt = SD59x18.unwrap(x);
    if (xInt < uMIN_SD1x18) {
        revert PRBMath_SD59x18_IntoSD1x18_Underflow(x);
    }
    if (xInt > uMAX_SD1x18) {
        revert PRBMath_SD59x18_IntoSD1x18_Overflow(x);
    }
    result = SD1x18.wrap(int64(xInt));
}

/// @notice Casts an SD59x18 number into UD2x18.
/// @dev Requirements:
/// - x must be positive.
/// - x must be less than or equal to `uMAX_UD2x18`.
function intoUD2x18_1(SD59x18 x) pure returns (UD2x18 result) {
    int256 xInt = SD59x18.unwrap(x);
    if (xInt < 0) {
        revert PRBMath_SD59x18_IntoUD2x18_Underflow(x);
    }
    if (xInt > int256(uint256(uMAX_UD2x18))) {
        revert PRBMath_SD59x18_IntoUD2x18_Overflow(x);
    }
    result = UD2x18.wrap(uint64(uint256(xInt)));
}

/// @notice Casts an SD59x18 number into UD60x18.
/// @dev Requirements:
/// - x must be positive.
function intoUD60x18_1(SD59x18 x) pure returns (UD60x18 result) {
    int256 xInt = SD59x18.unwrap(x);
    if (xInt < 0) {
        revert PRBMath_SD59x18_IntoUD60x18_Underflow(x);
    }
    result = UD60x18.wrap(uint256(xInt));
}

/// @notice Casts an SD59x18 number into uint256.
/// @dev Requirements:
/// - x must be positive.
function intoUint256_1(SD59x18 x) pure returns (uint256 result) {
    int256 xInt = SD59x18.unwrap(x);
    if (xInt < 0) {
        revert PRBMath_SD59x18_IntoUint256_Underflow(x);
    }
    result = uint256(xInt);
}

/// @notice Casts an SD59x18 number into uint128.
/// @dev Requirements:
/// - x must be positive.
/// - x must be less than or equal to `uMAX_UINT128`.
function intoUint128_1(SD59x18 x) pure returns (uint128 result) {
    int256 xInt = SD59x18.unwrap(x);
    if (xInt < 0) {
        revert PRBMath_SD59x18_IntoUint128_Underflow(x);
    }
    if (xInt > int256(uint256(MAX_UINT128))) {
        revert PRBMath_SD59x18_IntoUint128_Overflow(x);
    }
    result = uint128(uint256(xInt));
}

/// @notice Casts an SD59x18 number into uint40.
/// @dev Requirements:
/// - x must be positive.
/// - x must be less than or equal to `MAX_UINT40`.
function intoUint40_1(SD59x18 x) pure returns (uint40 result) {
    int256 xInt = SD59x18.unwrap(x);
    if (xInt < 0) {
        revert PRBMath_SD59x18_IntoUint40_Underflow(x);
    }
    if (xInt > int256(uint256(MAX_UINT40))) {
        revert PRBMath_SD59x18_IntoUint40_Overflow(x);
    }
    result = uint40(uint256(xInt));
}

/// @notice Alias for the `wrap` function.
function sd59x18(int256 x) pure returns (SD59x18 result) {
    result = SD59x18.wrap(x);
}

/// @notice Unwraps an SD59x18 number into int256.
function unwrap_1(SD59x18 x) pure returns (int256 result) {
    result = SD59x18.unwrap(x);
}

/// @notice Wraps an int256 number into the SD59x18 value type.
function wrap_1(int256 x) pure returns (SD59x18 result) {
    result = SD59x18.wrap(x);
}

// lib/prb-math/src/ud2x18/Casting.sol

/// @notice Casts an UD2x18 number into SD1x18.
/// - x must be less than or equal to `uMAX_SD1x18`.
function intoSD1x18_1(UD2x18 x) pure returns (SD1x18 result) {
    uint64 xUint = UD2x18.unwrap(x);
    if (xUint > uint64(uMAX_SD1x18)) {
        revert PRBMath_UD2x18_IntoSD1x18_Overflow(x);
    }
    result = SD1x18.wrap(int64(xUint));
}

/// @notice Casts an UD2x18 number into SD59x18.
/// @dev There is no overflow check because the domain of UD2x18 is a subset of SD59x18.
function intoSD59x18_1(UD2x18 x) pure returns (SD59x18 result) {
    result = SD59x18.wrap(int256(uint256(UD2x18.unwrap(x))));
}

/// @notice Casts an UD2x18 number into UD60x18.
/// @dev There is no overflow check because the domain of UD2x18 is a subset of UD60x18.
function intoUD60x18_2(UD2x18 x) pure returns (UD60x18 result) {
    result = UD60x18.wrap(UD2x18.unwrap(x));
}

/// @notice Casts an UD2x18 number into uint128.
/// @dev There is no overflow check because the domain of UD2x18 is a subset of uint128.
function intoUint128_2(UD2x18 x) pure returns (uint128 result) {
    result = uint128(UD2x18.unwrap(x));
}

/// @notice Casts an UD2x18 number into uint256.
/// @dev There is no overflow check because the domain of UD2x18 is a subset of uint256.
function intoUint256_2(UD2x18 x) pure returns (uint256 result) {
    result = uint256(UD2x18.unwrap(x));
}

/// @notice Casts an UD2x18 number into uint40.
/// @dev Requirements:
/// - x must be less than or equal to `MAX_UINT40`.
function intoUint40_2(UD2x18 x) pure returns (uint40 result) {
    uint64 xUint = UD2x18.unwrap(x);
    if (xUint > uint64(MAX_UINT40)) {
        revert PRBMath_UD2x18_IntoUint40_Overflow(x);
    }
    result = uint40(xUint);
}

/// @notice Alias for the `wrap` function.
function ud2x18(uint64 x) pure returns (UD2x18 result) {
    result = UD2x18.wrap(x);
}

/// @notice Unwrap an UD2x18 number into uint64.
function unwrap_2(UD2x18 x) pure returns (uint64 result) {
    result = UD2x18.unwrap(x);
}

/// @notice Wraps an uint64 number into the UD2x18 value type.
function wrap_2(uint64 x) pure returns (UD2x18 result) {
    result = UD2x18.wrap(x);
}

// lib/prb-math/src/ud60x18/Casting.sol

/// @notice Casts an UD60x18 number into SD1x18.
/// @dev Requirements:
/// - x must be less than or equal to `uMAX_SD1x18`.
function intoSD1x18_2(UD60x18 x) pure returns (SD1x18 result) {
    uint256 xUint = UD60x18.unwrap(x);
    if (xUint > uint256(int256(uMAX_SD1x18))) {
        revert PRBMath_UD60x18_IntoSD1x18_Overflow(x);
    }
    result = SD1x18.wrap(int64(uint64(xUint)));
}

/// @notice Casts an UD60x18 number into UD2x18.
/// @dev Requirements:
/// - x must be less than or equal to `uMAX_UD2x18`.
function intoUD2x18_2(UD60x18 x) pure returns (UD2x18 result) {
    uint256 xUint = UD60x18.unwrap(x);
    if (xUint > uMAX_UD2x18) {
        revert PRBMath_UD60x18_IntoUD2x18_Overflow(x);
    }
    result = UD2x18.wrap(uint64(xUint));
}

/// @notice Casts an UD60x18 number into SD59x18.
/// @dev Requirements:
/// - x must be less than or equal to `uMAX_SD59x18`.
function intoSD59x18_2(UD60x18 x) pure returns (SD59x18 result) {
    uint256 xUint = UD60x18.unwrap(x);
    if (xUint > uint256(uMAX_SD59x18)) {
        revert PRBMath_UD60x18_IntoSD59x18_Overflow(x);
    }
    result = SD59x18.wrap(int256(xUint));
}

/// @notice Casts an UD60x18 number into uint128.
/// @dev This is basically a functional alias for the `unwrap` function.
function intoUint256_3(UD60x18 x) pure returns (uint256 result) {
    result = UD60x18.unwrap(x);
}

/// @notice Casts an UD60x18 number into uint128.
/// @dev Requirements:
/// - x must be less than or equal to `MAX_UINT128`.
function intoUint128_3(UD60x18 x) pure returns (uint128 result) {
    uint256 xUint = UD60x18.unwrap(x);
    if (xUint > MAX_UINT128) {
        revert PRBMath_UD60x18_IntoUint128_Overflow(x);
    }
    result = uint128(xUint);
}

/// @notice Casts an UD60x18 number into uint40.
/// @dev Requirements:
/// - x must be less than or equal to `MAX_UINT40`.
function intoUint40_3(UD60x18 x) pure returns (uint40 result) {
    uint256 xUint = UD60x18.unwrap(x);
    if (xUint > MAX_UINT40) {
        revert PRBMath_UD60x18_IntoUint40_Overflow(x);
    }
    result = uint40(xUint);
}

/// @notice Alias for the `wrap` function.
function ud(uint256 x) pure returns (UD60x18 result) {
    result = UD60x18.wrap(x);
}

/// @notice Alias for the `wrap` function.
function ud60x18(uint256 x) pure returns (UD60x18 result) {
    result = UD60x18.wrap(x);
}

/// @notice Unwraps an UD60x18 number into uint256.
function unwrap_3(UD60x18 x) pure returns (uint256 result) {
    result = UD60x18.unwrap(x);
}

/// @notice Wraps an uint256 number into the UD60x18 value type.
function wrap_3(uint256 x) pure returns (UD60x18 result) {
    result = UD60x18.wrap(x);
}

// lib/prb-math/src/sd1x18/Constants.sol

/// @dev Euler's number as an SD1x18 number.
SD1x18 constant E_0 = SD1x18.wrap(2_718281828459045235);

/// @dev The maximum value an SD1x18 number can have.
int64 constant uMAX_SD1x18 = 9_223372036854775807;
SD1x18 constant MAX_SD1x18 = SD1x18.wrap(uMAX_SD1x18);

/// @dev The maximum value an SD1x18 number can have.
int64 constant uMIN_SD1x18 = -9_223372036854775808;
SD1x18 constant MIN_SD1x18 = SD1x18.wrap(uMIN_SD1x18);

/// @dev PI as an SD1x18 number.
SD1x18 constant PI_0 = SD1x18.wrap(3_141592653589793238);

/// @dev The unit amount that implies how many trailing decimals can be represented.
SD1x18 constant UNIT_1 = SD1x18.wrap(1e18);
int256 constant uUNIT_0 = 1e18;

// lib/prb-math/src/sd59x18/Constants.sol

/// NOTICE: the "u" prefix stands for "unwrapped".

/// @dev Euler's number as an SD59x18 number.
SD59x18 constant E_1 = SD59x18.wrap(2_718281828459045235);

/// @dev Half the UNIT number.
int256 constant uHALF_UNIT_0 = 0.5e18;
SD59x18 constant HALF_UNIT_0 = SD59x18.wrap(uHALF_UNIT_0);

/// @dev log2(10) as an SD59x18 number.
int256 constant uLOG2_10_0 = 3_321928094887362347;
SD59x18 constant LOG2_10_0 = SD59x18.wrap(uLOG2_10_0);

/// @dev log2(e) as an SD59x18 number.
int256 constant uLOG2_E_0 = 1_442695040888963407;
SD59x18 constant LOG2_E_0 = SD59x18.wrap(uLOG2_E_0);

/// @dev The maximum value an SD59x18 number can have.
int256 constant uMAX_SD59x18 = 57896044618658097711785492504343953926634992332820282019728_792003956564819967;
SD59x18 constant MAX_SD59x18 = SD59x18.wrap(uMAX_SD59x18);

/// @dev The maximum whole value an SD59x18 number can have.
int256 constant uMAX_WHOLE_SD59x18 = 57896044618658097711785492504343953926634992332820282019728_000000000000000000;
SD59x18 constant MAX_WHOLE_SD59x18 = SD59x18.wrap(uMAX_WHOLE_SD59x18);

/// @dev The minimum value an SD59x18 number can have.
int256 constant uMIN_SD59x18 = -57896044618658097711785492504343953926634992332820282019728_792003956564819968;
SD59x18 constant MIN_SD59x18 = SD59x18.wrap(uMIN_SD59x18);

/// @dev The minimum whole value an SD59x18 number can have.
int256 constant uMIN_WHOLE_SD59x18 = -57896044618658097711785492504343953926634992332820282019728_000000000000000000;
SD59x18 constant MIN_WHOLE_SD59x18 = SD59x18.wrap(uMIN_WHOLE_SD59x18);

/// @dev PI as an SD59x18 number.
SD59x18 constant PI_1 = SD59x18.wrap(3_141592653589793238);

/// @dev The unit amount that implies how many trailing decimals can be represented.
int256 constant uUNIT_1 = 1e18;
SD59x18 constant UNIT_2 = SD59x18.wrap(1e18);

/// @dev Zero as an SD59x18 number.
SD59x18 constant ZERO_0 = SD59x18.wrap(0);

// lib/prb-math/src/ud2x18/Constants.sol

/// @dev Euler's number as an UD2x18 number.
UD2x18 constant E_2 = UD2x18.wrap(2_718281828459045235);

/// @dev The maximum value an UD2x18 number can have.
uint64 constant uMAX_UD2x18 = 18_446744073709551615;
UD2x18 constant MAX_UD2x18 = UD2x18.wrap(uMAX_UD2x18);

/// @dev PI as an UD2x18 number.
UD2x18 constant PI_2 = UD2x18.wrap(3_141592653589793238);

/// @dev The unit amount that implies how many trailing decimals can be represented.
uint256 constant uUNIT_2 = 1e18;
UD2x18 constant UNIT_3 = UD2x18.wrap(1e18);

// lib/prb-math/src/ud60x18/Constants.sol

/// @dev Euler's number as an UD60x18 number.
UD60x18 constant E_3 = UD60x18.wrap(2_718281828459045235);

/// @dev Half the UNIT number.
uint256 constant uHALF_UNIT_1 = 0.5e18;
UD60x18 constant HALF_UNIT_1 = UD60x18.wrap(uHALF_UNIT_1);

/// @dev log2(10) as an UD60x18 number.
uint256 constant uLOG2_10_1 = 3_321928094887362347;
UD60x18 constant LOG2_10_1 = UD60x18.wrap(uLOG2_10_1);

/// @dev log2(e) as an UD60x18 number.
uint256 constant uLOG2_E_1 = 1_442695040888963407;
UD60x18 constant LOG2_E_1 = UD60x18.wrap(uLOG2_E_1);

/// @dev The maximum value an UD60x18 number can have.
uint256 constant uMAX_UD60x18 = 115792089237316195423570985008687907853269984665640564039457_584007913129639935;
UD60x18 constant MAX_UD60x18 = UD60x18.wrap(uMAX_UD60x18);

/// @dev The maximum whole value an UD60x18 number can have.
uint256 constant uMAX_WHOLE_UD60x18 = 115792089237316195423570985008687907853269984665640564039457_000000000000000000;
UD60x18 constant MAX_WHOLE_UD60x18 = UD60x18.wrap(uMAX_WHOLE_UD60x18);

/// @dev PI as an UD60x18 number.
UD60x18 constant PI_3 = UD60x18.wrap(3_141592653589793238);

/// @dev The unit amount that implies how many trailing decimals can be represented.
uint256 constant uUNIT_3 = 1e18;
UD60x18 constant UNIT_4 = UD60x18.wrap(uUNIT_3);

/// @dev Zero as an UD60x18 number.
UD60x18 constant ZERO_1 = UD60x18.wrap(0);

// lib/prb-math/src/sd1x18/Errors.sol

/// @notice Emitted when trying to cast a SD1x18 number that doesn't fit in UD2x18.
error PRBMath_SD1x18_ToUD2x18_Underflow(SD1x18 x);

/// @notice Emitted when trying to cast a SD1x18 number that doesn't fit in UD60x18.
error PRBMath_SD1x18_ToUD60x18_Underflow(SD1x18 x);

/// @notice Emitted when trying to cast a SD1x18 number that doesn't fit in uint128.
error PRBMath_SD1x18_ToUint128_Underflow(SD1x18 x);

/// @notice Emitted when trying to cast a SD1x18 number that doesn't fit in uint256.
error PRBMath_SD1x18_ToUint256_Underflow(SD1x18 x);

/// @notice Emitted when trying to cast a SD1x18 number that doesn't fit in uint40.
error PRBMath_SD1x18_ToUint40_Overflow(SD1x18 x);

/// @notice Emitted when trying to cast a SD1x18 number that doesn't fit in uint40.
error PRBMath_SD1x18_ToUint40_Underflow(SD1x18 x);

// lib/prb-math/src/sd59x18/Errors.sol

/// @notice Emitted when taking the absolute value of `MIN_SD59x18`.
error PRBMath_SD59x18_Abs_MinSD59x18();

/// @notice Emitted when ceiling a number overflows SD59x18.
error PRBMath_SD59x18_Ceil_Overflow(SD59x18 x);

/// @notice Emitted when converting a basic integer to the fixed-point format overflows SD59x18.
error PRBMath_SD59x18_Convert_Overflow(int256 x);

/// @notice Emitted when converting a basic integer to the fixed-point format underflows SD59x18.
error PRBMath_SD59x18_Convert_Underflow(int256 x);

/// @notice Emitted when dividing two numbers and one of them is `MIN_SD59x18`.
error PRBMath_SD59x18_Div_InputTooSmall();

/// @notice Emitted when dividing two numbers and one of the intermediary unsigned results overflows SD59x18.
error PRBMath_SD59x18_Div_Overflow(SD59x18 x, SD59x18 y);

/// @notice Emitted when taking the natural exponent of a base greater than 133.084258667509499441.
error PRBMath_SD59x18_Exp_InputTooBig(SD59x18 x);

/// @notice Emitted when taking the binary exponent of a base greater than 192.
error PRBMath_SD59x18_Exp2_InputTooBig(SD59x18 x);

/// @notice Emitted when flooring a number underflows SD59x18.
error PRBMath_SD59x18_Floor_Underflow(SD59x18 x);

/// @notice Emitted when taking the geometric mean of two numbers and their product is negative.
error PRBMath_SD59x18_Gm_NegativeProduct(SD59x18 x, SD59x18 y);

/// @notice Emitted when taking the geometric mean of two numbers and multiplying them overflows SD59x18.
error PRBMath_SD59x18_Gm_Overflow(SD59x18 x, SD59x18 y);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in SD1x18.
error PRBMath_SD59x18_IntoSD1x18_Overflow(SD59x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in SD1x18.
error PRBMath_SD59x18_IntoSD1x18_Underflow(SD59x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in UD2x18.
error PRBMath_SD59x18_IntoUD2x18_Overflow(SD59x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in UD2x18.
error PRBMath_SD59x18_IntoUD2x18_Underflow(SD59x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in UD60x18.
error PRBMath_SD59x18_IntoUD60x18_Underflow(SD59x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in uint128.
error PRBMath_SD59x18_IntoUint128_Overflow(SD59x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in uint128.
error PRBMath_SD59x18_IntoUint128_Underflow(SD59x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in uint256.
error PRBMath_SD59x18_IntoUint256_Underflow(SD59x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in uint40.
error PRBMath_SD59x18_IntoUint40_Overflow(SD59x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in uint40.
error PRBMath_SD59x18_IntoUint40_Underflow(SD59x18 x);

/// @notice Emitted when taking the logarithm of a number less than or equal to zero.
error PRBMath_SD59x18_Log_InputTooSmall(SD59x18 x);

/// @notice Emitted when multiplying two numbers and one of the inputs is `MIN_SD59x18`.
error PRBMath_SD59x18_Mul_InputTooSmall();

/// @notice Emitted when multiplying two numbers and the intermediary absolute result overflows SD59x18.
error PRBMath_SD59x18_Mul_Overflow(SD59x18 x, SD59x18 y);

/// @notice Emitted when raising a number to a power and hte intermediary absolute result overflows SD59x18.
error PRBMath_SD59x18_Powu_Overflow(SD59x18 x, uint256 y);

/// @notice Emitted when taking the square root of a negative number.
error PRBMath_SD59x18_Sqrt_NegativeInput(SD59x18 x);

/// @notice Emitted when the calculating the square root overflows SD59x18.
error PRBMath_SD59x18_Sqrt_Overflow(SD59x18 x);

// lib/prb-math/src/ud2x18/Errors.sol

/// @notice Emitted when trying to cast a UD2x18 number that doesn't fit in SD1x18.
error PRBMath_UD2x18_IntoSD1x18_Overflow(UD2x18 x);

/// @notice Emitted when trying to cast a UD2x18 number that doesn't fit in uint40.
error PRBMath_UD2x18_IntoUint40_Overflow(UD2x18 x);

// lib/prb-math/src/ud60x18/Errors.sol

/// @notice Emitted when ceiling a number overflows UD60x18.
error PRBMath_UD60x18_Ceil_Overflow(UD60x18 x);

/// @notice Emitted when converting a basic integer to the fixed-point format overflows UD60x18.
error PRBMath_UD60x18_Convert_Overflow(uint256 x);

/// @notice Emitted when taking the natural exponent of a base greater than 133.084258667509499441.
error PRBMath_UD60x18_Exp_InputTooBig(UD60x18 x);

/// @notice Emitted when taking the binary exponent of a base greater than 192.
error PRBMath_UD60x18_Exp2_InputTooBig(UD60x18 x);

/// @notice Emitted when taking the geometric mean of two numbers and multiplying them overflows UD60x18.
error PRBMath_UD60x18_Gm_Overflow(UD60x18 x, UD60x18 y);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in SD1x18.
error PRBMath_UD60x18_IntoSD1x18_Overflow(UD60x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in SD59x18.
error PRBMath_UD60x18_IntoSD59x18_Overflow(UD60x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in UD2x18.
error PRBMath_UD60x18_IntoUD2x18_Overflow(UD60x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in uint128.
error PRBMath_UD60x18_IntoUint128_Overflow(UD60x18 x);

/// @notice Emitted when trying to cast an UD60x18 number that doesn't fit in uint40.
error PRBMath_UD60x18_IntoUint40_Overflow(UD60x18 x);

/// @notice Emitted when taking the logarithm of a number less than 1.
error PRBMath_UD60x18_Log_InputTooSmall(UD60x18 x);

/// @notice Emitted when calculating the square root overflows UD60x18.
error PRBMath_UD60x18_Sqrt_Overflow(UD60x18 x);

// lib/prb-math/src/sd59x18/Helpers.sol

/// @notice Implements the checked addition operation (+) in the SD59x18 type.
function add_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    return wrap_1(unwrap_1(x) + unwrap_1(y));
}

/// @notice Implements the AND (&) bitwise operation in the SD59x18 type.
function and_0(SD59x18 x, int256 bits) pure returns (SD59x18 result) {
    return wrap_1(unwrap_1(x) & bits);
}

/// @notice Implements the equal (=) operation in the SD59x18 type.
function eq_0(SD59x18 x, SD59x18 y) pure returns (bool result) {
    result = unwrap_1(x) == unwrap_1(y);
}

/// @notice Implements the greater than operation (>) in the SD59x18 type.
function gt_0(SD59x18 x, SD59x18 y) pure returns (bool result) {
    result = unwrap_1(x) > unwrap_1(y);
}

/// @notice Implements the greater than or equal to operation (>=) in the SD59x18 type.
function gte_0(SD59x18 x, SD59x18 y) pure returns (bool result) {
    result = unwrap_1(x) >= unwrap_1(y);
}

/// @notice Implements a zero comparison check function in the SD59x18 type.
function isZero_0(SD59x18 x) pure returns (bool result) {
    result = unwrap_1(x) == 0;
}

/// @notice Implements the left shift operation (<<) in the SD59x18 type.
function lshift_0(SD59x18 x, uint256 bits) pure returns (SD59x18 result) {
    result = wrap_1(unwrap_1(x) << bits);
}

/// @notice Implements the lower than operation (<) in the SD59x18 type.
function lt_0(SD59x18 x, SD59x18 y) pure returns (bool result) {
    result = unwrap_1(x) < unwrap_1(y);
}

/// @notice Implements the lower than or equal to operation (<=) in the SD59x18 type.
function lte_0(SD59x18 x, SD59x18 y) pure returns (bool result) {
    result = unwrap_1(x) <= unwrap_1(y);
}

/// @notice Implements the unchecked modulo operation (%) in the SD59x18 type.
function mod_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    result = wrap_1(unwrap_1(x) % unwrap_1(y));
}

/// @notice Implements the not equal operation (!=) in the SD59x18 type.
function neq_0(SD59x18 x, SD59x18 y) pure returns (bool result) {
    result = unwrap_1(x) != unwrap_1(y);
}

/// @notice Implements the OR (|) bitwise operation in the SD59x18 type.
function or_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    result = wrap_1(unwrap_1(x) | unwrap_1(y));
}

/// @notice Implements the right shift operation (>>) in the SD59x18 type.
function rshift_0(SD59x18 x, uint256 bits) pure returns (SD59x18 result) {
    result = wrap_1(unwrap_1(x) >> bits);
}

/// @notice Implements the checked subtraction operation (-) in the SD59x18 type.
function sub_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    result = wrap_1(unwrap_1(x) - unwrap_1(y));
}

/// @notice Implements the unchecked addition operation (+) in the SD59x18 type.
function uncheckedAdd_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    unchecked {
        result = wrap_1(unwrap_1(x) + unwrap_1(y));
    }
}

/// @notice Implements the unchecked subtraction operation (-) in the SD59x18 type.
function uncheckedSub_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    unchecked {
        result = wrap_1(unwrap_1(x) - unwrap_1(y));
    }
}

/// @notice Implements the unchecked unary minus operation (-) in the SD59x18 type.
function uncheckedUnary(SD59x18 x) pure returns (SD59x18 result) {
    unchecked {
        result = wrap_1(-unwrap_1(x));
    }
}

/// @notice Implements the XOR (^) bitwise operation in the SD59x18 type.
function xor_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    result = wrap_1(unwrap_1(x) ^ unwrap_1(y));
}

// lib/prb-math/src/ud60x18/Helpers.sol

/// @notice Implements the checked addition operation (+) in the UD60x18 type.
function add_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    result = wrap_3(unwrap_3(x) + unwrap_3(y));
}

/// @notice Implements the AND (&) bitwise operation in the UD60x18 type.
function and_1(UD60x18 x, uint256 bits) pure returns (UD60x18 result) {
    result = wrap_3(unwrap_3(x) & bits);
}

/// @notice Implements the equal operation (==) in the UD60x18 type.
function eq_1(UD60x18 x, UD60x18 y) pure returns (bool result) {
    result = unwrap_3(x) == unwrap_3(y);
}

/// @notice Implements the greater than operation (>) in the UD60x18 type.
function gt_1(UD60x18 x, UD60x18 y) pure returns (bool result) {
    result = unwrap_3(x) > unwrap_3(y);
}

/// @notice Implements the greater than or equal to operation (>=) in the UD60x18 type.
function gte_1(UD60x18 x, UD60x18 y) pure returns (bool result) {
    result = unwrap_3(x) >= unwrap_3(y);
}

/// @notice Implements a zero comparison check function in the UD60x18 type.
function isZero_1(UD60x18 x) pure returns (bool result) {
    // This wouldn't work if x could be negative.
    result = unwrap_3(x) == 0;
}

/// @notice Implements the left shift operation (<<) in the UD60x18 type.
function lshift_1(UD60x18 x, uint256 bits) pure returns (UD60x18 result) {
    result = wrap_3(unwrap_3(x) << bits);
}

/// @notice Implements the lower than operation (<) in the UD60x18 type.
function lt_1(UD60x18 x, UD60x18 y) pure returns (bool result) {
    result = unwrap_3(x) < unwrap_3(y);
}

/// @notice Implements the lower than or equal to operation (<=) in the UD60x18 type.
function lte_1(UD60x18 x, UD60x18 y) pure returns (bool result) {
    result = unwrap_3(x) <= unwrap_3(y);
}

/// @notice Implements the checked modulo operation (%) in the UD60x18 type.
function mod_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    result = wrap_3(unwrap_3(x) % unwrap_3(y));
}

/// @notice Implements the not equal operation (!=) in the UD60x18 type
function neq_1(UD60x18 x, UD60x18 y) pure returns (bool result) {
    result = unwrap_3(x) != unwrap_3(y);
}

/// @notice Implements the OR (|) bitwise operation in the UD60x18 type.
function or_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    result = wrap_3(unwrap_3(x) | unwrap_3(y));
}

/// @notice Implements the right shift operation (>>) in the UD60x18 type.
function rshift_1(UD60x18 x, uint256 bits) pure returns (UD60x18 result) {
    result = wrap_3(unwrap_3(x) >> bits);
}

/// @notice Implements the checked subtraction operation (-) in the UD60x18 type.
function sub_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    result = wrap_3(unwrap_3(x) - unwrap_3(y));
}

/// @notice Implements the unchecked addition operation (+) in the UD60x18 type.
function uncheckedAdd_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    unchecked {
        result = wrap_3(unwrap_3(x) + unwrap_3(y));
    }
}

/// @notice Implements the unchecked subtraction operation (-) in the UD60x18 type.
function uncheckedSub_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    unchecked {
        result = wrap_3(unwrap_3(x) - unwrap_3(y));
    }
}

/// @notice Implements the XOR (^) bitwise operation in the UD60x18 type.
function xor_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    result = wrap_3(unwrap_3(x) ^ unwrap_3(y));
}

// lib/prb-math/src/sd59x18/Math.sol

/// @notice Calculate the absolute value of x.
///
/// @dev Requirements:
/// - x must be greater than `MIN_SD59x18`.
///
/// @param x The SD59x18 number for which to calculate the absolute value.
/// @param result The absolute value of x as an SD59x18 number.
function abs(SD59x18 x) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    if (xInt == uMIN_SD59x18) {
        revert PRBMath_SD59x18_Abs_MinSD59x18();
    }
    result = xInt < 0 ? wrap_1(-xInt) : x;
}

/// @notice Calculates the arithmetic average of x and y, rounding towards zero.
/// @param x The first operand as an SD59x18 number.
/// @param y The second operand as an SD59x18 number.
/// @return result The arithmetic average as an SD59x18 number.
function avg_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    int256 yInt = unwrap_1(y);

    unchecked {
        // This is equivalent to "x / 2 +  y / 2" but faster.
        // This operation can never overflow.
        int256 sum = (xInt >> 1) + (yInt >> 1);

        if (sum < 0) {
            // If at least one of x and y is odd, we add 1 to the result, since shifting negative numbers to the right rounds
            // down to infinity. The right part is equivalent to "sum + (x % 2 == 1 || y % 2 == 1)" but faster.
            assembly ("memory-safe") {
                result := add(sum, and(or(xInt, yInt), 1))
            }
        } else {
            // We need to add 1 if both x and y are odd to account for the double 0.5 remainder that is truncated after shifting.
            result = wrap_1(sum + (xInt & yInt & 1));
        }
    }
}

/// @notice Yields the smallest whole SD59x18 number greater than or equal to x.
///
/// @dev Optimized for fractional value inputs, because for every whole value there are (1e18 - 1) fractional counterparts.
/// See https://en.wikipedia.org/wiki/Floor_and_ceiling_functions.
///
/// Requirements:
/// - x must be less than or equal to `MAX_WHOLE_SD59x18`.
///
/// @param x The SD59x18 number to ceil.
/// @param result The least number greater than or equal to x, as an SD59x18 number.
function ceil_0(SD59x18 x) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    if (xInt > uMAX_WHOLE_SD59x18) {
        revert PRBMath_SD59x18_Ceil_Overflow(x);
    }

    int256 remainder = xInt % uUNIT_1;
    if (remainder == 0) {
        result = x;
    } else {
        unchecked {
            // Solidity uses C fmod style, which returns a modulus with the same sign as x.
            int256 resultInt = xInt - remainder;
            if (xInt > 0) {
                resultInt += uUNIT_1;
            }
            result = wrap_1(resultInt);
        }
    }
}

/// @notice Divides two SD59x18 numbers, returning a new SD59x18 number. Rounds towards zero.
///
/// @dev This is a variant of `mulDiv` that works with signed numbers. Works by computing the signs and the absolute values
/// separately.
///
/// Requirements:
/// - All from `Common.mulDiv`.
/// - None of the inputs can be `MIN_SD59x18`.
/// - The denominator cannot be zero.
/// - The result must fit within int256.
///
/// Caveats:
/// - All from `Common.mulDiv`.
///
/// @param x The numerator as an SD59x18 number.
/// @param y The denominator as an SD59x18 number.
/// @param result The quotient as an SD59x18 number.
function div_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    int256 yInt = unwrap_1(y);
    if (xInt == uMIN_SD59x18 || yInt == uMIN_SD59x18) {
        revert PRBMath_SD59x18_Div_InputTooSmall();
    }

    // Get hold of the absolute values of x and y.
    uint256 xAbs;
    uint256 yAbs;
    unchecked {
        xAbs = xInt < 0 ? uint256(-xInt) : uint256(xInt);
        yAbs = yInt < 0 ? uint256(-yInt) : uint256(yInt);
    }

    // Compute the absolute value (x*UNIT)÷y. The resulting value must fit within int256.
    uint256 resultAbs = mulDiv(xAbs, uint256(uUNIT_1), yAbs);
    if (resultAbs > uint256(uMAX_SD59x18)) {
        revert PRBMath_SD59x18_Div_Overflow(x, y);
    }

    // Check if x and y have the same sign. This works thanks to two's complement; the left-most bit is the sign bit.
    bool sameSign = (xInt ^ yInt) > -1;

    // If the inputs don't have the same sign, the result should be negative. Otherwise, it should be positive.
    unchecked {
        result = wrap_1(sameSign ? int256(resultAbs) : -int256(resultAbs));
    }
}

/// @notice Calculates the natural exponent of x.
///
/// @dev Based on the formula:
///
/// $$
/// e^x = 2^{x * log_2{e}}
/// $$
///
/// Requirements:
/// - All from `log2`.
/// - x must be less than 133.084258667509499441.
///
/// Caveats:
/// - All from `exp2`.
/// - For any x less than -41.446531673892822322, the result is zero.
///
/// @param x The exponent as an SD59x18 number.
/// @return result The result as an SD59x18 number.
function exp_0(SD59x18 x) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    // Without this check, the value passed to `exp2` would be less than -59.794705707972522261.
    if (xInt < -41_446531673892822322) {
        return ZERO_0;
    }

    // Without this check, the value passed to `exp2` would be greater than 192.
    if (xInt >= 133_084258667509499441) {
        revert PRBMath_SD59x18_Exp_InputTooBig(x);
    }

    unchecked {
        // Do the fixed-point multiplication inline to save gas.
        int256 doubleUnitProduct = xInt * uLOG2_E_0;
        result = exp2_0(wrap_1(doubleUnitProduct / uUNIT_1));
    }
}

/// @notice Calculates the binary exponent of x using the binary fraction method.
///
/// @dev Based on the formula:
///
/// $$
/// 2^{-x} = \frac{1}{2^x}
/// $$
///
/// See https://ethereum.stackexchange.com/q/79903/24693.
///
/// Requirements:
/// - x must be 192 or less.
/// - The result must fit within `MAX_SD59x18`.
///
/// Caveats:
/// - For any x less than -59.794705707972522261, the result is zero.
///
/// @param x The exponent as an SD59x18 number.
/// @return result The result as an SD59x18 number.
function exp2_0(SD59x18 x) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    if (xInt < 0) {
        // 2^59.794705707972522262 is the maximum number whose inverse does not truncate down to zero.
        if (xInt < -59_794705707972522261) {
            return ZERO_0;
        }

        unchecked {
            // Do the fixed-point inversion $1/2^x$ inline to save gas. 1e36 is UNIT * UNIT.
            result = wrap_1(1e36 / unwrap_1(exp2_0(wrap_1(-xInt))));
        }
    } else {
        // 2^192 doesn't fit within the 192.64-bit format used internally in this function.
        if (xInt >= 192e18) {
            revert PRBMath_SD59x18_Exp2_InputTooBig(x);
        }

        unchecked {
            // Convert x to the 192.64-bit fixed-point format.
            uint256 x_192x64 = uint256((xInt << 64) / uUNIT_1);

            // It is safe to convert the result to int256 with no checks because the maximum input allowed in this function is 192.
            result = wrap_1(int256(prbExp2(x_192x64)));
        }
    }
}

/// @notice Yields the greatest whole SD59x18 number less than or equal to x.
///
/// @dev Optimized for fractional value inputs, because for every whole value there are (1e18 - 1) fractional counterparts.
/// See https://en.wikipedia.org/wiki/Floor_and_ceiling_functions.
///
/// Requirements:
/// - x must be greater than or equal to `MIN_WHOLE_SD59x18`.
///
/// @param x The SD59x18 number to floor.
/// @param result The greatest integer less than or equal to x, as an SD59x18 number.
function floor_0(SD59x18 x) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    if (xInt < uMIN_WHOLE_SD59x18) {
        revert PRBMath_SD59x18_Floor_Underflow(x);
    }

    int256 remainder = xInt % uUNIT_1;
    if (remainder == 0) {
        result = x;
    } else {
        unchecked {
            // Solidity uses C fmod style, which returns a modulus with the same sign as x.
            int256 resultInt = xInt - remainder;
            if (xInt < 0) {
                resultInt -= uUNIT_1;
            }
            result = wrap_1(resultInt);
        }
    }
}

/// @notice Yields the excess beyond the floor of x for positive numbers and the part of the number to the right.
/// of the radix point for negative numbers.
/// @dev Based on the odd function definition. https://en.wikipedia.org/wiki/Fractional_part
/// @param x The SD59x18 number to get the fractional part of.
/// @param result The fractional part of x as an SD59x18 number.
function frac_0(SD59x18 x) pure returns (SD59x18 result) {
    result = wrap_1(unwrap_1(x) % uUNIT_1);
}

/// @notice Calculates the geometric mean of x and y, i.e. sqrt(x * y), rounding down.
///
/// @dev Requirements:
/// - x * y must fit within `MAX_SD59x18`, lest it overflows.
/// - x * y must not be negative, since this library does not handle complex numbers.
///
/// @param x The first operand as an SD59x18 number.
/// @param y The second operand as an SD59x18 number.
/// @return result The result as an SD59x18 number.
function gm_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    int256 yInt = unwrap_1(y);
    if (xInt == 0 || yInt == 0) {
        return ZERO_0;
    }

    unchecked {
        // Equivalent to "xy / x != y". Checking for overflow this way is faster than letting Solidity do it.
        int256 xyInt = xInt * yInt;
        if (xyInt / xInt != yInt) {
            revert PRBMath_SD59x18_Gm_Overflow(x, y);
        }

        // The product must not be negative, since this library does not handle complex numbers.
        if (xyInt < 0) {
            revert PRBMath_SD59x18_Gm_NegativeProduct(x, y);
        }

        // We don't need to multiply the result by `UNIT` here because the x*y product had picked up a factor of `UNIT`
        // during multiplication. See the comments within the `prbSqrt` function.
        uint256 resultUint = prbSqrt(uint256(xyInt));
        result = wrap_1(int256(resultUint));
    }
}

/// @notice Calculates 1 / x, rounding toward zero.
///
/// @dev Requirements:
/// - x cannot be zero.
///
/// @param x The SD59x18 number for which to calculate the inverse.
/// @return result The inverse as an SD59x18 number.
function inv_0(SD59x18 x) pure returns (SD59x18 result) {
    // 1e36 is UNIT * UNIT.
    result = wrap_1(1e36 / unwrap_1(x));
}

/// @notice Calculates the natural logarithm of x.
///
/// @dev Based on the formula:
///
/// $$
/// ln{x} = log_2{x} / log_2{e}$$.
/// $$
///
/// Requirements:
/// - All from `log2`.
///
/// Caveats:
/// - All from `log2`.
/// - This doesn't return exactly 1 for 2.718281828459045235, for that more fine-grained precision is needed.
///
/// @param x The SD59x18 number for which to calculate the natural logarithm.
/// @return result The natural logarithm as an SD59x18 number.
function ln_0(SD59x18 x) pure returns (SD59x18 result) {
    // Do the fixed-point multiplication inline to save gas. This is overflow-safe because the maximum value that log2(x)
    // can return is 195.205294292027477728.
    result = wrap_1((unwrap_1(log2_0(x)) * uUNIT_1) / uLOG2_E_0);
}

/// @notice Calculates the common logarithm of x.
///
/// @dev First checks if x is an exact power of ten and it stops if yes. If it's not, calculates the common
/// logarithm based on the formula:
///
/// $$
/// log_{10}{x} = log_2{x} / log_2{10}
/// $$
///
/// Requirements:
/// - All from `log2`.
///
/// Caveats:
/// - All from `log2`.
///
/// @param x The SD59x18 number for which to calculate the common logarithm.
/// @return result The common logarithm as an SD59x18 number.
function log10_0(SD59x18 x) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    if (xInt < 0) {
        revert PRBMath_SD59x18_Log_InputTooSmall(x);
    }

    // Note that the `mul` in this block is the assembly mul operation, not the SD59x18 `mul`.
    // prettier-ignore
    assembly ("memory-safe") {
        switch x
        case 1 { result := mul(uUNIT_1, sub(0, 18)) }
        case 10 { result := mul(uUNIT_1, sub(1, 18)) }
        case 100 { result := mul(uUNIT_1, sub(2, 18)) }
        case 1000 { result := mul(uUNIT_1, sub(3, 18)) }
        case 10000 { result := mul(uUNIT_1, sub(4, 18)) }
        case 100000 { result := mul(uUNIT_1, sub(5, 18)) }
        case 1000000 { result := mul(uUNIT_1, sub(6, 18)) }
        case 10000000 { result := mul(uUNIT_1, sub(7, 18)) }
        case 100000000 { result := mul(uUNIT_1, sub(8, 18)) }
        case 1000000000 { result := mul(uUNIT_1, sub(9, 18)) }
        case 10000000000 { result := mul(uUNIT_1, sub(10, 18)) }
        case 100000000000 { result := mul(uUNIT_1, sub(11, 18)) }
        case 1000000000000 { result := mul(uUNIT_1, sub(12, 18)) }
        case 10000000000000 { result := mul(uUNIT_1, sub(13, 18)) }
        case 100000000000000 { result := mul(uUNIT_1, sub(14, 18)) }
        case 1000000000000000 { result := mul(uUNIT_1, sub(15, 18)) }
        case 10000000000000000 { result := mul(uUNIT_1, sub(16, 18)) }
        case 100000000000000000 { result := mul(uUNIT_1, sub(17, 18)) }
        case 1000000000000000000 { result := 0 }
        case 10000000000000000000 { result := uUNIT_1 }
        case 100000000000000000000 { result := mul(uUNIT_1, 2) }
        case 1000000000000000000000 { result := mul(uUNIT_1, 3) }
        case 10000000000000000000000 { result := mul(uUNIT_1, 4) }
        case 100000000000000000000000 { result := mul(uUNIT_1, 5) }
        case 1000000000000000000000000 { result := mul(uUNIT_1, 6) }
        case 10000000000000000000000000 { result := mul(uUNIT_1, 7) }
        case 100000000000000000000000000 { result := mul(uUNIT_1, 8) }
        case 1000000000000000000000000000 { result := mul(uUNIT_1, 9) }
        case 10000000000000000000000000000 { result := mul(uUNIT_1, 10) }
        case 100000000000000000000000000000 { result := mul(uUNIT_1, 11) }
        case 1000000000000000000000000000000 { result := mul(uUNIT_1, 12) }
        case 10000000000000000000000000000000 { result := mul(uUNIT_1, 13) }
        case 100000000000000000000000000000000 { result := mul(uUNIT_1, 14) }
        case 1000000000000000000000000000000000 { result := mul(uUNIT_1, 15) }
        case 10000000000000000000000000000000000 { result := mul(uUNIT_1, 16) }
        case 100000000000000000000000000000000000 { result := mul(uUNIT_1, 17) }
        case 1000000000000000000000000000000000000 { result := mul(uUNIT_1, 18) }
        case 10000000000000000000000000000000000000 { result := mul(uUNIT_1, 19) }
        case 100000000000000000000000000000000000000 { result := mul(uUNIT_1, 20) }
        case 1000000000000000000000000000000000000000 { result := mul(uUNIT_1, 21) }
        case 10000000000000000000000000000000000000000 { result := mul(uUNIT_1, 22) }
        case 100000000000000000000000000000000000000000 { result := mul(uUNIT_1, 23) }
        case 1000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 24) }
        case 10000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 25) }
        case 100000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 26) }
        case 1000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 27) }
        case 10000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 28) }
        case 100000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 29) }
        case 1000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 30) }
        case 10000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 31) }
        case 100000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 32) }
        case 1000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 33) }
        case 10000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 34) }
        case 100000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 35) }
        case 1000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 36) }
        case 10000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 37) }
        case 100000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 38) }
        case 1000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 39) }
        case 10000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 40) }
        case 100000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 41) }
        case 1000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 42) }
        case 10000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 43) }
        case 100000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 44) }
        case 1000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 45) }
        case 10000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 46) }
        case 100000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 47) }
        case 1000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 48) }
        case 10000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 49) }
        case 100000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 50) }
        case 1000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 51) }
        case 10000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 52) }
        case 100000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 53) }
        case 1000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 54) }
        case 10000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 55) }
        case 100000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 56) }
        case 1000000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 57) }
        case 10000000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_1, 58) }
        default {
            result := uMAX_SD59x18
        }
    }

    if (unwrap_1(result) == uMAX_SD59x18) {
        unchecked {
            // Do the fixed-point division inline to save gas.
            result = wrap_1((unwrap_1(log2_0(x)) * uUNIT_1) / uLOG2_10_0);
        }
    }
}

/// @notice Calculates the binary logarithm of x.
///
/// @dev Based on the iterative approximation algorithm.
/// https://en.wikipedia.org/wiki/Binary_logarithm#Iterative_approximation
///
/// Requirements:
/// - x must be greater than zero.
///
/// Caveats:
/// - The results are not perfectly accurate to the last decimal, due to the lossy precision of the iterative approximation.
///
/// @param x The SD59x18 number for which to calculate the binary logarithm.
/// @return result The binary logarithm as an SD59x18 number.
function log2_0(SD59x18 x) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    if (xInt <= 0) {
        revert PRBMath_SD59x18_Log_InputTooSmall(x);
    }

    unchecked {
        // This works because of:
        //
        // $$
        // log_2{x} = -log_2{\frac{1}{x}}
        // $$
        int256 sign;
        if (xInt >= uUNIT_1) {
            sign = 1;
        } else {
            sign = -1;
            // Do the fixed-point inversion inline to save gas. The numerator is UNIT * UNIT.
            xInt = 1e36 / xInt;
        }

        // Calculate the integer part of the logarithm and add it to the result and finally calculate $y = x * 2^(-n)$.
        uint256 n = msb(uint256(xInt / uUNIT_1));

        // This is the integer part of the logarithm as an SD59x18 number. The operation can't overflow
        // because n is maximum 255, UNIT is 1e18 and sign is either 1 or -1.
        int256 resultInt = int256(n) * uUNIT_1;

        // This is $y = x * 2^{-n}$.
        int256 y = xInt >> n;

        // If y is 1, the fractional part is zero.
        if (y == uUNIT_1) {
            return wrap_1(resultInt * sign);
        }

        // Calculate the fractional part via the iterative approximation.
        // The "delta >>= 1" part is equivalent to "delta /= 2", but shifting bits is faster.
        int256 DOUBLE_UNIT = 2e18;
        for (int256 delta = uHALF_UNIT_0; delta > 0; delta >>= 1) {
            y = (y * y) / uUNIT_1;

            // Is $y^2 > 2$ and so in the range [2,4)?
            if (y >= DOUBLE_UNIT) {
                // Add the 2^{-m} factor to the logarithm.
                resultInt = resultInt + delta;

                // Corresponds to z/2 on Wikipedia.
                y >>= 1;
            }
        }
        resultInt *= sign;
        result = wrap_1(resultInt);
    }
}

/// @notice Multiplies two SD59x18 numbers together, returning a new SD59x18 number.
///
/// @dev This is a variant of `mulDiv` that works with signed numbers and employs constant folding, i.e. the denominator
/// is always 1e18.
///
/// Requirements:
/// - All from `Common.mulDiv18`.
/// - None of the inputs can be `MIN_SD59x18`.
/// - The result must fit within `MAX_SD59x18`.
///
/// Caveats:
/// - To understand how this works in detail, see the NatSpec comments in `Common.mulDivSigned`.
///
/// @param x The multiplicand as an SD59x18 number.
/// @param y The multiplier as an SD59x18 number.
/// @return result The product as an SD59x18 number.
function mul_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    int256 yInt = unwrap_1(y);
    if (xInt == uMIN_SD59x18 || yInt == uMIN_SD59x18) {
        revert PRBMath_SD59x18_Mul_InputTooSmall();
    }

    // Get hold of the absolute values of x and y.
    uint256 xAbs;
    uint256 yAbs;
    unchecked {
        xAbs = xInt < 0 ? uint256(-xInt) : uint256(xInt);
        yAbs = yInt < 0 ? uint256(-yInt) : uint256(yInt);
    }

    uint256 resultAbs = mulDiv18(xAbs, yAbs);
    if (resultAbs > uint256(uMAX_SD59x18)) {
        revert PRBMath_SD59x18_Mul_Overflow(x, y);
    }

    // Check if x and y have the same sign. This works thanks to two's complement; the left-most bit is the sign bit.
    bool sameSign = (xInt ^ yInt) > -1;

    // If the inputs have the same sign, the result should be negative. Otherwise, it should be positive.
    unchecked {
        result = wrap_1(sameSign ? int256(resultAbs) : -int256(resultAbs));
    }
}

/// @notice Raises x to the power of y.
///
/// @dev Based on the formula:
///
/// $$
/// x^y = 2^{log_2{x} * y}
/// $$
///
/// Requirements:
/// - All from `exp2`, `log2` and `mul`.
/// - x cannot be zero.
///
/// Caveats:
/// - All from `exp2`, `log2` and `mul`.
/// - Assumes 0^0 is 1.
///
/// @param x Number to raise to given power y, as an SD59x18 number.
/// @param y Exponent to raise x to, as an SD59x18 number
/// @return result x raised to power y, as an SD59x18 number.
function pow_0(SD59x18 x, SD59x18 y) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    int256 yInt = unwrap_1(y);

    if (xInt == 0) {
        result = yInt == 0 ? UNIT_2 : ZERO_0;
    } else {
        if (yInt == uUNIT_1) {
            result = x;
        } else {
            result = exp2_0(mul_0(log2_0(x), y));
        }
    }
}

/// @notice Raises x (an SD59x18 number) to the power y (unsigned basic integer) using the famous algorithm
/// algorithm "exponentiation by squaring".
///
/// @dev See https://en.wikipedia.org/wiki/Exponentiation_by_squaring
///
/// Requirements:
/// - All from `abs` and `Common.mulDiv18`.
/// - The result must fit within `MAX_SD59x18`.
///
/// Caveats:
/// - All from `Common.mulDiv18`.
/// - Assumes 0^0 is 1.
///
/// @param x The base as an SD59x18 number.
/// @param y The exponent as an uint256.
/// @return result The result as an SD59x18 number.
function powu_0(SD59x18 x, uint256 y) pure returns (SD59x18 result) {
    uint256 xAbs = uint256(unwrap_1(abs(x)));

    // Calculate the first iteration of the loop in advance.
    uint256 resultAbs = y & 1 > 0 ? xAbs : uint256(uUNIT_1);

    // Equivalent to "for(y /= 2; y > 0; y /= 2)" but faster.
    uint256 yAux = y;
    for (yAux >>= 1; yAux > 0; yAux >>= 1) {
        xAbs = mulDiv18(xAbs, xAbs);

        // Equivalent to "y % 2 == 1" but faster.
        if (yAux & 1 > 0) {
            resultAbs = mulDiv18(resultAbs, xAbs);
        }
    }

    // The result must fit within `MAX_SD59x18`.
    if (resultAbs > uint256(uMAX_SD59x18)) {
        revert PRBMath_SD59x18_Powu_Overflow(x, y);
    }

    unchecked {
        // Is the base negative and the exponent an odd number?
        int256 resultInt = int256(resultAbs);
        bool isNegative = unwrap_1(x) < 0 && y & 1 == 1;
        if (isNegative) {
            resultInt = -resultInt;
        }
        result = wrap_1(resultInt);
    }
}

/// @notice Calculates the square root of x, rounding down. Only the positive root is returned.
/// @dev Uses the Babylonian method https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method.
///
/// Requirements:
/// - x cannot be negative, since this library does not handle complex numbers.
/// - x must be less than `MAX_SD59x18` divided by `UNIT`.
///
/// @param x The SD59x18 number for which to calculate the square root.
/// @return result The result as an SD59x18 number.
function sqrt_0(SD59x18 x) pure returns (SD59x18 result) {
    int256 xInt = unwrap_1(x);
    if (xInt < 0) {
        revert PRBMath_SD59x18_Sqrt_NegativeInput(x);
    }
    if (xInt > uMAX_SD59x18 / uUNIT_1) {
        revert PRBMath_SD59x18_Sqrt_Overflow(x);
    }

    unchecked {
        // Multiply x by `UNIT` to account for the factor of `UNIT` that is picked up when multiplying two SD59x18
        // numbers together (in this case, the two numbers are both the square root).
        uint256 resultUint = prbSqrt(uint256(xInt * uUNIT_1));
        result = wrap_1(int256(resultUint));
    }
}

// lib/prb-math/src/ud60x18/Math.sol

/*//////////////////////////////////////////////////////////////////////////
                            MATHEMATICAL FUNCTIONS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Calculates the arithmetic average of x and y, rounding down.
///
/// @dev Based on the formula:
///
/// $$
/// avg(x, y) = (x & y) + ((xUint ^ yUint) / 2)
/// $$
//
/// In English, what this formula does is:
///
/// 1. AND x and y.
/// 2. Calculate half of XOR x and y.
/// 3. Add the two results together.
///
/// This technique is known as SWAR, which stands for "SIMD within a register". You can read more about it here:
/// https://devblogs.microsoft.com/oldnewthing/20220207-00/?p=106223
///
/// @param x The first operand as an UD60x18 number.
/// @param y The second operand as an UD60x18 number.
/// @return result The arithmetic average as an UD60x18 number.
function avg_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    uint256 xUint = unwrap_3(x);
    uint256 yUint = unwrap_3(y);
    unchecked {
        result = wrap_3((xUint & yUint) + ((xUint ^ yUint) >> 1));
    }
}

/// @notice Yields the smallest whole UD60x18 number greater than or equal to x.
///
/// @dev This is optimized for fractional value inputs, because for every whole value there are "1e18 - 1" fractional
/// counterparts. See https://en.wikipedia.org/wiki/Floor_and_ceiling_functions.
///
/// Requirements:
/// - x must be less than or equal to `MAX_WHOLE_UD60x18`.
///
/// @param x The UD60x18 number to ceil.
/// @param result The least number greater than or equal to x, as an UD60x18 number.
function ceil_1(UD60x18 x) pure returns (UD60x18 result) {
    uint256 xUint = unwrap_3(x);
    if (xUint > uMAX_WHOLE_UD60x18) {
        revert PRBMath_UD60x18_Ceil_Overflow(x);
    }

    assembly ("memory-safe") {
        // Equivalent to "x % UNIT" but faster.
        let remainder := mod(x, uUNIT_3)

        // Equivalent to "UNIT - remainder" but faster.
        let delta := sub(uUNIT_3, remainder)

        // Equivalent to "x + delta * (remainder > 0 ? 1 : 0)" but faster.
        result := add(x, mul(delta, gt(remainder, 0)))
    }
}

/// @notice Divides two UD60x18 numbers, returning a new UD60x18 number. Rounds towards zero.
///
/// @dev Uses `mulDiv` to enable overflow-safe multiplication and division.
///
/// Requirements:
/// - The denominator cannot be zero.
///
/// @param x The numerator as an UD60x18 number.
/// @param y The denominator as an UD60x18 number.
/// @param result The quotient as an UD60x18 number.
function div_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    result = wrap_3(mulDiv(unwrap_3(x), uUNIT_3, unwrap_3(y)));
}

/// @notice Calculates the natural exponent of x.
///
/// @dev Based on the formula:
///
/// $$
/// e^x = 2^{x * log_2{e}}
/// $$
///
/// Requirements:
/// - All from `log2`.
/// - x must be less than 133.084258667509499441.
///
/// @param x The exponent as an UD60x18 number.
/// @return result The result as an UD60x18 number.
function exp_1(UD60x18 x) pure returns (UD60x18 result) {
    uint256 xUint = unwrap_3(x);

    // Without this check, the value passed to `exp2` would be greater than 192.
    if (xUint >= 133_084258667509499441) {
        revert PRBMath_UD60x18_Exp_InputTooBig(x);
    }

    unchecked {
        // We do the fixed-point multiplication inline rather than via the `mul` function to save gas.
        uint256 doubleUnitProduct = xUint * uLOG2_E_1;
        result = exp2_1(wrap_3(doubleUnitProduct / uUNIT_3));
    }
}

/// @notice Calculates the binary exponent of x using the binary fraction method.
///
/// @dev See https://ethereum.stackexchange.com/q/79903/24693.
///
/// Requirements:
/// - x must be 192 or less.
/// - The result must fit within `MAX_UD60x18`.
///
/// @param x The exponent as an UD60x18 number.
/// @return result The result as an UD60x18 number.
function exp2_1(UD60x18 x) pure returns (UD60x18 result) {
    uint256 xUint = unwrap_3(x);

    // Numbers greater than or equal to 2^192 don't fit within the 192.64-bit format.
    if (xUint >= 192e18) {
        revert PRBMath_UD60x18_Exp2_InputTooBig(x);
    }

    // Convert x to the 192.64-bit fixed-point format.
    uint256 x_192x64 = (xUint << 64) / uUNIT_3;

    // Pass x to the `prbExp2` function, which uses the 192.64-bit fixed-point number representation.
    result = wrap_3(prbExp2(x_192x64));
}

/// @notice Yields the greatest whole UD60x18 number less than or equal to x.
/// @dev Optimized for fractional value inputs, because for every whole value there are (1e18 - 1) fractional counterparts.
/// See https://en.wikipedia.org/wiki/Floor_and_ceiling_functions.
/// @param x The UD60x18 number to floor.
/// @param result The greatest integer less than or equal to x, as an UD60x18 number.
function floor_1(UD60x18 x) pure returns (UD60x18 result) {
    assembly ("memory-safe") {
        // Equivalent to "x % UNIT" but faster.
        let remainder := mod(x, uUNIT_3)

        // Equivalent to "x - remainder * (remainder > 0 ? 1 : 0)" but faster.
        result := sub(x, mul(remainder, gt(remainder, 0)))
    }
}

/// @notice Yields the excess beyond the floor of x.
/// @dev Based on the odd function definition https://en.wikipedia.org/wiki/Fractional_part.
/// @param x The UD60x18 number to get the fractional part of.
/// @param result The fractional part of x as an UD60x18 number.
function frac_1(UD60x18 x) pure returns (UD60x18 result) {
    assembly ("memory-safe") {
        result := mod(x, uUNIT_3)
    }
}

/// @notice Calculates the geometric mean of x and y, i.e. $$sqrt(x * y)$$, rounding down.
///
/// @dev Requirements:
/// - x * y must fit within `MAX_UD60x18`, lest it overflows.
///
/// @param x The first operand as an UD60x18 number.
/// @param y The second operand as an UD60x18 number.
/// @return result The result as an UD60x18 number.
function gm_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    uint256 xUint = unwrap_3(x);
    uint256 yUint = unwrap_3(y);
    if (xUint == 0 || yUint == 0) {
        return ZERO_1;
    }

    unchecked {
        // Checking for overflow this way is faster than letting Solidity do it.
        uint256 xyUint = xUint * yUint;
        if (xyUint / xUint != yUint) {
            revert PRBMath_UD60x18_Gm_Overflow(x, y);
        }

        // We don't need to multiply the result by `UNIT` here because the x*y product had picked up a factor of `UNIT`
        // during multiplication. See the comments in the `prbSqrt` function.
        result = wrap_3(prbSqrt(xyUint));
    }
}

/// @notice Calculates 1 / x, rounding toward zero.
///
/// @dev Requirements:
/// - x cannot be zero.
///
/// @param x The UD60x18 number for which to calculate the inverse.
/// @return result The inverse as an UD60x18 number.
function inv_1(UD60x18 x) pure returns (UD60x18 result) {
    unchecked {
        // 1e36 is UNIT * UNIT.
        result = wrap_3(1e36 / unwrap_3(x));
    }
}

/// @notice Calculates the natural logarithm of x.
///
/// @dev Based on the formula:
///
/// $$
/// ln{x} = log_2{x} / log_2{e}$$.
/// $$
///
/// Requirements:
/// - All from `log2`.
///
/// Caveats:
/// - All from `log2`.
/// - This doesn't return exactly 1 for 2.718281828459045235, for that more fine-grained precision is needed.
///
/// @param x The UD60x18 number for which to calculate the natural logarithm.
/// @return result The natural logarithm as an UD60x18 number.
function ln_1(UD60x18 x) pure returns (UD60x18 result) {
    unchecked {
        // We do the fixed-point multiplication inline to save gas. This is overflow-safe because the maximum value
        // that `log2` can return is 196.205294292027477728.
        result = wrap_3((unwrap_3(log2_1(x)) * uUNIT_3) / uLOG2_E_1);
    }
}

/// @notice Calculates the common logarithm of x.
///
/// @dev First checks if x is an exact power of ten and it stops if yes. If it's not, calculates the common
/// logarithm based on the formula:
///
/// $$
/// log_{10}{x} = log_2{x} / log_2{10}
/// $$
///
/// Requirements:
/// - All from `log2`.
///
/// Caveats:
/// - All from `log2`.
///
/// @param x The UD60x18 number for which to calculate the common logarithm.
/// @return result The common logarithm as an UD60x18 number.
function log10_1(UD60x18 x) pure returns (UD60x18 result) {
    uint256 xUint = unwrap_3(x);
    if (xUint < uUNIT_3) {
        revert PRBMath_UD60x18_Log_InputTooSmall(x);
    }

    // Note that the `mul` in this assembly block is the assembly multiplication operation, not the UD60x18 `mul`.
    // prettier-ignore
    assembly ("memory-safe") {
        switch x
        case 1 { result := mul(uUNIT_3, sub(0, 18)) }
        case 10 { result := mul(uUNIT_3, sub(1, 18)) }
        case 100 { result := mul(uUNIT_3, sub(2, 18)) }
        case 1000 { result := mul(uUNIT_3, sub(3, 18)) }
        case 10000 { result := mul(uUNIT_3, sub(4, 18)) }
        case 100000 { result := mul(uUNIT_3, sub(5, 18)) }
        case 1000000 { result := mul(uUNIT_3, sub(6, 18)) }
        case 10000000 { result := mul(uUNIT_3, sub(7, 18)) }
        case 100000000 { result := mul(uUNIT_3, sub(8, 18)) }
        case 1000000000 { result := mul(uUNIT_3, sub(9, 18)) }
        case 10000000000 { result := mul(uUNIT_3, sub(10, 18)) }
        case 100000000000 { result := mul(uUNIT_3, sub(11, 18)) }
        case 1000000000000 { result := mul(uUNIT_3, sub(12, 18)) }
        case 10000000000000 { result := mul(uUNIT_3, sub(13, 18)) }
        case 100000000000000 { result := mul(uUNIT_3, sub(14, 18)) }
        case 1000000000000000 { result := mul(uUNIT_3, sub(15, 18)) }
        case 10000000000000000 { result := mul(uUNIT_3, sub(16, 18)) }
        case 100000000000000000 { result := mul(uUNIT_3, sub(17, 18)) }
        case 1000000000000000000 { result := 0 }
        case 10000000000000000000 { result := uUNIT_3 }
        case 100000000000000000000 { result := mul(uUNIT_3, 2) }
        case 1000000000000000000000 { result := mul(uUNIT_3, 3) }
        case 10000000000000000000000 { result := mul(uUNIT_3, 4) }
        case 100000000000000000000000 { result := mul(uUNIT_3, 5) }
        case 1000000000000000000000000 { result := mul(uUNIT_3, 6) }
        case 10000000000000000000000000 { result := mul(uUNIT_3, 7) }
        case 100000000000000000000000000 { result := mul(uUNIT_3, 8) }
        case 1000000000000000000000000000 { result := mul(uUNIT_3, 9) }
        case 10000000000000000000000000000 { result := mul(uUNIT_3, 10) }
        case 100000000000000000000000000000 { result := mul(uUNIT_3, 11) }
        case 1000000000000000000000000000000 { result := mul(uUNIT_3, 12) }
        case 10000000000000000000000000000000 { result := mul(uUNIT_3, 13) }
        case 100000000000000000000000000000000 { result := mul(uUNIT_3, 14) }
        case 1000000000000000000000000000000000 { result := mul(uUNIT_3, 15) }
        case 10000000000000000000000000000000000 { result := mul(uUNIT_3, 16) }
        case 100000000000000000000000000000000000 { result := mul(uUNIT_3, 17) }
        case 1000000000000000000000000000000000000 { result := mul(uUNIT_3, 18) }
        case 10000000000000000000000000000000000000 { result := mul(uUNIT_3, 19) }
        case 100000000000000000000000000000000000000 { result := mul(uUNIT_3, 20) }
        case 1000000000000000000000000000000000000000 { result := mul(uUNIT_3, 21) }
        case 10000000000000000000000000000000000000000 { result := mul(uUNIT_3, 22) }
        case 100000000000000000000000000000000000000000 { result := mul(uUNIT_3, 23) }
        case 1000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 24) }
        case 10000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 25) }
        case 100000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 26) }
        case 1000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 27) }
        case 10000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 28) }
        case 100000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 29) }
        case 1000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 30) }
        case 10000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 31) }
        case 100000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 32) }
        case 1000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 33) }
        case 10000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 34) }
        case 100000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 35) }
        case 1000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 36) }
        case 10000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 37) }
        case 100000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 38) }
        case 1000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 39) }
        case 10000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 40) }
        case 100000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 41) }
        case 1000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 42) }
        case 10000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 43) }
        case 100000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 44) }
        case 1000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 45) }
        case 10000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 46) }
        case 100000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 47) }
        case 1000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 48) }
        case 10000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 49) }
        case 100000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 50) }
        case 1000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 51) }
        case 10000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 52) }
        case 100000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 53) }
        case 1000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 54) }
        case 10000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 55) }
        case 100000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 56) }
        case 1000000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 57) }
        case 10000000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 58) }
        case 100000000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(uUNIT_3, 59) }
        default {
            result := uMAX_UD60x18
        }
    }

    if (unwrap_3(result) == uMAX_UD60x18) {
        unchecked {
            // Do the fixed-point division inline to save gas.
            result = wrap_3((unwrap_3(log2_1(x)) * uUNIT_3) / uLOG2_10_1);
        }
    }
}

/// @notice Calculates the binary logarithm of x.
///
/// @dev Based on the iterative approximation algorithm.
/// https://en.wikipedia.org/wiki/Binary_logarithm#Iterative_approximation
///
/// Requirements:
/// - x must be greater than or equal to UNIT, otherwise the result would be negative.
///
/// Caveats:
/// - The results are nor perfectly accurate to the last decimal, due to the lossy precision of the iterative approximation.
///
/// @param x The UD60x18 number for which to calculate the binary logarithm.
/// @return result The binary logarithm as an UD60x18 number.
function log2_1(UD60x18 x) pure returns (UD60x18 result) {
    uint256 xUint = unwrap_3(x);

    if (xUint < uUNIT_3) {
        revert PRBMath_UD60x18_Log_InputTooSmall(x);
    }

    unchecked {
        // Calculate the integer part of the logarithm, add it to the result and finally calculate y = x * 2^(-n).
        uint256 n = msb(xUint / uUNIT_3);

        // This is the integer part of the logarithm as an UD60x18 number. The operation can't overflow because n
        // n is maximum 255 and UNIT is 1e18.
        uint256 resultUint = n * uUNIT_3;

        // This is $y = x * 2^{-n}$.
        uint256 y = xUint >> n;

        // If y is 1, the fractional part is zero.
        if (y == uUNIT_3) {
            return wrap_3(resultUint);
        }

        // Calculate the fractional part via the iterative approximation.
        // The "delta.rshift(1)" part is equivalent to "delta /= 2", but shifting bits is faster.
        uint256 DOUBLE_UNIT = 2e18;
        for (uint256 delta = uHALF_UNIT_1; delta > 0; delta >>= 1) {
            y = (y * y) / uUNIT_3;

            // Is y^2 > 2 and so in the range [2,4)?
            if (y >= DOUBLE_UNIT) {
                // Add the 2^{-m} factor to the logarithm.
                resultUint += delta;

                // Corresponds to z/2 on Wikipedia.
                y >>= 1;
            }
        }
        result = wrap_3(resultUint);
    }
}

/// @notice Multiplies two UD60x18 numbers together, returning a new UD60x18 number.
/// @dev See the documentation for the `Common.mulDiv18` function.
/// @param x The multiplicand as an UD60x18 number.
/// @param y The multiplier as an UD60x18 number.
/// @return result The product as an UD60x18 number.
function mul_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    result = wrap_3(mulDiv18(unwrap_3(x), unwrap_3(y)));
}

/// @notice Raises x to the power of y.
///
/// @dev Based on the formula:
///
/// $$
/// x^y = 2^{log_2{x} * y}
/// $$
///
/// Requirements:
/// - All from `exp2`, `log2` and `mul`.
///
/// Caveats:
/// - All from `exp2`, `log2` and `mul`.
/// - Assumes 0^0 is 1.
///
/// @param x Number to raise to given power y, as an UD60x18 number.
/// @param y Exponent to raise x to, as an UD60x18 number.
/// @return result x raised to power y, as an UD60x18 number.
function pow_1(UD60x18 x, UD60x18 y) pure returns (UD60x18 result) {
    uint256 xUint = unwrap_3(x);
    uint256 yUint = unwrap_3(y);

    if (xUint == 0) {
        result = yUint == 0 ? UNIT_4 : ZERO_1;
    } else {
        if (yUint == uUNIT_3) {
            result = x;
        } else {
            result = exp2_1(mul_1(log2_1(x), y));
        }
    }
}

/// @notice Raises x (an UD60x18 number) to the power y (unsigned basic integer) using the famous algorithm
/// "exponentiation by squaring".
///
/// @dev See https://en.wikipedia.org/wiki/Exponentiation_by_squaring
///
/// Requirements:
/// - The result must fit within `MAX_UD60x18`.
///
/// Caveats:
/// - All from "Common.mulDiv18".
/// - Assumes 0^0 is 1.
///
/// @param x The base as an UD60x18 number.
/// @param y The exponent as an uint256.
/// @return result The result as an UD60x18 number.
function powu_1(UD60x18 x, uint256 y) pure returns (UD60x18 result) {
    // Calculate the first iteration of the loop in advance.
    uint256 xUint = unwrap_3(x);
    uint256 resultUint = y & 1 > 0 ? xUint : uUNIT_3;

    // Equivalent to "for(y /= 2; y > 0; y /= 2)" but faster.
    for (y >>= 1; y > 0; y >>= 1) {
        xUint = mulDiv18(xUint, xUint);

        // Equivalent to "y % 2 == 1" but faster.
        if (y & 1 > 0) {
            resultUint = mulDiv18(resultUint, xUint);
        }
    }
    result = wrap_3(resultUint);
}

/// @notice Calculates the square root of x, rounding down.
/// @dev Uses the Babylonian method https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method.
///
/// Requirements:
/// - x must be less than `MAX_UD60x18` divided by `UNIT`.
///
/// @param x The UD60x18 number for which to calculate the square root.
/// @return result The result as an UD60x18 number.
function sqrt_1(UD60x18 x) pure returns (UD60x18 result) {
    uint256 xUint = unwrap_3(x);

    unchecked {
        if (xUint > uMAX_UD60x18 / uUNIT_3) {
            revert PRBMath_UD60x18_Sqrt_Overflow(x);
        }
        // Multiply x by `UNIT` to account for the factor of `UNIT` that is picked up when multiplying two UD60x18
        // numbers together (in this case, the two numbers are both the square root).
        result = wrap_3(prbSqrt(xUint * uUNIT_3));
    }
}

// lib/prb-math/src/sd1x18/ValueType.sol

/// @notice The signed 1.18-decimal fixed-point number representation, which can have up to 1 digit and up to 18 decimals.
/// The values of this are bound by the minimum and the maximum values permitted by the underlying Solidity type int64.
/// This is useful when end users want to use int64 to save gas, e.g. with tight variable packing in contract storage.
type SD1x18 is int64;

/*//////////////////////////////////////////////////////////////////////////
                                    CASTING
//////////////////////////////////////////////////////////////////////////*/

using { intoSD59x18_0, intoUD2x18_0, intoUD60x18_0, intoUint256_0, intoUint128_0, intoUint40_0, unwrap_0 } for SD1x18 global;

// lib/prb-math/src/sd59x18/ValueType.sol

/// @notice The signed 59.18-decimal fixed-point number representation, which can have up to 59 digits and up to 18 decimals.
/// The values of this are bound by the minimum and the maximum values permitted by the underlying Solidity type int256.
type SD59x18 is int256;

/*//////////////////////////////////////////////////////////////////////////
                                    CASTING
//////////////////////////////////////////////////////////////////////////*/

using {
    intoInt256,
    intoSD1x18_0,
    intoUD2x18_1,
    intoUD60x18_1,
    intoUint256_1,
    intoUint128_1,
    intoUint40_1,
    unwrap_1
} for SD59x18 global;

/*//////////////////////////////////////////////////////////////////////////
                            MATHEMATICAL FUNCTIONS
//////////////////////////////////////////////////////////////////////////*/

using {
    abs,
    avg_0,
    ceil_0,
    div_0,
    exp_0,
    exp2_0,
    floor_0,
    frac_0,
    gm_0,
    inv_0,
    log10_0,
    log2_0,
    ln_0,
    mul_0,
    pow_0,
    powu_0,
    sqrt_0
} for SD59x18 global;

/*//////////////////////////////////////////////////////////////////////////
                                HELPER FUNCTIONS
//////////////////////////////////////////////////////////////////////////*/

using {
    add_0,
    and_0,
    eq_0,
    gt_0,
    gte_0,
    isZero_0,
    lshift_0,
    lt_0,
    lte_0,
    mod_0,
    neq_0,
    or_0,
    rshift_0,
    sub_0,
    uncheckedAdd_0,
    uncheckedSub_0,
    uncheckedUnary,
    xor_0
} for SD59x18 global;

// lib/prb-math/src/ud2x18/ValueType.sol

/// @notice The unsigned 2.18-decimal fixed-point number representation, which can have up to 2 digits and up to 18 decimals.
/// The values of this are bound by the minimum and the maximum values permitted by the underlying Solidity type uint64.
/// This is useful when end users want to use uint64 to save gas, e.g. with tight variable packing in contract storage.
type UD2x18 is uint64;

/*//////////////////////////////////////////////////////////////////////////
                                    CASTING
//////////////////////////////////////////////////////////////////////////*/

using { intoSD1x18_1, intoSD59x18_1, intoUD60x18_2, intoUint256_2, intoUint128_2, intoUint40_2, unwrap_2 } for UD2x18 global;

// lib/prb-math/src/ud60x18/ValueType.sol

/// @notice The unsigned 60.18-decimal fixed-point number representation, which can have up to 60 digits and up to 18 decimals.
/// The values of this are bound by the minimum and the maximum values permitted by the Solidity type uint256.
/// @dev The value type is defined here so it can be imported in all other files.
type UD60x18 is uint256;

/*//////////////////////////////////////////////////////////////////////////
                                    CASTING
//////////////////////////////////////////////////////////////////////////*/

using { intoSD1x18_2, intoUD2x18_2, intoSD59x18_2, intoUint128_3, intoUint256_3, intoUint40_3, unwrap_3 } for UD60x18 global;

/*//////////////////////////////////////////////////////////////////////////
                            MATHEMATICAL FUNCTIONS
//////////////////////////////////////////////////////////////////////////*/

/// The global "using for" directive makes the functions in this library callable on the UD60x18 type.
using {
    avg_1,
    ceil_1,
    div_1,
    exp_1,
    exp2_1,
    floor_1,
    frac_1,
    gm_1,
    inv_1,
    ln_1,
    log10_1,
    log2_1,
    mul_1,
    pow_1,
    powu_1,
    sqrt_1
} for UD60x18 global;

/*//////////////////////////////////////////////////////////////////////////
                                HELPER FUNCTIONS
//////////////////////////////////////////////////////////////////////////*/

/// The global "using for" directive makes the functions in this library callable on the UD60x18 type.
using {
    add_1,
    and_1,
    eq_1,
    gt_1,
    gte_1,
    isZero_1,
    lshift_1,
    lt_1,
    lte_1,
    mod_1,
    neq_1,
    or_1,
    rshift_1,
    sub_1,
    uncheckedAdd_1,
    uncheckedSub_1,
    xor_1
} for UD60x18 global;

// lib/prb-math/src/ud60x18/Conversions.sol

/// @notice Converts an UD60x18 number to a simple integer by dividing it by `UNIT`. Rounds towards zero in the process.
/// @dev Rounds down in the process.
/// @param x The UD60x18 number to convert.
/// @return result The same number in basic integer form.
function convert_0(UD60x18 x) pure returns (uint256 result) {
    result = UD60x18.unwrap(x) / uUNIT_3;
}

/// @notice Converts a simple integer to UD60x18 by multiplying it by `UNIT`.
///
/// @dev Requirements:
/// - x must be less than or equal to `MAX_UD60x18` divided by `UNIT`.
///
/// @param x The basic integer to convert.
/// @param result The same number converted to UD60x18.
function convert_1(uint256 x) pure returns (UD60x18 result) {
    if (x > uMAX_UD60x18 / uUNIT_3) {
        revert PRBMath_UD60x18_Convert_Overflow(x);
    }
    unchecked {
        result = UD60x18.wrap(x * uUNIT_3);
    }
}

/// @notice Alias for the `convert` function defined above.
/// @dev Here for backward compatibility. Will be removed in V4.
function fromUD60x18(UD60x18 x) pure returns (uint256 result) {
    result = convert_0(x);
}

/// @notice Alias for the `convert` function defined above.
/// @dev Here for backward compatibility. Will be removed in V4.
function toUD60x18(uint256 x) pure returns (UD60x18 result) {
    result = convert_1(x);
}

// lib/prb-math/src/UD60x18.sol

// contracts/goodDollar/BancorExchangeProvider.sol

/**
 * @title BancorExchangeProvider
 * @notice Provides exchange functionality for Bancor pools.
 */
contract BancorExchangeProvider is IExchangeProvider, IBancorExchangeProvider, BancorFormula, OwnableUpgradeable {
  /* ========================================================= */
  /* ==================== State Variables ==================== */
  /* ========================================================= */

  // Address of the broker contract.
  address public broker;

  // Address of the reserve contract.
  IReserve public reserve;

  // Maps an exchange id to the corresponding PoolExchange struct.
  // exchangeId is in the format "asset0Symbol:asset1Symbol"
  mapping(bytes32 => PoolExchange) public exchanges;
  bytes32[] public exchangeIds;

  // Token precision multiplier used to normalize values to the same precision when calculating amounts.
  mapping(address => uint256) public tokenPrecisionMultipliers;

  /* ===================================================== */
  /* ==================== Constructor ==================== */
  /* ===================================================== */

  /**
   * @dev Should be called with disable=true in deployments when it's accessed through a Proxy.
   * Call this with disable=false during testing, when used without a proxy.
   * @param disable Set to true to run `_disableInitializers()` inherited from
   * openzeppelin-contracts-upgradeable/Initializable.sol
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /// @inheritdoc IBancorExchangeProvider
  function initialize(address _broker, address _reserve) public initializer {
    _initialize(_broker, _reserve);
  }

  function _initialize(address _broker, address _reserve) internal onlyInitializing {
    __Ownable_init();

    BancorFormula.init();
    setBroker(_broker);
    setReserve(_reserve);
  }

  /* =================================================== */
  /* ==================== Modifiers ==================== */
  /* =================================================== */

  modifier onlyBroker() {
    require(msg.sender == broker, "Caller is not the Broker");
    _;
  }

  modifier verifyExchangeTokens(address tokenIn, address tokenOut, PoolExchange memory exchange) {
    require(
      (tokenIn == exchange.reserveAsset && tokenOut == exchange.tokenAddress) ||
        (tokenIn == exchange.tokenAddress && tokenOut == exchange.reserveAsset),
      "tokenIn and tokenOut must match exchange"
    );
    _;
  }

  /* ======================================================== */
  /* ==================== View Functions ==================== */
  /* ======================================================== */

  /// @inheritdoc IBancorExchangeProvider
  function getPoolExchange(bytes32 exchangeId) public view returns (PoolExchange memory exchange) {
    exchange = exchanges[exchangeId];
    require(exchange.tokenAddress != address(0), "Exchange does not exist");
    return exchange;
  }

  /// @inheritdoc IBancorExchangeProvider
  function getExchangeIds() external view returns (bytes32[] memory) {
    return exchangeIds;
  }

  /**
   * @inheritdoc IExchangeProvider
   * @dev We don't expect the number of exchanges to grow to
   * astronomical values so this is safe gas-wise as is.
   */
  function getExchanges() public view returns (Exchange[] memory _exchanges) {
    uint256 numExchanges = exchangeIds.length;
    _exchanges = new Exchange[](numExchanges);
    for (uint256 i = 0; i < numExchanges; i++) {
      _exchanges[i].exchangeId = exchangeIds[i];
      _exchanges[i].assets = new address[](2);
      _exchanges[i].assets[0] = exchanges[exchangeIds[i]].reserveAsset;
      _exchanges[i].assets[1] = exchanges[exchangeIds[i]].tokenAddress;
    }
  }

  /// @inheritdoc IExchangeProvider
  function getAmountOut(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view virtual returns (uint256 amountOut) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint256 scaledAmountIn = amountIn * tokenPrecisionMultipliers[tokenIn];

    if (tokenIn == exchange.tokenAddress) {
      require(scaledAmountIn < exchange.tokenSupply, "amountIn is greater than tokenSupply");
      // apply exit contribution
      scaledAmountIn = (scaledAmountIn * (MAX_WEIGHT - exchange.exitContribution)) / MAX_WEIGHT;
    }

    uint256 scaledAmountOut = _getScaledAmountOut(exchange, tokenIn, tokenOut, scaledAmountIn);
    amountOut = scaledAmountOut / tokenPrecisionMultipliers[tokenOut];
    return amountOut;
  }

  /// @inheritdoc IExchangeProvider
  function getAmountIn(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) external view virtual returns (uint256 amountIn) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint256 scaledAmountOut = amountOut * tokenPrecisionMultipliers[tokenOut];
    uint256 scaledAmountIn = _getScaledAmountIn(exchange, tokenIn, tokenOut, scaledAmountOut);

    if (tokenIn == exchange.tokenAddress) {
      // apply exit contribution
      scaledAmountIn = (scaledAmountIn * MAX_WEIGHT) / (MAX_WEIGHT - exchange.exitContribution);
      require(scaledAmountIn < exchange.tokenSupply, "amountIn is greater than tokenSupply");
    }

    amountIn = divAndRoundUp(scaledAmountIn, tokenPrecisionMultipliers[tokenIn]);
    return amountIn;
  }

  /// @inheritdoc IBancorExchangeProvider
  function currentPrice(bytes32 exchangeId) public view returns (uint256 price) {
    // calculates: reserveBalance / (tokenSupply * reserveRatio)
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint256 scaledReserveRatio = uint256(exchange.reserveRatio) * 1e10;

    UD60x18 denominator = wrap_3(exchange.tokenSupply).mul_1(wrap_3(scaledReserveRatio));
    uint256 priceScaled = unwrap_3(wrap_3(exchange.reserveBalance).div_1(denominator));

    price = priceScaled / tokenPrecisionMultipliers[exchange.reserveAsset];
  }

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc IBancorExchangeProvider
  function setBroker(address _broker) public onlyOwner {
    require(_broker != address(0), "Broker address must be set");
    broker = _broker;
    emit BrokerUpdated(_broker);
  }

  /// @inheritdoc IBancorExchangeProvider
  function setReserve(address _reserve) public onlyOwner {
    require(_reserve != address(0), "Reserve address must be set");
    reserve = IReserve(_reserve);
    emit ReserveUpdated(_reserve);
  }

  /// @inheritdoc IBancorExchangeProvider
  function setExitContribution(bytes32 exchangeId, uint32 exitContribution) external virtual onlyOwner {
    return _setExitContribution(exchangeId, exitContribution);
  }

  /// @inheritdoc IBancorExchangeProvider
  function createExchange(PoolExchange calldata _exchange) external virtual onlyOwner returns (bytes32 exchangeId) {
    return _createExchange(_exchange);
  }

  /// @inheritdoc IBancorExchangeProvider
  function destroyExchange(
    bytes32 exchangeId,
    uint256 exchangeIdIndex
  ) external virtual onlyOwner returns (bool destroyed) {
    return _destroyExchange(exchangeId, exchangeIdIndex);
  }

  /// @inheritdoc IExchangeProvider
  function swapIn(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) public virtual onlyBroker returns (uint256 amountOut) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint256 scaledAmountIn = amountIn * tokenPrecisionMultipliers[tokenIn];
    uint256 exitContribution = 0;

    if (tokenIn == exchange.tokenAddress) {
      require(scaledAmountIn < exchange.tokenSupply, "amountIn is greater than tokenSupply");
      // apply exit contribution
      exitContribution = (scaledAmountIn * exchange.exitContribution) / MAX_WEIGHT;
      scaledAmountIn -= exitContribution;
    }

    uint256 scaledAmountOut = _getScaledAmountOut(exchange, tokenIn, tokenOut, scaledAmountIn);

    executeSwap(exchangeId, tokenIn, scaledAmountIn, scaledAmountOut);
    if (exitContribution > 0) {
      _accountExitContribution(exchangeId, exitContribution);
    }

    amountOut = scaledAmountOut / tokenPrecisionMultipliers[tokenOut];
    return amountOut;
  }

  /// @inheritdoc IExchangeProvider
  function swapOut(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) public virtual onlyBroker returns (uint256 amountIn) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint256 scaledAmountOut = amountOut * tokenPrecisionMultipliers[tokenOut];
    uint256 scaledAmountIn = _getScaledAmountIn(exchange, tokenIn, tokenOut, scaledAmountOut);

    uint256 exitContribution = 0;
    uint256 scaledAmountInWithExitContribution = scaledAmountIn;

    if (tokenIn == exchange.tokenAddress) {
      // apply exit contribution
      scaledAmountInWithExitContribution = (scaledAmountIn * MAX_WEIGHT) / (MAX_WEIGHT - exchange.exitContribution);
      require(
        scaledAmountInWithExitContribution < exchange.tokenSupply,
        "amountIn required is greater than tokenSupply"
      );
      exitContribution = scaledAmountInWithExitContribution - scaledAmountIn;
    }

    executeSwap(exchangeId, tokenIn, scaledAmountIn, scaledAmountOut);
    if (exitContribution > 0) {
      _accountExitContribution(exchangeId, exitContribution);
    }

    amountIn = divAndRoundUp(scaledAmountInWithExitContribution, tokenPrecisionMultipliers[tokenIn]);
    return amountIn;
  }

  /* =========================================================== */
  /* ==================== Private Functions ==================== */
  /* =========================================================== */

  function _createExchange(PoolExchange calldata _exchange) internal returns (bytes32 exchangeId) {
    PoolExchange memory exchange = _exchange;
    validateExchange(exchange);

    // slither-disable-next-line encode-packed-collision
    exchangeId = keccak256(
      abi.encodePacked(IERC20(exchange.reserveAsset).symbol(), IERC20(exchange.tokenAddress).symbol())
    );
    require(exchanges[exchangeId].reserveAsset == address(0), "Exchange already exists");

    uint256 reserveAssetDecimals = IERC20(exchange.reserveAsset).decimals();
    uint256 tokenDecimals = IERC20(exchange.tokenAddress).decimals();
    require(reserveAssetDecimals <= 18, "Reserve asset decimals must be <= 18");
    require(tokenDecimals <= 18, "Token decimals must be <= 18");

    tokenPrecisionMultipliers[exchange.reserveAsset] = 10 ** (18 - uint256(reserveAssetDecimals));
    tokenPrecisionMultipliers[exchange.tokenAddress] = 10 ** (18 - uint256(tokenDecimals));

    exchange.reserveBalance = exchange.reserveBalance * tokenPrecisionMultipliers[exchange.reserveAsset];
    exchange.tokenSupply = exchange.tokenSupply * tokenPrecisionMultipliers[exchange.tokenAddress];

    exchanges[exchangeId] = exchange;
    exchangeIds.push(exchangeId);
    emit ExchangeCreated(exchangeId, exchange.reserveAsset, exchange.tokenAddress);
  }

  function _destroyExchange(bytes32 exchangeId, uint256 exchangeIdIndex) internal returns (bool destroyed) {
    require(exchangeIdIndex < exchangeIds.length, "exchangeIdIndex not in range");
    require(exchangeIds[exchangeIdIndex] == exchangeId, "exchangeId at index doesn't match");
    PoolExchange memory exchange = exchanges[exchangeId];

    delete exchanges[exchangeId];
    exchangeIds[exchangeIdIndex] = exchangeIds[exchangeIds.length - 1];
    exchangeIds.pop();
    destroyed = true;

    emit ExchangeDestroyed(exchangeId, exchange.reserveAsset, exchange.tokenAddress);
  }

  function _setExitContribution(bytes32 exchangeId, uint32 exitContribution) internal {
    require(exchanges[exchangeId].reserveAsset != address(0), "Exchange does not exist");
    require(exitContribution < MAX_WEIGHT, "Exit contribution is too high");

    PoolExchange storage exchange = exchanges[exchangeId];
    exchange.exitContribution = exitContribution;
    emit ExitContributionSet(exchangeId, exitContribution);
  }

  /**
   * @notice Execute a swap against the in-memory exchange and write the new exchange state to storage.
   * @param exchangeId The ID of the pool
   * @param tokenIn The token to be sold
   * @param scaledAmountIn The amount of tokenIn to be sold, scaled to 18 decimals
   * @param scaledAmountOut The amount of tokenOut to be bought, scaled to 18 decimals
   */
  function executeSwap(bytes32 exchangeId, address tokenIn, uint256 scaledAmountIn, uint256 scaledAmountOut) internal {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    if (tokenIn == exchange.reserveAsset) {
      exchange.reserveBalance += scaledAmountIn;
      exchange.tokenSupply += scaledAmountOut;
    } else {
      require(exchange.reserveBalance >= scaledAmountOut, "Insufficient reserve balance for swap");
      exchange.reserveBalance -= scaledAmountOut;
      exchange.tokenSupply -= scaledAmountIn;
    }
    exchanges[exchangeId].reserveBalance = exchange.reserveBalance;
    exchanges[exchangeId].tokenSupply = exchange.tokenSupply;
  }

  /**
   * @notice Accounting of exit contribution on a swap.
   * @dev Accounting of exit contribution without changing the current price of an exchange.
   * this is done by updating the reserve ratio and subtracting the exit contribution from the token supply.
   * Formula: newRatio = (Supply * oldRatio) / (Supply - exitContribution)
   * @param exchangeId The ID of the pool
   * @param exitContribution The amount of the token to be removed from the pool, scaled to 18 decimals
   */
  function _accountExitContribution(bytes32 exchangeId, uint256 exitContribution) internal {
    PoolExchange memory exchange = getPoolExchange(exchangeId);
    uint256 scaledReserveRatio = uint256(exchange.reserveRatio) * 1e10;
    UD60x18 nominator = wrap_3(exchange.tokenSupply).mul_1(wrap_3(scaledReserveRatio));
    UD60x18 denominator = wrap_3(exchange.tokenSupply - exitContribution);
    UD60x18 newRatioScaled = nominator.div_1(denominator);

    uint256 newRatio = unwrap_3(newRatioScaled) / 1e10;

    exchanges[exchangeId].reserveRatio = uint32(newRatio);
    exchanges[exchangeId].tokenSupply -= exitContribution;
  }

  /**
   * @notice Division and rounding up if there is a remainder
   * @param a The dividend
   * @param b The divisor
   * @return The result of the division rounded up
   */
  function divAndRoundUp(uint256 a, uint256 b) internal pure returns (uint256) {
    return (a / b) + (a % b > 0 ? 1 : 0);
  }

  /**
   * @notice Calculate the scaledAmountIn of tokenIn for a given scaledAmountOut of tokenOut
   * @param exchange The pool exchange to operate on
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param scaledAmountOut The amount of tokenOut to be bought, scaled to 18 decimals
   * @return scaledAmountIn The amount of tokenIn to be sold, scaled to 18 decimals
   */
  function _getScaledAmountIn(
    PoolExchange memory exchange,
    address tokenIn,
    address tokenOut,
    uint256 scaledAmountOut
  ) internal view verifyExchangeTokens(tokenIn, tokenOut, exchange) returns (uint256 scaledAmountIn) {
    if (tokenIn == exchange.reserveAsset) {
      scaledAmountIn = fundCost(exchange.tokenSupply, exchange.reserveBalance, exchange.reserveRatio, scaledAmountOut);
    } else {
      scaledAmountIn = saleCost(exchange.tokenSupply, exchange.reserveBalance, exchange.reserveRatio, scaledAmountOut);
    }
  }

  /**
   * @notice Calculate the scaledAmountOut of tokenOut received for a given scaledAmountIn of tokenIn
   * @param exchange The pool exchange to operate on
   * @param tokenIn The token to be sold
   * @param tokenOut The token to be bought
   * @param scaledAmountIn The amount of tokenIn to be sold, scaled to 18 decimals
   * @return scaledAmountOut The amount of tokenOut to be bought, scaled to 18 decimals
   */
  function _getScaledAmountOut(
    PoolExchange memory exchange,
    address tokenIn,
    address tokenOut,
    uint256 scaledAmountIn
  ) internal view verifyExchangeTokens(tokenIn, tokenOut, exchange) returns (uint256 scaledAmountOut) {
    if (tokenIn == exchange.reserveAsset) {
      scaledAmountOut = purchaseTargetAmount(
        exchange.tokenSupply,
        exchange.reserveBalance,
        exchange.reserveRatio,
        scaledAmountIn
      );
    } else {
      scaledAmountOut = saleTargetAmount(
        exchange.tokenSupply,
        exchange.reserveBalance,
        exchange.reserveRatio,
        scaledAmountIn
      );
    }
  }

  /**
   * @notice Validates a PoolExchange's parameters and configuration
   * @dev Reverts if not valid
   * @param exchange The PoolExchange to validate
   */
  function validateExchange(PoolExchange memory exchange) internal view {
    require(exchange.reserveAsset != address(0), "Invalid reserve asset");
    require(
      reserve.isCollateralAsset(exchange.reserveAsset),
      "Reserve asset must be a collateral registered with the reserve"
    );
    require(exchange.tokenAddress != address(0), "Invalid token address");
    require(reserve.isStableAsset(exchange.tokenAddress), "Token must be a stable registered with the reserve");
    require(exchange.reserveRatio > 1, "Reserve ratio is too low");
    require(exchange.reserveRatio <= MAX_WEIGHT, "Reserve ratio is too high");
    require(exchange.exitContribution <= MAX_WEIGHT, "Exit contribution is too high");
    require(exchange.reserveBalance > 0, "Reserve balance must be greater than 0");
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}

// contracts/goodDollar/GoodDollarExchangeProvider.sol

/**
 * @title GoodDollarExchangeProvider
 * @notice Provides exchange functionality for the GoodDollar system.
 */
contract GoodDollarExchangeProvider is IGoodDollarExchangeProvider, BancorExchangeProvider, PausableUpgradeable {
  /* ========================================================= */
  /* ==================== State Variables ==================== */
  /* ========================================================= */

  // Address of the Expansion Controller contract.
  IGoodDollarExpansionController public expansionController;

  // Address of the GoodDollar DAO contract.
  // solhint-disable-next-line var-name-mixedcase
  address public AVATAR;

  /* ===================================================== */
  /* ==================== Constructor ==================== */
  /* ===================================================== */

  /**
   * @dev Should be called with disable=true in deployments when it's accessed through a Proxy.
   * Call this with disable=false during testing, when used without a proxy.
   * @param disable Set to true to run `_disableInitializers()` inherited from
   * openzeppelin-contracts-upgradeable/Initializable.sol
   */
  constructor(bool disable) BancorExchangeProvider(disable) {}

  /// @inheritdoc IGoodDollarExchangeProvider
  function initialize(
    address _broker,
    address _reserve,
    address _expansionController,
    address _avatar
  ) public initializer {
    BancorExchangeProvider._initialize(_broker, _reserve);
    __Pausable_init();

    setExpansionController(_expansionController);
    setAvatar(_avatar);
  }

  /* =================================================== */
  /* ==================== Modifiers ==================== */
  /* =================================================== */

  modifier onlyAvatar() {
    require(msg.sender == AVATAR, "Only Avatar can call this function");
    _;
  }

  modifier onlyExpansionController() {
    require(msg.sender == address(expansionController), "Only ExpansionController can call this function");
    _;
  }

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc IGoodDollarExchangeProvider
  function setAvatar(address _avatar) public onlyOwner {
    require(_avatar != address(0), "Avatar address must be set");
    AVATAR = _avatar;
    emit AvatarUpdated(_avatar);
  }

  /// @inheritdoc IGoodDollarExchangeProvider
  function setExpansionController(address _expansionController) public onlyOwner {
    require(_expansionController != address(0), "ExpansionController address must be set");
    expansionController = IGoodDollarExpansionController(_expansionController);
    emit ExpansionControllerUpdated(_expansionController);
  }

  /**
   * @inheritdoc BancorExchangeProvider
   * @dev Only callable by the GoodDollar DAO contract.
   */
  function setExitContribution(bytes32 exchangeId, uint32 exitContribution) external override onlyAvatar {
    return _setExitContribution(exchangeId, exitContribution);
  }

  /**
   * @inheritdoc BancorExchangeProvider
   * @dev Only callable by the GoodDollar DAO contract.
   */
  function createExchange(PoolExchange calldata _exchange) external override onlyAvatar returns (bytes32 exchangeId) {
    return _createExchange(_exchange);
  }

  /**
   * @inheritdoc BancorExchangeProvider
   * @dev Only callable by the GoodDollar DAO contract.
   */
  function destroyExchange(
    bytes32 exchangeId,
    uint256 exchangeIdIndex
  ) external override onlyAvatar returns (bool destroyed) {
    return _destroyExchange(exchangeId, exchangeIdIndex);
  }

  /// @inheritdoc BancorExchangeProvider
  function swapIn(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) public override onlyBroker whenNotPaused returns (uint256 amountOut) {
    amountOut = BancorExchangeProvider.swapIn(exchangeId, tokenIn, tokenOut, amountIn);
  }

  /// @inheritdoc BancorExchangeProvider
  function swapOut(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) public override onlyBroker whenNotPaused returns (uint256 amountIn) {
    amountIn = BancorExchangeProvider.swapOut(exchangeId, tokenIn, tokenOut, amountOut);
  }

  /**
   * @inheritdoc IGoodDollarExchangeProvider
   * @dev Calculates the amount of G$ tokens that need to be minted as a result of the expansion
   *      while keeping the current price the same.
   *      calculation: amountToMint = (tokenSupply * reserveRatio - tokenSupply * newRatio) / newRatio
   */
  function mintFromExpansion(
    bytes32 exchangeId,
    uint256 reserveRatioScalar
  ) external onlyExpansionController whenNotPaused returns (uint256 amountToMint) {
    require(reserveRatioScalar > 0, "Reserve ratio scalar must be greater than 0");
    PoolExchange memory exchange = getPoolExchange(exchangeId);

    UD60x18 scaledRatio = wrap_3(uint256(exchange.reserveRatio) * 1e10);

    // The division and multiplication by 1e10 here ensures that the new ratio used for calculating the amount to mint
    // is the same as the one set in the exchange but only scaled to 18 decimals.
    // Ignored, because the division and multiplication by 1e10 is needed see comment above.
    // slither-disable-next-line divide-before-multiply
    UD60x18 newRatio = wrap_3((unwrap_3(scaledRatio.mul_1(wrap_3(reserveRatioScalar))) / 1e10) * 1e10);

    uint32 newRatioUint = uint32(unwrap_3(newRatio) / 1e10);
    require(newRatioUint > 0, "New ratio must be greater than 0");

    UD60x18 numerator = wrap_3(exchange.tokenSupply).mul_1(scaledRatio);
    numerator = numerator.sub_1(wrap_3(exchange.tokenSupply).mul_1(newRatio));

    uint256 scaledAmountToMint = unwrap_3(numerator.div_1(newRatio));

    exchanges[exchangeId].reserveRatio = newRatioUint;
    exchanges[exchangeId].tokenSupply += scaledAmountToMint;

    amountToMint = scaledAmountToMint / tokenPrecisionMultipliers[exchange.tokenAddress];
    emit ReserveRatioUpdated(exchangeId, newRatioUint);

    return amountToMint;
  }

  /**
   * @inheritdoc IGoodDollarExchangeProvider
   * @dev Calculates the amount of G$ tokens that need to be minted as a result of the reserve interest
   *      flowing into the reserve while keeping the current price the same.
   *      calculation: amountToMint = reserveInterest * tokenSupply / reserveBalance
   */
  function mintFromInterest(
    bytes32 exchangeId,
    uint256 reserveInterest
  ) external onlyExpansionController whenNotPaused returns (uint256 amountToMint) {
    PoolExchange memory exchange = getPoolExchange(exchangeId);

    uint256 amountToMintScaled = unwrap_3(
      wrap_3(reserveInterest).mul_1(wrap_3(exchange.tokenSupply)).div_1(wrap_3(exchange.reserveBalance))
    );
    amountToMint = amountToMintScaled / tokenPrecisionMultipliers[exchange.tokenAddress];

    exchanges[exchangeId].tokenSupply += amountToMintScaled;
    exchanges[exchangeId].reserveBalance += reserveInterest;

    return amountToMint;
  }

  /**
   * @inheritdoc IGoodDollarExchangeProvider
   * @dev Calculates the new reserve ratio needed to mint the G$ reward while keeping the current price the same.
   *      calculation: newRatio = (tokenSupply * reserveRatio) / (tokenSupply + reward)
   */
  function updateRatioForReward(
    bytes32 exchangeId,
    uint256 reward,
    uint256 maxSlippagePercentage
  ) external onlyExpansionController whenNotPaused {
    PoolExchange memory exchange = getPoolExchange(exchangeId);

    uint256 scaledRatio = uint256(exchange.reserveRatio) * 1e10;
    uint256 scaledReward = reward * tokenPrecisionMultipliers[exchange.tokenAddress];

    UD60x18 numerator = wrap_3(exchange.tokenSupply).mul_1(wrap_3(scaledRatio));
    UD60x18 denominator = wrap_3(exchange.tokenSupply).add_1(wrap_3(scaledReward));
    uint256 newScaledRatio = unwrap_3(numerator.div_1(denominator));

    uint32 newRatioUint = uint32(newScaledRatio / 1e10);

    require(newRatioUint > 0, "New ratio must be greater than 0");

    uint256 allowedSlippage = (exchange.reserveRatio * maxSlippagePercentage) / MAX_WEIGHT;
    require(exchange.reserveRatio - newRatioUint <= allowedSlippage, "Slippage exceeded");

    exchanges[exchangeId].reserveRatio = newRatioUint;
    exchanges[exchangeId].tokenSupply += scaledReward;

    emit ReserveRatioUpdated(exchangeId, newRatioUint);
  }

  /**
   * @inheritdoc IGoodDollarExchangeProvider
   * @dev Only callable by the GoodDollar DAO contract.
   */
  function pause() external virtual onlyAvatar {
    _pause();
  }

  /**
   * @inheritdoc IGoodDollarExchangeProvider
   * @dev Only callable by the GoodDollar DAO contract.
   */
  function unpause() external virtual onlyAvatar {
    _unpause();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
