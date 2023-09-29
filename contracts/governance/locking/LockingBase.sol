// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import "./libs/LibBrokenLine.sol";

import "./interfaces/IVotesUpgradeable.sol";

abstract contract LockingBase is OwnableUpgradeable, IVotesUpgradeable {
  using LibBrokenLine for LibBrokenLine.BrokenLine;

  uint32 public constant WEEK = 50400; //blocks one week = 50400, day = 7200, goerli = 50

  uint32 constant MAX_CLIFF_PERIOD = 103;
  uint32 constant MAX_SLOPE_PERIOD = 104;

  uint32 constant ST_FORMULA_DIVIDER = 1 * (10**8); //stFormula divider          100000000
  uint32 constant ST_FORMULA_CONST_MULTIPLIER = 2 * (10**7); //stFormula const multiplier  20000000
  uint32 constant ST_FORMULA_CLIFF_MULTIPLIER = 8 * (10**7); //stFormula cliff multiplier  80000000
  uint32 constant ST_FORMULA_SLOPE_MULTIPLIER = 4 * (10**7); //stFormula slope multiplier  40000000

  /**
   * @dev ERC20 token to lock
   */
  IERC20Upgradeable public token;
  /**
   * @dev counter for Lock identifiers
   */
  uint256 public counter;

  /**
   * @dev true if contract entered stopped state
   */
  bool public stopped;

  /**
   * @dev address to migrate Locks to (zero if not in migration state)
   */
  address public migrateTo;

  /**
   * @dev minimal cliff period in weeks, minCliffPeriod < MAX_CLIFF_PERIOD
   */

  uint256 public minCliffPeriod;

  /**
   * @dev minimal slope period in weeks, minSlopePeriod < MAX_SLOPE_PERIOD
   */
  uint256 public minSlopePeriod;

  /**
   * @dev locking epoch start in weeks
   */
  uint256 public startingPointWeek;

  /**
   * @dev represents one user Lock
   */
  struct Lock {
    address account;
    address delegate;
  }

  /**
   * @dev describes state of accounts's balance.
   *      balance - broken line describes lock
   *      locked - broken line describes how many tokens are locked
   *      amount - total currently locked tokens (including tokens which can be withdrawed)
   */
  struct AccountOld {
    LibBrokenLine.BrokenLineOld balance;
    LibBrokenLine.BrokenLineOld locked;
    uint256 amount;
  }

  mapping(address => AccountOld) accountsOld;
  mapping(uint256 => Lock) locks;
  LibBrokenLine.BrokenLineOld public totalSupplyLineOld;

  struct Account {
    LibBrokenLine.BrokenLine balance;
    LibBrokenLine.BrokenLine locked;
    uint96 amount;
  }

  mapping(address => Account) accounts;
  LibBrokenLine.BrokenLine public totalSupplyLine;

  /**
   * @dev Emitted when create Lock with parameters (account, delegate, amount, slopePeriod, cliff)
   */
  event LockCreate(
    uint256 indexed id,
    address indexed account,
    address indexed delegate,
    uint256 time,
    uint256 amount,
    uint256 slopePeriod,
    uint256 cliff
  );
  /**
   * @dev Emitted when change Lock parameters (newDelegate, newAmount, newSlopePeriod, newCliff) for Lock with given id
   */
  event Relock(
    uint256 indexed id,
    address indexed account,
    address indexed delegate,
    uint256 counter,
    uint256 time,
    uint256 amount,
    uint256 slopePeriod,
    uint256 cliff
  );
  /**
   * @dev Emitted when to set newDelegate address for Lock with given id
   */
  event Delegate(uint256 indexed id, address indexed account, address indexed delegate, uint256 time);
  /**
   * @dev Emitted when withdraw amount of Rari, account - msg.sender, amount - amount Rari
   */
  event Withdraw(address indexed account, uint256 amount);
  /**
   * @dev Emitted when migrate Locks with given id, account - msg.sender
   */
  event Migrate(address indexed account, uint256[] id);
  /**
   * @dev Stop run contract functions, accept withdraw, account - msg.sender
   */
  event StopLocking(address indexed account);
  /**
   * @dev Start run contract functions, accept withdraw, account - msg.sender
   */
  event StartLocking(address indexed account);
  /**
   * @dev StartMigration initiate migration to another contract, account - msg.sender, to - address delegate to
   */
  event StartMigration(address indexed account, address indexed to);
  /**
   * @dev set newMinCliffPeriod
   */
  event SetMinCliffPeriod(uint256 indexed newMinCliffPeriod);
  /**
   * @dev set newMinSlopePeriod
   */
  event SetMinSlopePeriod(uint256 indexed newMinSlopePeriod);
  /**
   * @dev set startingPointWeek
   */
  event SetStartingPointWeek(uint256 indexed newStartingPointWeek);

  function __LockingBase_init_unchained(
    IERC20Upgradeable _token,
    uint32 _startingPointWeek,
    uint32 _minCliffPeriod,
    uint32 _minSlopePeriod
  ) internal onlyInitializing {
    token = _token;
    startingPointWeek = _startingPointWeek;

    //setting min cliff and slope
    require(_minCliffPeriod <= MAX_CLIFF_PERIOD, "cliff too big");
    require(_minSlopePeriod <= MAX_SLOPE_PERIOD, "period too big");
    minCliffPeriod = _minCliffPeriod;
    minSlopePeriod = _minSlopePeriod;
  }

  function addLines(
    address account,
    address _delegate,
    uint96 amount,
    uint32 slopePeriod,
    uint32 cliff,
    uint32 time,
    uint32 currentBlock
  ) internal {
    require(slopePeriod <= amount, "Wrong value slopePeriod");
    updateLines(account, _delegate, time);
    (uint96 stAmount, uint96 stSlope) = getLock(amount, slopePeriod, cliff);
    LibBrokenLine.Line memory line = LibBrokenLine.Line(time, stAmount, stSlope, cliff);
    totalSupplyLine.addOneLine(counter, line, currentBlock);
    accounts[_delegate].balance.addOneLine(counter, line, currentBlock);
    {
      uint96 slope = divUp(amount, slopePeriod);
      line = LibBrokenLine.Line(time, amount, slope, cliff);
    }
    accounts[account].locked.addOneLine(counter, line, currentBlock);
    locks[counter].account = account;
    locks[counter].delegate = _delegate;
  }

  function updateLines(
    address account,
    address _delegate,
    uint32 time
  ) internal {
    totalSupplyLine.update(time);
    accounts[_delegate].balance.update(time);
    accounts[account].locked.update(time);
  }

  /**
   * Сalculate and return (newAmount, newSlope), using formula:
   * locking = (tokens * (
   *      ST_FORMULA_CONST_MULTIPLIER
   *      + ST_FORMULA_CLIFF_MULTIPLIER * (cliffPeriod - minCliffPeriod))/(MAX_CLIFF_PERIOD - minCliffPeriod)
   *      + ST_FORMULA_SLOPE_MULTIPLIER * (slopePeriod - minSlopePeriod))/(MAX_SLOPE_PERIOD - minSlopePeriod)
   *      )) / ST_FORMULA_DIVIDER
   **/
  function getLock(
    uint96 amount,
    uint32 slopePeriod,
    uint32 cliff
  ) public view returns (uint96 lockAmount, uint96 lockSlope) {
    require(cliff >= minCliffPeriod, "cliff period < minimal lock period");
    require(slopePeriod >= minSlopePeriod, "slope period < minimal lock period");

    uint96 cliffSide = (uint96(cliff - uint32(minCliffPeriod)) * (ST_FORMULA_CLIFF_MULTIPLIER)) /
      (MAX_CLIFF_PERIOD - uint32(minCliffPeriod));
    uint96 slopeSide = (uint96((slopePeriod - uint32(minSlopePeriod))) * (ST_FORMULA_SLOPE_MULTIPLIER)) /
      (MAX_SLOPE_PERIOD - uint32(minSlopePeriod));
    uint96 multiplier = cliffSide + (slopeSide) + (ST_FORMULA_CONST_MULTIPLIER);

    uint256 amountMultiplied = uint256(amount) * uint256(multiplier);
    lockAmount = uint96(amountMultiplied / (ST_FORMULA_DIVIDER));
    lockSlope = divUp(lockAmount, slopePeriod);
  }

  function divUp(uint96 a, uint96 b) internal pure returns (uint96) {
    return ((a - 1) / b) + 1;
  }

  function roundTimestamp(uint32 ts) public view returns (uint32) {
    if (ts < getEpochShift()) {
      return 0;
    }
    uint32 shifted = ts - (getEpochShift());
    return shifted / WEEK - uint32(startingPointWeek);
  }

  /**
   * @notice method returns the amount of blocks to shift locking epoch to.
   * By the time of development, the default weekly-epoch calculated by main-net block number
   * would start at about 11-35 UTC on Tuesday
   * we move it to 00-00 UTC Thursday by adding 10800 blocks (approx)
   */
  function getEpochShift() internal view virtual returns (uint32) {
    return 10800;
  }

  function verifyLockOwner(uint256 id) internal view returns (address account) {
    account = locks[id].account;
    require(account == msg.sender, "caller not a lock owner");
  }

  function getBlockNumber() internal view virtual returns (uint32) {
    return uint32(block.number);
  }

  function setStartingPointWeek(uint32 newStartingPointWeek) public notStopped notMigrating onlyOwner {
    require(newStartingPointWeek < roundTimestamp(getBlockNumber()), "wrong newStartingPointWeek");
    startingPointWeek = newStartingPointWeek;

    emit SetStartingPointWeek(newStartingPointWeek);
  }

  function setMinCliffPeriod(uint32 newMinCliffPeriod) external notStopped notMigrating onlyOwner {
    require(newMinCliffPeriod < MAX_CLIFF_PERIOD, "new cliff period > 2 years");
    minCliffPeriod = newMinCliffPeriod;

    emit SetMinCliffPeriod(newMinCliffPeriod);
  }

  function setMinSlopePeriod(uint32 newMinSlopePeriod) external notStopped notMigrating onlyOwner {
    require(newMinSlopePeriod < MAX_SLOPE_PERIOD, "new slope period > 2 years");
    minSlopePeriod = newMinSlopePeriod;

    emit SetMinSlopePeriod(newMinSlopePeriod);
  }

  /**
        @notice checks if the line is relevant and needs to be copied to the new data structure
     */
  function isRelevant(uint256 id)
    external
    view
    returns (
      bool,
      uint256,
      address,
      uint256,
      address
    )
  {
    uint32 currentBlock = getBlockNumber();
    uint32 currentEpoch = roundTimestamp(currentBlock);

    address delegate = locks[id].delegate;
    LibBrokenLine.LineDataOld storage oldLineBalance = accountsOld[delegate].balance.initiatedLines[id];

    address account = locks[id].account;
    LibBrokenLine.LineDataOld storage oldLineLocked = accountsOld[account].locked.initiatedLines[id];

    //line adds at time start + cliff + slopePeriod + 1(mod)
    uint256 slopeLocked = (oldLineLocked.line.bias / oldLineLocked.line.slope);
    uint256 slopeBalance = (oldLineBalance.line.bias / oldLineBalance.line.slope);
    uint256 slope = slopeLocked > slopeBalance ? slopeLocked : slopeBalance;

    uint256 finishTime = oldLineLocked.line.start + oldLineLocked.cliff + slope + 1;

    return (
      (finishTime < currentEpoch) ? false : true,
      oldLineBalance.line.start,
      delegate,
      oldLineLocked.line.start,
      account
    );
  }

  /**
   * @dev Throws if stopped
   */
  modifier notStopped() {
    require(!stopped, "stopped");
    _;
  }

  /**
   * @dev Throws if not stopped
   */
  modifier isStopped() {
    require(stopped, "not stopped");
    _;
  }

  modifier notMigrating() {
    require(migrateTo == address(0), "migrating");
    _;
  }

  function updateAccountLines(address account, uint32 time) public notStopped notMigrating onlyOwner {
    accounts[account].balance.update(time);
    accounts[account].locked.update(time);
  }

  function updateTotalSupplyLine(uint32 time) public notStopped notMigrating onlyOwner {
    totalSupplyLine.update(time);
  }

  function updateAccountLinesBlockNumber(address account, uint32 blockNumber)
    external
    notStopped
    notMigrating
    onlyOwner
  {
    uint32 time = roundTimestamp(blockNumber);
    updateAccountLines(account, time);
  }

  function updateTotalSupplyLineBlockNumber(uint32 blockNumber) external notStopped notMigrating onlyOwner {
    uint32 time = roundTimestamp(blockNumber);
    updateTotalSupplyLine(time);
  }

  function migrateBalanceLines(uint256[] calldata ids) external onlyOwner {
    uint256 len = ids.length;
    for (uint256 i = 0; i < len; i++) {
      uint256 id = ids[i];
      Lock storage lock = locks[id];
      address user = lock.delegate;
      LibBrokenLine.LineDataOld storage oldLine = accountsOld[user].balance.initiatedLines[id];

      LibBrokenLine.Line memory line = LibBrokenLine.Line({
        start: uint32(oldLine.line.start),
        bias: uint96(oldLine.line.bias),
        slope: uint96(oldLine.line.slope),
        cliff: uint32(oldLine.cliff)
      });

      //adding the line to balance broken line
      accounts[user].balance._addOneLine(id, line);
      //adding the line to totalSupply broken line
      totalSupplyLine._addOneLine(id, line);
    }
  }

  function migrateLockedLines(uint256[] calldata ids) external onlyOwner {
    uint256 len = ids.length;
    for (uint256 i = 0; i < len; i++) {
      uint256 id = ids[i];
      Lock storage lock = locks[id];
      address user = lock.account;
      LibBrokenLine.LineDataOld storage oldLine = accountsOld[user].locked.initiatedLines[id];

      LibBrokenLine.Line memory line = LibBrokenLine.Line({
        start: uint32(oldLine.line.start),
        bias: uint96(oldLine.line.bias),
        slope: uint96(oldLine.line.slope),
        cliff: uint32(oldLine.cliff)
      });

      //adding the line to balance broken line
      accounts[user].locked._addOneLine(id, line);
    }
  }

  function copyAmountMakeSnapshots(address[] calldata users) external onlyOwner {
    uint32 currentBlock = getBlockNumber();
    uint32 currentEpoch = roundTimestamp(currentBlock);
    uint256 len = users.length;
    for (uint256 i = 0; i < len; i++) {
      Account storage newData = accounts[users[i]];
      AccountOld storage oldData = accountsOld[users[i]];

      //copy amount
      newData.amount = uint96(oldData.amount);

      if (newData.balance.initial.bias > 0) {
        newData.balance.update(currentEpoch);
        newData.balance.saveSnapshot(currentEpoch, currentBlock);
      }

      if (newData.locked.initial.bias > 0) {
        newData.locked.update(currentEpoch);
        newData.locked.saveSnapshot(currentEpoch, currentBlock);
      }
    }

    totalSupplyLine.saveSnapshot(currentEpoch, currentBlock);
  }

  //48 => 43 add new accounts and totalSupplyLine
  uint256[43] private __gap;
}
