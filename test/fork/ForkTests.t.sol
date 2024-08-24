// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, max-line-length
pragma solidity ^0.8;
/**
@dev Fork tests for Mento!
This test suite tests invariantes on a fork of a live Mento environemnts.

Thare are two types of tests contracts:
- ChainForkTests: Tests that are specific to the chain, such as the number of exchanges, the number of collateral assets, etc. 
- ExchangeForkTests: Tests that are specific to the exchange, such as trading limits, swaps, etc.

To make it easier to debug and develop, we have one ChainForkTest for each chain (Alfajores, Celo) and 
one ExchangeForkTest for each (exchange provider, exchange) pair.

The ChainFork tests are instantiated with:
- Chain ID.
- Expected number of exchange providers.
- Expected number of exchanges per exchange provider.
If any of this assertions fail then the ChainTest will fail and that's the queue to update this file
and add additional ExchangeForkTests.

The ExchangeForkTests are instantiated with:
- Chain ID.
- Exchange Provider Index.
- Exchange Index.

And the naming convetion for them is:
${ChainName}_P${ExchangeProviderIndex}E${ExchangeIndex}_ExchangeForkTest
e.g. Alfajores_P0E00_ExchangeForkTest (Alfajores, Exchange Provider 0, Exchange 0)
The Exchange Index is 0 padded to make them align nicely in the file, exchange provider counts shouldn't
exceed 10, if they do, then we need to update the naming convention.
*/

import { uints } from "mento-std/Array.sol";
import { ChainForkTest } from "./ChainForkTest.sol";
import { ExchangeForkTest } from "./ExchangeForkTest.sol";
import { CELO_ID, ALFAJORES_ID } from "mento-std/Constants.sol";

contract Alfajores_ChainForkTest is ChainForkTest(ALFAJORES_ID, 1, uints(14)) {}

contract Alfajores_P0E00_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 0) {}

contract Alfajores_P0E01_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 1) {}

contract Alfajores_P0E02_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 2) {}

contract Alfajores_P0E03_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 3) {}

contract Alfajores_P0E04_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 4) {}

contract Alfajores_P0E05_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 5) {}

contract Alfajores_P0E06_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 6) {}

contract Alfajores_P0E07_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 7) {}

contract Alfajores_P0E08_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 8) {}

contract Alfajores_P0E09_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 9) {}

contract Alfajores_P0E10_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 10) {}

contract Alfajores_P0E11_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 11) {}

contract Alfajores_P0E12_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 12) {}

contract Alfajores_P0E13_ExchangeForkTest is ExchangeForkTest(ALFAJORES_ID, 0, 13) {}

contract Celo_ChainForkTest is ChainForkTest(CELO_ID, 1, uints(14)) {}

contract Celo_P0E00_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 0) {}

contract Celo_P0E01_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 1) {}

contract Celo_P0E02_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 2) {}

contract Celo_P0E03_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 3) {}

contract Celo_P0E04_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 4) {}

contract Celo_P0E05_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 5) {}

contract Celo_P0E06_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 6) {}

contract Celo_P0E07_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 7) {}

contract Celo_P0E08_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 8) {}

contract Celo_P0E09_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 9) {}

contract Celo_P0E10_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 10) {}

contract Celo_P0E11_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 11) {}

contract Celo_P0E12_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 12) {}

contract Celo_P0E13_ExchangeForkTest is ExchangeForkTest(CELO_ID, 0, 13) {}
