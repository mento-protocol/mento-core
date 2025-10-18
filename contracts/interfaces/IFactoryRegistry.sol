// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFactoryRegistry {
  error FallbackFactory();
  error PathAlreadyApproved();
  error PathNotApproved();
  error ZeroAddress();

  event Approve(address indexed poolFactory);
  event Unapprove(address indexed poolFactory);

  /// @notice Initialize the registry with a fallback pool factory (auto-approved).
  /// @param fallbackFactory Address of the fallback pool factory
  /// @param governance Address of the governance (which will be the owner of this instance)
  function initialize(address fallbackFactory, address governance) external;

  /// @notice Approve a Pool Factory to be used in the protocol.
  ///         Router.sol is able to swap any poolFactories currently approved.
  ///         Cannot approve an address(0) factory.
  ///         Cannot approve a factory that is already approved.
  /// @dev Callable by onlyOwner
  /// @param poolFactory .
  function approve(address poolFactory) external;

  /// @notice Unapprove a Pool Factory from being used in the Protocol.
  ///         While a poolFactory is unapproved, Router.sol cannot swap with pools made from the corresponding factory
  ///         Can only unapprove an approved factory.
  ///         Cannot unapprove the fallback factory.
  /// @dev Callable by onlyOwner
  /// @param poolFactory .
  function unapprove(address poolFactory) external;

  /// @notice Get all PoolFactories approved by the registry
  /// @dev The same PoolFactory address cannot be used twice
  /// @return Array of PoolFactory addresses
  function poolFactories() external view returns (address[] memory);

  /// @notice Check if a PoolFactory is approved within the factory registry.  Router uses this method to
  ///         ensure a pool swapped from is approved.
  /// @param poolFactory .
  /// @return True if PoolFactory is approved, else false
  function isPoolFactoryApproved(address poolFactory) external view returns (bool);

  /// @notice Get the length of the poolFactories array
  function poolFactoriesLength() external view returns (uint256);
}
