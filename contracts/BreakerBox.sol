pragma solidity ^0.5.13;

import { IBreakerBox } from "./interfaces/IBreakerBox.sol";
import { IBreaker } from "./interfaces/IBreaker.sol";
import { ISortedOracles } from "./interfaces/ISortedOracles.sol";

import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import { AddressLinkedList, LinkedList } from "./common/linkedlists/AddressLinkedList.sol";
import { Initializable } from "./common/Initializable.sol";

/**
 * @title   BreakerBox
 * @notice  The BreakerBox checks the criteria defined in separate breaker contracts
 *          to determine whether or not buying or selling should be allowed for a
 *          specified referenceRateIDs. The contract stores references to all breakers
 *          that hold criteria to be checked, referenceRateIDs that
 *          can make use of the BreakerBox & their current trading.
 */
contract BreakerBox is IBreakerBox, Initializable, Ownable {
  using AddressLinkedList for LinkedList.List;

  /* ==================== State Variables ==================== */

  address[] public referenceRateIDs;
  // Maps reference rate to its current trading mode info.
  mapping(address => TradingModeInfo) public referenceRateTradingModes;
  // Maps a trading mode to the associated breaker.
  mapping(uint64 => address) public tradingModeBreaker;
  // Maps a breaker to the associated trading mode.
  mapping(address => uint64) public breakerTradingMode;
  // Ordered list of breakers to be checked.
  LinkedList.List private breakers;

  // Address of the Mento SortedOracles contract
  ISortedOracles public sortedOracles;

  modifier onlyValidBreaker(address breaker, uint64 tradingMode) {
    require(!isBreaker(breaker), "This breaker has already been added");
    require(tradingModeBreaker[tradingMode] == address(0), "There is already a breaker added with the same trading mode");
    require(tradingMode != 0, "The default trading mode can not have a breaker");
    _;
  }

  /* ==================== Constructor ==================== */

  /**
   * @notice Sets initialized == true on implementation contracts.
   * @param test Set to true to skip implementation initialization.
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @param _referenceRates referenceRateIDs to be added.
   * @param _sortedOracles The address of the Celo sorted oracles contract.
   */
  function initialize(address[] calldata _referenceRates, ISortedOracles _sortedOracles) external initializer {
    _transferOwnership(msg.sender);
    setSortedOracles(_sortedOracles);
    addReferenceRates(_referenceRates);
  }

  /* ==================== Mutative Functions ==================== */
  /**
   * @notice Sets the address of the sortedOracles contract.
   * @param _sortedOracles The new address of the sorted oracles contract.
   */
  function setSortedOracles(ISortedOracles _sortedOracles) public onlyOwner {
    require(address(_sortedOracles) != address(0), "SortedOracles address must be set");
    sortedOracles = _sortedOracles;
    emit SortedOraclesUpdated(address(_sortedOracles));
  }

  /* ==================== Restricted Functions ==================== */

  /* ---------- Breakers ---------- */

  /**
   * @notice Adds a breaker to the end of the list of breakers & the tradingMode-Breaker mapping.
   * @param breaker The address of the breaker to be added.
   * @param tradingMode The trading mode of the breaker to be added.
   */
  function addBreaker(address breaker, uint64 tradingMode) public onlyOwner onlyValidBreaker(breaker, tradingMode) {
    tradingModeBreaker[tradingMode] = breaker;
    breakerTradingMode[breaker] = tradingMode;
    breakers.push(breaker);
    emit BreakerAdded(breaker);
  }

  /**
   * @notice Adds a breaker to the list of breakers at a specified position.
   * @param breaker The address of the breaker to be added.
   * @param tradingMode The trading mode of the breaker to be added.
   * @param prevBreaker The address of the breaker that should come before the new breaker.
   * @param nextBreaker The address of the breaker that should come after the new breaker.
   */
  function insertBreaker(
    address breaker,
    uint64 tradingMode,
    address prevBreaker,
    address nextBreaker
  ) external onlyOwner onlyValidBreaker(breaker, tradingMode) {
    tradingModeBreaker[tradingMode] = breaker;
    breakerTradingMode[breaker] = tradingMode;
    breakers.insert(breaker, prevBreaker, nextBreaker);
    emit BreakerAdded(breaker);
  }

  // changes trading mode for pairs that have this breaker because if its tripped and if we remove it its stuck
  /**
   * @notice Removes the specified breaker from the list of breakers.
   * @param breaker The address of the breaker to be removed.
   * @dev Will set any referenceRateID using this breakers trading mode to the default trading mode.
   */
  function removeBreaker(address breaker) external onlyOwner {
    require(isBreaker(breaker), "This breaker has not been added");

    uint64 tradingMode = breakerTradingMode[breaker];

    // Set any refenceRateIDs using this breakers trading mode to the default mode.
    address[] memory activeReferenceRates = referenceRateIDs;
    TradingModeInfo memory tradingModeInfo;

    for (uint256 i = 0; i < activeReferenceRates.length; i++) {
      tradingModeInfo = referenceRateTradingModes[activeReferenceRates[i]];
      if (tradingModeInfo.tradingMode == tradingMode) {
        setReferenceRateTradingMode(activeReferenceRates[i], 0);
      }
    }

    delete tradingModeBreaker[tradingMode];
    delete breakerTradingMode[breaker];
    breakers.remove(breaker);

    emit BreakerRemoved(breaker);
  }

  /* ---------- referenceRateIDs ---------- */

  /**
   * @notice Adds a referenceRateID to the mapping of monitored referenceRateIDs.
   * @param referenceRateID The address of the referenceRateID to be added.
   */
  function addReferenceRate(address referenceRateID) public onlyOwner {
    TradingModeInfo memory info = referenceRateTradingModes[referenceRateID];
    require(info.lastUpdatedTime == 0, "Reference rate ID has already been added");

    require(sortedOracles.getOracles(referenceRateID).length > 0, "Reference rate does not exist in oracles list");

    info.tradingMode = 0; // Default trading mode (Bi-directional).
    info.lastUpdatedTime = uint64(block.timestamp);
    info.lastUpdatedBlock = uint128(block.number);
    referenceRateTradingModes[referenceRateID] = info;
    referenceRateIDs.push(referenceRateID);

    emit ReferenceRateIDAdded(referenceRateID);
  }

  /**
   * @notice Adds the specified referenceRateIDs to the mapping of monitored referenceRateIDs.
   * @param newReferenceRates The array of referenceRateID addresses to be added.
   */
  function addReferenceRates(address[] memory newReferenceRates) public onlyOwner {
    for (uint256 i = 0; i < newReferenceRates.length; i++) {
      addReferenceRate(newReferenceRates[i]);
    }
  }

  /**
   * @notice Removes a referenceRateID from the mapping of monitored referenceRateIDs.
   * @param referenceRateID The address of the referenceRateID to be removed.
   */
  function removeReferenceRate(address referenceRateID) external onlyOwner {
    uint256 referenceRateIndex;
    for (uint256 i = 0; i < referenceRateIDs.length; i++) {
      if (referenceRateIDs[i] == referenceRateID) {
        referenceRateIndex = i;
        break;
      }
    }

    require(referenceRateIDs[referenceRateIndex] == referenceRateID, "referenceRateID has not been added");

    uint256 lastIndex = referenceRateIDs.length - 1;
    if (referenceRateIndex != lastIndex) {
      referenceRateIDs[referenceRateIndex] = referenceRateIDs[lastIndex];
    }

    referenceRateIDs.pop();

    delete referenceRateTradingModes[referenceRateID];
    emit ReferenceRateIDRemoved(referenceRateID);
  }

  /**
   * @notice Sets the trading mode for the specified referenceRateID.
   * @param referenceRateID The address of the referenceRateID.
   * @param tradingMode The trading mode that should be set.
   */
  function setReferenceRateTradingMode(address referenceRateID, uint64 tradingMode) public onlyOwner {
    require(
      tradingMode == 0 || tradingModeBreaker[tradingMode] != address(0),
      "Trading mode must be default or have a breaker set"
    );

    TradingModeInfo memory info = referenceRateTradingModes[referenceRateID];
    require(info.lastUpdatedTime > 0, "Reference rate ID has not been added");

    info.tradingMode = tradingMode;
    info.lastUpdatedTime = uint64(block.timestamp);
    info.lastUpdatedBlock = uint128(block.number);
    referenceRateTradingModes[referenceRateID] = info;

    emit TradingModeUpdated(referenceRateID, tradingMode);
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Returns an array of breaker addresses from start to end.
   * @return An ordered list of breakers.
   */
  function getBreakers() external view returns (address[] memory) {
    return breakers.getKeys();
  }

  /**
   * @notice Checks whether a breaker with the specifed address has been added.
   */
  function isBreaker(address breaker) public view returns (bool) {
    return breakers.contains(breaker);
  }

  /**
   * @notice Returns addresses of referenceRateIDs that have been added.
   */
  function getReferenceRateIDs() external view returns (address[] memory) {
    return referenceRateIDs;
  }

  /**
   * @notice Returns the trading mode for the specified referenceRateID.
   * @param referenceRateID The address of the referenceRateID to retrieve the trading mode for.
   */
  function getTradingMode(address referenceRateID) external view returns (uint256 tradingMode) {
    TradingModeInfo memory info = referenceRateTradingModes[referenceRateID];
    return info.tradingMode;
  }

  /* ==================== Check Breakers ==================== */

  /**
   * @notice Checks breakers for the referenceRateID with the specified id 
             and sets correct trading mode if any breakers are tripped
             or need to be reset.
   * @param referenceRateID The registryId of the referenceRateID to run checks for.
   */
  function checkAndSetBreakers(address referenceRateID) external {
    TradingModeInfo memory info = referenceRateTradingModes[referenceRateID];

    // This referenceRateID has not been added. So do nothing.
    if (info.lastUpdatedTime == 0) {
      return;
    }

    // Check if a breaker has non default trading mode and reset if we should.
    if (info.tradingMode != 0) {
      IBreaker breaker = IBreaker(tradingModeBreaker[info.tradingMode]);

      uint256 cooldown = breaker.getCooldown();

      // If the cooldown == 0, then a manual reset is required.
      if (((cooldown > 0) && (cooldown + info.lastUpdatedTime) <= block.timestamp)) {
        if (breaker.shouldReset(referenceRateID)) {
          info.tradingMode = 0;
          info.lastUpdatedTime = uint64(block.timestamp);
          info.lastUpdatedBlock = uint128(block.number);
          referenceRateTradingModes[referenceRateID] = info;
          emit ResetSuccessful(referenceRateID, address(breaker));
        } else {
          emit ResetAttemptCriteriaFail(referenceRateID, address(breaker));
          return;
        }
      } else {
        emit ResetAttemptNotCool(referenceRateID, address(breaker));
        return;
      }
    }

    address[] memory _breakers = breakers.getKeys();

    // Check all breakers.
    for (uint256 i = 0; i < _breakers.length; i++) {
      IBreaker breaker = IBreaker(_breakers[i]);
      bool tripBreaker = breaker.shouldTrigger(referenceRateID);
      if (tripBreaker) {
        info.tradingMode = breakerTradingMode[address(breaker)];
        info.lastUpdatedTime = uint64(block.timestamp);
        info.lastUpdatedBlock = uint128(block.number);
        referenceRateTradingModes[referenceRateID] = info;
        emit BreakerTripped(address(breaker), referenceRateID);
      }
    }
  }
}
