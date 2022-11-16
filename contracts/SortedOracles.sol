pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "./interfaces/ISortedOracles.sol";
import "./common/interfaces/ICeloVersionedContract.sol";
import "./interfaces/IBreakerBox.sol";

import "./common/FixidityLib.sol";
import "./common/Initializable.sol";
import "./common/linkedlists/AddressSortedLinkedListWithMedian.sol";
import "./common/linkedlists/SortedLinkedListWithMedian.sol";

/**
 * @title Maintains a sorted list of oracle exchange rates between CELO and other currencies.
 */
contract SortedOracles is ISortedOracles, ICeloVersionedContract, Ownable, Initializable {
  using SafeMath for uint256;
  using AddressSortedLinkedListWithMedian for SortedLinkedListWithMedian.List;
  using FixidityLib for FixidityLib.Fraction;

  uint256 private constant FIXED1_UINT = 1000000000000000000000000;

  // Maps a rateFeedID address to a sorted list of report values.
  mapping(address => SortedLinkedListWithMedian.List) private rates;
  // Maps a rateFeedID address to a sorted list of report timestamps.
  mapping(address => SortedLinkedListWithMedian.List) private timestamps;
  mapping(address => mapping(address => bool)) public isOracle;
  mapping(address => address[]) public oracles;
  mapping(address => uint256) public previousMedianRate;

  // `reportExpirySeconds` is the fallback value used to determine reporting
  // frequency. Initially it was the _only_ value but we later introduced
  // the per rateFeedID mapping in `rateFeedReportExpirySeconds`. If a rateFeedID
  // doesn't have a value in the mapping (i.e. it's 0), the fallback is used.
  // See: #getRateFeedReportExpirySeconds
  uint256 public reportExpirySeconds;
  mapping(address => uint256) public rateFeedReportExpirySeconds;

  IBreakerBox public breakerBox;

  event OracleAdded(address indexed rateFeedID, address indexed oracleAddress);
  event OracleRemoved(address indexed rateFeedID, address indexed oracleAddress);
  event OracleReported(address indexed rateFeedID, address indexed oracle, uint256 timestamp, uint256 value);
  event OracleReportRemoved(address indexed rateFeedID, address indexed oracle);
  event MedianUpdated(address indexed rateFeedID, uint256 value);
  event ReportExpirySet(uint256 reportExpiry);
  event RateFeedReportExpirySet(address rateFeedID, uint256 reportExpiry);
  event BreakerBoxUpdated(address indexed newBreakerBox);

  modifier onlyOracle(address rateFeedID) {
    require(isOracle[rateFeedID][msg.sender], "sender was not an oracle for rateFeedID addr");
    _;
  }

  /**
   * @notice Returns the storage, major, minor, and patch version of the contract.
   * @return Storage version of the contract.
   * @return Major version of the contract.
   * @return Minor version of the contract.
   * @return Patch version of the contract.
   */
  function getVersionNumber()
    external
    pure
    returns (
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    return (1, 1, 2, 1);
  }

  /**
   * @notice Sets initialized == true on implementation contracts
   * @param test Set to true to skip implementation initialization
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @notice Used in place of the constructor to allow the contract to be upgradable via proxy.
   * @param _reportExpirySeconds The number of seconds before a report is considered expired.
   */
  function initialize(uint256 _reportExpirySeconds) external initializer {
    _transferOwnership(msg.sender);
    setReportExpiry(_reportExpirySeconds);
  }

  /**
   * @notice Sets the report expiry parameter.
   * @param _reportExpirySeconds The number of seconds before a report is considered expired.
   */
  function setReportExpiry(uint256 _reportExpirySeconds) public onlyOwner {
    require(_reportExpirySeconds > 0, "report expiry seconds must be > 0");
    require(_reportExpirySeconds != reportExpirySeconds, "reportExpirySeconds hasn't changed");
    reportExpirySeconds = _reportExpirySeconds;
    emit ReportExpirySet(_reportExpirySeconds);
  }

  /**
   * @notice Sets the report expiry parameter for a rateFeedID.
   * @param _rateFeedID The address of the rateFeedID to set expiry for.
   * @param _reportExpirySeconds The number of seconds before a report is considered expired.
   */
  function setRateFeedReportExpiry(address _rateFeedID, uint256 _reportExpirySeconds) external onlyOwner {
    require(_reportExpirySeconds > 0, "report expiry seconds must be > 0");
    require(_reportExpirySeconds != rateFeedReportExpirySeconds[_rateFeedID], "rateFeedID reportExpirySeconds hasn't changed");
    rateFeedReportExpirySeconds[_rateFeedID] = _reportExpirySeconds;
    emit RateFeedReportExpirySet(_rateFeedID, _reportExpirySeconds);
  }

  /**
   * @notice Sets the address of the BreakerBox.
   * @param newBreakerBox The new BreakerBox address.
   */
  function setBreakerBox(IBreakerBox newBreakerBox) public onlyOwner {
    breakerBox = newBreakerBox;
    emit BreakerBoxUpdated(address(newBreakerBox));
  }

  /**
   * @notice Adds a new Oracle.
   * @param rateFeedID The address of the rateFeedID.
   * @param oracleAddress The address of the oracle.
   */
  function addOracle(address rateFeedID, address oracleAddress) external onlyOwner {
    require(
      rateFeedID != address(0) && oracleAddress != address(0) && !isOracle[rateFeedID][oracleAddress],
      "rateFeedID addr was null or oracle addr was null or oracle addr is not an oracle for rateFeedID addr"
    );
    isOracle[rateFeedID][oracleAddress] = true;
    oracles[rateFeedID].push(oracleAddress);
    emit OracleAdded(rateFeedID, oracleAddress);
  }

  /**
   * @notice Removes an Oracle.
   * @param rateFeedID The address of the rateFeedID.
   * @param oracleAddress The address of the oracle.
   * @param index The index of `oracleAddress` in the list of oracles.
   */
  function removeOracle(
    address rateFeedID,
    address oracleAddress,
    uint256 index
  ) external onlyOwner {
    require(
      rateFeedID != address(0) &&
        oracleAddress != address(0) &&
        oracles[rateFeedID].length > index &&
        oracles[rateFeedID][index] == oracleAddress,
      "rateFeedID addr null or oracle addr null or index of rateFeedID oracle not mapped to oracle addr"
    );
    isOracle[rateFeedID][oracleAddress] = false;
    oracles[rateFeedID][index] = oracles[rateFeedID][oracles[rateFeedID].length.sub(1)];
    oracles[rateFeedID].length = oracles[rateFeedID].length.sub(1);
    if (reportExists(rateFeedID, oracleAddress)) {
      removeReport(rateFeedID, oracleAddress);
    }
    emit OracleRemoved(rateFeedID, oracleAddress);
  }

  /**
   * @notice Removes a report that is expired.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @param n The number of expired reports to remove, at most (deterministic upper gas bound).
   */
  function removeExpiredReports(address rateFeedID, uint256 n) external {
    require(
      rateFeedID != address(0) && n < timestamps[rateFeedID].getNumElements(),
      "rateFeedID addr null or trying to remove too many reports"
    );
    for (uint256 i = 0; i < n; i = i.add(1)) {
      (bool isExpired, address oldestAddress) = isOldestReportExpired(rateFeedID);
      if (isExpired) {
        removeReport(rateFeedID, oldestAddress);
      } else {
        break;
      }
    }
  }

  /**
   * @notice Check if last report is expired.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @return isExpired
   * @return The address of the last report.
   */
  function isOldestReportExpired(address rateFeedID) public view returns (bool, address) {
    require(rateFeedID != address(0));
    address oldest = timestamps[rateFeedID].getTail();
    uint256 timestamp = timestamps[rateFeedID].getValue(oldest);
    // solhint-disable-next-line not-rely-on-time
    if (now.sub(timestamp) >= getRateFeedReportExpirySeconds(rateFeedID)) {
      return (true, oldest);
    }
    return (false, oldest);
  }

  /**
   * @notice Updates an oracle value and the median.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @param value The amount of `rateFeedID` equal to one CELO, expressed as a fixidity value.
   * @param lesserKey The element which should be just left of the new oracle value.
   * @param greaterKey The element which should be just right of the new oracle value.
   * @dev Note that only one of `lesserKey` or `greaterKey` needs to be correct to reduce friction.
   */
  function report(
    address rateFeedID,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) external onlyOracle(rateFeedID) {
    uint256 originalMedian = rates[rateFeedID].getMedianValue();
    if (rates[rateFeedID].contains(msg.sender)) {
      rates[rateFeedID].update(msg.sender, value, lesserKey, greaterKey);

      // Rather than update the timestamp, we remove it and re-add it at the
      // head of the list later. The reason for this is that we need to handle
      // a few different cases:
      //   1. This oracle is the only one to report so far. lesserKey = address(0)
      //   2. Other oracles have reported since this one's last report. lesserKey = getHead()
      //   3. Other oracles have reported, but the most recent is this one.
      //      lesserKey = key immediately after getHead()
      //
      // However, if we just remove this timestamp, timestamps[rateFeedID].getHead()
      // does the right thing in all cases.
      timestamps[rateFeedID].remove(msg.sender);
    } else {
      rates[rateFeedID].insert(msg.sender, value, lesserKey, greaterKey);
    }
    timestamps[rateFeedID].insert(
      msg.sender,
      // solhint-disable-next-line not-rely-on-time
      now,
      timestamps[rateFeedID].getHead(),
      address(0)
    );
    emit OracleReported(rateFeedID, msg.sender, now, value);
    uint256 newMedian = rates[rateFeedID].getMedianValue();
    if (newMedian != originalMedian) {
      previousMedianRate[rateFeedID] = originalMedian;
      emit MedianUpdated(rateFeedID, newMedian);
    }
    breakerBox.checkAndSetBreakers(rateFeedID);
  }

  /**
   * @notice Returns the number of rates.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @return The number of reported oracle rates for `rateFeedID`.
   */
  function numRates(address rateFeedID) public view returns (uint256) {
    return rates[rateFeedID].getNumElements();
  }

  /**
   * @notice Returns the median rate.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @return The median exchange rate for `rateFeedID`.
   * @return fixidity
   */
  function medianRate(address rateFeedID) external view returns (uint256, uint256) {
    return (rates[rateFeedID].getMedianValue(), numRates(rateFeedID) == 0 ? 0 : FIXED1_UINT);
  }

  /**
   * @notice Gets all elements from the doubly linked list.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @return keys Keys of nn unpacked list of elements from largest to smallest.
   * @return values Values of an unpacked list of elements from largest to smallest.
   * @return relations Relations of an unpacked list of elements from largest to smallest.
   */
  function getRates(address rateFeedID)
    external
    view
    returns (
      address[] memory,
      uint256[] memory,
      SortedLinkedListWithMedian.MedianRelation[] memory
    )
  {
    return rates[rateFeedID].getElements();
  }

  /**
   * @notice Returns the number of timestamps.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @return The number of oracle report timestamps for `rateFeedID`.
   */
  function numTimestamps(address rateFeedID) public view returns (uint256) {
    return timestamps[rateFeedID].getNumElements();
  }

  /**
   * @notice Returns the median timestamp.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @return The median report timestamp for `rateFeedID`.
   */
  function medianTimestamp(address rateFeedID) external view returns (uint256) {
    return timestamps[rateFeedID].getMedianValue();
  }

  /**
   * @notice Gets all elements from the doubly linked list.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @return keys Keys of nn unpacked list of elements from largest to smallest.
   * @return values Values of an unpacked list of elements from largest to smallest.
   * @return relations Relations of an unpacked list of elements from largest to smallest.
   */
  function getTimestamps(address rateFeedID)
    external
    view
    returns (
      address[] memory,
      uint256[] memory,
      SortedLinkedListWithMedian.MedianRelation[] memory
    )
  {
    return timestamps[rateFeedID].getElements();
  }

  /**
   * @notice Returns whether a report exists on rateFeedID from oracle.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @param oracle The oracle whose report should be checked.
   */
  function reportExists(address rateFeedID, address oracle) internal view returns (bool) {
    return rates[rateFeedID].contains(oracle) && timestamps[rateFeedID].contains(oracle);
  }

  /**
   * @notice Returns the list of oracles for a particular rateFeedID.
   * @param rateFeedID The address of the rateFeedID whose oracles should be returned.
   * @return The list of oracles for a particular rateFeedID.
   */
  function getOracles(address rateFeedID) external view returns (address[] memory) {
    return oracles[rateFeedID];
  }

  /**
   * @notice Returns the expiry for the rateFeedID if exists, if not the default.
   * @param rateFeedID The address of the rateFeedID.
   * @return The report expiry in seconds.
   */
  function getRateFeedReportExpirySeconds(address rateFeedID) public view returns (uint256) {
    if (rateFeedReportExpirySeconds[rateFeedID] == 0) {
      return reportExpirySeconds;
    }

    return rateFeedReportExpirySeconds[rateFeedID];
  }

  /**
   * @notice Removes an oracle value and updates the median.
   * @param rateFeedID The address of the rateFeedID for which the CELO exchange rate is being reported.
   * @param oracle The oracle whose value should be removed.
   * @dev This can be used to delete elements for oracles that have been removed.
   * However, a > 1 elements reports list should always be maintained
   */
  function removeReport(address rateFeedID, address oracle) private {
    if (numTimestamps(rateFeedID) == 1 && reportExists(rateFeedID, oracle)) return;
    uint256 originalMedian = rates[rateFeedID].getMedianValue();
    rates[rateFeedID].remove(oracle);
    timestamps[rateFeedID].remove(oracle);
    emit OracleReportRemoved(rateFeedID, oracle);
    uint256 newMedian = rates[rateFeedID].getMedianValue();
    if (newMedian != originalMedian) {
      previousMedianRate[rateFeedID] = newMedian;
      emit MedianUpdated(rateFeedID, newMedian);
    }
  }
}
