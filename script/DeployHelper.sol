// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

contract DeployHelper {
  struct MentoConfig {
    address broker;
    address reserve;
    address sortedOracles;
    address exchange;
    address biPoolManager;
    address governance;
    // TODO: Add all core contracts
  }

  constructor() public {}

  /**
   * @notice Helper function to retrieve config for Anvil.
   */
  function getAnvilConfig() internal pure returns (MentoConfig memory contractAddresses) {
    contractAddresses = MentoConfig({
      broker: 0x731a10897d267e19B34503aD902d0A29173Ba4B1,
      reserve: 0x9380fA34Fd9e4Fd14c06305fd7B6199089eD4eb9,
      sortedOracles: 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33,
      exchange: 0x67316300f17f063085Ca8bCa4bd3f7a5a3C66275,
      biPoolManager: 0x731a10897d267e19B34503aD902d0A29173Ba4B1,
      governance: 0xD533Ca259b330c7A88f74E000a3FaEa2d63B7972
    });
  }

  /**
   * @notice Helper function to retrieve config for Baklava.
   */
  function getBaklavaConfig() internal pure returns (MentoConfig memory contractAddresses) {
    contractAddresses = MentoConfig({
      broker: 0x731a10897d267e19B34503aD902d0A29173Ba4B1,
      reserve: 0x9380fA34Fd9e4Fd14c06305fd7B6199089eD4eb9,
      sortedOracles: 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33,
      exchange: 0x67316300f17f063085Ca8bCa4bd3f7a5a3C66275,
      biPoolManager: 0x731a10897d267e19B34503aD902d0A29173Ba4B1,
      governance: 0xD533Ca259b330c7A88f74E000a3FaEa2d63B7972
    });
  }

  /**
   * @notice Helper function to retrieve config for Mainnet.
   */
  function getMainnetConfig() internal pure returns (MentoConfig memory contractAddresses) {
    contractAddresses = MentoConfig({
      broker: 0x731a10897d267e19B34503aD902d0A29173Ba4B1,
      reserve: 0x9380fA34Fd9e4Fd14c06305fd7B6199089eD4eb9,
      sortedOracles: 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33,
      exchange: 0x67316300f17f063085Ca8bCa4bd3f7a5a3C66275,
      biPoolManager: 0x731a10897d267e19B34503aD902d0A29173Ba4B1,
      governance: 0xD533Ca259b330c7A88f74E000a3FaEa2d63B7972
    });
  }
}
