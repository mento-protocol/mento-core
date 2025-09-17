// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { IFactoryRegistry } from "../interfaces/IFactoryRegistry.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/// @title Protocol Factory Registry
/// @author Modified from Carter Carlson (@pegahcarter)
/// @notice Protocol Factory Registry to swap and create gauges
contract FactoryRegistry is IFactoryRegistry, OwnableUpgradeable {
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @dev The protocol will always have a usable poolFactory.
  address public fallbackPoolFactory;

  /// @dev Array of poolFactories used to create a gauge and votingRewards
  EnumerableSet.AddressSet private _poolFactories;

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

  /// @notice Initialize the registry with a fallback pool factory (auto-approved).
  /// @param fallbackFactory Address of the fallback pool factory
  /// @param governance Address of the governance (which will be the owner of this instance)
  function initialize(address fallbackFactory, address governance) external initializer {
    if (fallbackFactory == address(0)) revert ZeroAddress();

    __Ownable_init();
    transferOwnership(governance);

    fallbackPoolFactory = fallbackFactory;
    _poolFactories.add(fallbackFactory);
    emit Approve(fallbackFactory);
  }

  /// @inheritdoc IFactoryRegistry
  function approve(address poolFactory) public onlyOwner {
    if (poolFactory == address(0)) revert ZeroAddress();
    if (_poolFactories.contains(poolFactory)) revert PathAlreadyApproved();

    _poolFactories.add(poolFactory);
    emit Approve(poolFactory);
  }

  /// @inheritdoc IFactoryRegistry
  function unapprove(address poolFactory) external onlyOwner {
    if (poolFactory == fallbackPoolFactory) revert FallbackFactory();
    if (!_poolFactories.contains(poolFactory)) revert PathNotApproved();

    _poolFactories.remove(poolFactory);
    emit Unapprove(poolFactory);
  }

  /// @inheritdoc IFactoryRegistry
  function poolFactories() external view returns (address[] memory) {
    return _poolFactories.values();
  }

  /// @inheritdoc IFactoryRegistry
  function isPoolFactoryApproved(address poolFactory) external view returns (bool) {
    return _poolFactories.contains(poolFactory);
  }

  /// @inheritdoc IFactoryRegistry
  function poolFactoriesLength() external view returns (uint256) {
    return _poolFactories.length();
  }
}
