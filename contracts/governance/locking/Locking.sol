// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import "./interfaces/INextVersionLock.sol";
import "./LockingBase.sol";
import "./LockingRelock.sol";
import "./LockingVotes.sol";
import "./interfaces/ILocking.sol";

/**
 * @title Locking
 * @notice Implements locking mechanism for tokens to enable voting power accumulation
 * @notice https://github.com/rarible/locking-contracts/tree/4f189a96b3e85602dedfbaf69d9a1f5056d835eb
 */
contract Locking is ILocking, LockingBase, LockingRelock, LockingVotes {
  using LibBrokenLine for LibBrokenLine.BrokenLine;

  /**
   * @notice Initializes the locking contract.
   * @dev Sets up the base locking parameters and initializes ownership and context setup.
   * @param _token Address of the ERC20 that will be locked. (Mento Token)
   * @param _startingPointWeek Origin week no for the week-based time system.
   * @param _minCliffPeriod Minimum cliff period for locks.
   * @param _minSlopePeriod Minimum slope period for locks.
   */
  function __Locking_init(
    IERC20Upgradeable _token,
    uint32 _startingPointWeek,
    uint32 _minCliffPeriod,
    uint32 _minSlopePeriod
  ) external initializer {
    __LockingBase_init_unchained(_token, _startingPointWeek, _minCliffPeriod, _minSlopePeriod);
    __Ownable_init_unchained();
    __Context_init_unchained();
  }

  /**
   * @notice Stops the locking functionality.
   * @dev Can only be called by the owner.
   */
  function stop() external onlyOwner notStopped {
    stopped = true;
    emit StopLocking(msg.sender);
  }

  /**
   * @notice Restarts the locking functionality after it has been stopped.
   * @dev Can only be called by the owner.
   */
  function start() external onlyOwner isStopped {
    stopped = false;
    emit StartLocking(msg.sender);
  }

  /**
   * @notice Begins the migration process to a new contract.
   * @param to Address of the new contract where future operations will be migrated.
   * @dev Can only be called by the owner.
   */
  function startMigration(address to) external onlyOwner {
    // slither-disable-next-line missing-zero-check
    migrateTo = to;
    emit StartMigration(msg.sender, to);
  }

  /**
   * @notice Locks a specified amount of tokens for a given period.
   * @param account Account for which tokens are being locked.
   * @param _delegate Address that will receive the voting power from the locked tokens.
   * If address(0) passed, voting power will be lost.
   * @param amount Amount of tokens to lock.
   * @param slopePeriod Period over which the tokens will unlock.
   * @param cliff Initial period during which tokens remain locked and do not start unlocking.
   * @return Id for the created lock.
   */
  function lock(
    address account,
    address _delegate,
    uint96 amount,
    uint32 slopePeriod,
    uint32 cliff
  ) external override notStopped notMigrating returns (uint256) {
    require(amount > 0, "zero amount");
    require(cliff <= MAX_CLIFF_PERIOD, "cliff too big");
    require(slopePeriod <= MAX_SLOPE_PERIOD, "period too big");

    counter++;

    uint32 currentBlock = getBlockNumber();
    uint32 time = roundTimestamp(currentBlock);
    addLines(account, _delegate, amount, slopePeriod, cliff, time, currentBlock);
    accounts[account].amount = accounts[account].amount + (amount);

    // slither-disable-next-line reentrancy-events
    require(token.transferFrom(msg.sender, address(this), amount), "transfer failed");

    emit LockCreate(counter, account, _delegate, time, amount, slopePeriod, cliff);
    return counter;
  }

  /**
   * @notice Withdraws available tokens for the caller.
   */
  function withdraw() external {
    uint96 value = getAvailableForWithdraw(msg.sender);
    if (value > 0) {
      accounts[msg.sender].amount = accounts[msg.sender].amount - (value);
      // slither-disable-next-line reentrancy-events
      require(token.transfer(msg.sender, value), "transfer failed");
    }
    emit Withdraw(msg.sender, value);
  }

  /**
   * @notice Calculates the amount available for withdrawal by an account.
   * @param account The account to check the withdrawable amount for.
   * @return The amount of tokens available for withdrawal.
   */
  function getAvailableForWithdraw(address account) public view returns (uint96) {
    uint96 value = accounts[account].amount;
    if (!stopped) {
      uint32 currentBlock = getBlockNumber();
      uint32 time = roundTimestamp(currentBlock);
      uint96 bias = accounts[account].locked.actualValue(time, currentBlock);
      value = value - (bias);
    }
    return value;
  }

  /**
   * @notice Returns the total amount of tokens locked for an account.
   * @param account The account to check locked amount for.
   * @return The total locked amount.
   */
  function locked(address account) external view returns (uint256) {
    return accounts[account].amount;
  }

  /**
   * @notice Retrieves the account and delegate associated with a given lock ID.
   * @param id The id of the lock.
   * @return _account The account that owns the lock.
   * @return _delegate The account owns the voting power.
   */
  function getAccountAndDelegate(uint256 id) external view returns (address _account, address _delegate) {
    _account = locks[id].account;
    _delegate = locks[id].delegate;
  }

  /**
   * @notice Returns "current week" of the contract.
   */
  function getWeek() external view returns (uint256) {
    return roundTimestamp(getBlockNumber());
  }

  /**
   * @notice Changes the delegate for a specific lock.
   * @param id The unique identifier for the lock whose delegate is to be changed.
   * @param newDelegate The address to which the delegation will be transferred.
   * @dev Updates the delegation and adjusts the voting power accordingly.
   */
  function delegateTo(uint256 id, address newDelegate) external notStopped notMigrating {
    address account = verifyLockOwner(id);
    address _delegate = locks[id].delegate;
    uint32 currentBlock = getBlockNumber();
    uint32 time = roundTimestamp(currentBlock);
    accounts[_delegate].balance.update(time);
    (uint96 bias, uint96 slope, uint32 cliff) = accounts[_delegate].balance.remove(id, time, currentBlock);
    LibBrokenLine.Line memory line = LibBrokenLine.Line(time, bias, slope, cliff);
    accounts[newDelegate].balance.update(time);
    accounts[newDelegate].balance.addOneLine(id, line, currentBlock);
    locks[id].delegate = newDelegate;
    emit Delegate(id, account, newDelegate, time);
  }

  /**
   * @notice Current total supply of veMENTO tokens.
   * @return The total locked supply affecting voting power.
   */
  function totalSupply() external view returns (uint256) {
    if ((totalSupplyLine.initial.bias == 0) || (stopped)) {
      return 0;
    }
    uint32 currentBlock = getBlockNumber();
    uint32 time = roundTimestamp(currentBlock);
    return totalSupplyLine.actualValue(time, currentBlock);
  }

  /**
   * @notice Retrieves the veMENTO balance of an account.
   * @param account The account to check the balance for.
   * @return The balance of veMENTO tokens affecting voting power.
   */
  function balanceOf(address account) external view returns (uint256) {
    if ((accounts[account].balance.initial.bias == 0) || (stopped)) {
      return 0;
    }
    uint32 currentBlock = getBlockNumber();
    uint32 time = roundTimestamp(currentBlock);
    return accounts[account].balance.actualValue(time, currentBlock);
  }

  /**
   * @notice Migrates specified locks to a new contract.
   * @param id An array of lock IDs to be migrated.
   * @dev Performs the migration by transferring locked tokens and updating delegations as necessary.
   */
  function migrate(uint256[] memory id) external {
    if (migrateTo == address(0)) {
      return;
    }
    uint32 currentBlock = getBlockNumber();
    uint32 time = roundTimestamp(currentBlock);
    INextVersionLock nextVersionLock = INextVersionLock(migrateTo);
    for (uint256 i = 0; i < id.length; ++i) {
      address account = verifyLockOwner(id[i]);
      address _delegate = locks[id[i]].delegate;
      updateLines(account, _delegate, time);
      //save data Line before remove
      LibBrokenLine.Line memory line = accounts[account].locked.initiatedLines[id[i]];
      // slither-disable-start unused-return
      (uint96 residue, , ) = accounts[account].locked.remove(id[i], time, currentBlock);

      accounts[account].amount = accounts[account].amount - (residue);

      accounts[_delegate].balance.remove(id[i], time, currentBlock);
      totalSupplyLine.remove(id[i], time, currentBlock);
      // slither-disable-end unused-return
      // slither-disable-start reentrancy-no-eth
      // slither-disable-start reentrancy-events
      // slither-disable-start calls-loop
      nextVersionLock.initiateData(id[i], line, account, _delegate);

      require(token.transfer(migrateTo, residue), "transfer failed");
      // slither-disable-end reentrancy-no-eth
      // slither-disable-end reentrancy-events
      // slither-disable-end calls-loop
    }
    emit Migrate(msg.sender, id);
  }

  /**
   * @notice Returns the name of the token.
   */
  function name() public view virtual returns (string memory) {
    return "Mento Vote-Escrow";
  }

  /**
   * @notice Returns the symbol of the token.
   */
  function symbol() public view virtual returns (string memory) {
    return "veMENTO";
  }

  /**
   * @notice Returns the decimal points of the token.
   */
  function decimals() public view virtual returns (uint8) {
    return 18;
  }

  uint256[50] private __gap;
}
