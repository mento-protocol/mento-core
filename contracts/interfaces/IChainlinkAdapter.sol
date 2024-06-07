// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.8.19;

interface IChainlinkAdapter {
    function token() external returns (address);
    function sortedOracles() external returns (address);
    function aggregator() external returns (address);
    function relay() external;
}
