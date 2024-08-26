// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { ChainForkTest } from "./ChainForkTest.sol";
import { ExchangeForkTest } from "./ExchangeForkTest.sol";
import { CELO_ID, BAKLAVA_ID, ALFAJORES_ID } from "mento-std/Constants.sol";

contract BaklavaChainForkTest is ChainForkTest(BAKLAVA_ID, 14) {}

contract BaklavaExchangeForkTest0 is ExchangeForkTest(BAKLAVA_ID, 0) {}

contract BaklavaExchangeForkTest1 is ExchangeForkTest(BAKLAVA_ID, 1) {}

contract BaklavaExchangeForkTest2 is ExchangeForkTest(BAKLAVA_ID, 2) {}

contract BaklavaExchangeForkTest3 is ExchangeForkTest(BAKLAVA_ID, 3) {}

contract BaklavaExchangeForkTest4 is ExchangeForkTest(BAKLAVA_ID, 4) {}

contract BaklavaExchangeForkTest5 is ExchangeForkTest(BAKLAVA_ID, 5) {}

contract BaklavaExchangeForkTest6 is ExchangeForkTest(BAKLAVA_ID, 6) {}

contract BaklavaExchangeForkTest7 is ExchangeForkTest(BAKLAVA_ID, 7) {}

contract BaklavaExchangeForkTest8 is ExchangeForkTest(BAKLAVA_ID, 8) {}

contract BaklavaExchangeForkTest9 is ExchangeForkTest(BAKLAVA_ID, 9) {}

contract BaklavaExchangeForkTest10 is ExchangeForkTest(BAKLAVA_ID, 10) {}

contract BaklavaExchangeForkTest11 is ExchangeForkTest(BAKLAVA_ID, 11) {}

contract BaklavaExchangeForkTest12 is ExchangeForkTest(BAKLAVA_ID, 12) {}

contract BaklavaExchangeForkTest13 is ExchangeForkTest(BAKLAVA_ID, 13) {}

contract AlfajoresChainForkTest is ChainForkTest(ALFAJORES_ID, 14) {}

contract AlfajoresExchangeForkTest0 is ExchangeForkTest(ALFAJORES_ID, 0) {}

contract AlfajoresExchangeForkTest1 is ExchangeForkTest(ALFAJORES_ID, 1) {}

contract AlfajoresExchangeForkTest2 is ExchangeForkTest(ALFAJORES_ID, 2) {}

contract AlfajoresExchangeForkTest3 is ExchangeForkTest(ALFAJORES_ID, 3) {}

contract AlfajoresExchangeForkTest4 is ExchangeForkTest(ALFAJORES_ID, 4) {}

contract AlfajoresExchangeForkTest5 is ExchangeForkTest(ALFAJORES_ID, 5) {}

contract AlfajoresExchangeForkTest6 is ExchangeForkTest(ALFAJORES_ID, 6) {}

contract AlfajoresExchangeForkTest7 is ExchangeForkTest(ALFAJORES_ID, 7) {}

contract AlfajoresExchangeForkTest8 is ExchangeForkTest(ALFAJORES_ID, 8) {}

contract AlfajoresExchangeForkTest9 is ExchangeForkTest(ALFAJORES_ID, 9) {}

contract AlfajoresExchangeForkTest10 is ExchangeForkTest(ALFAJORES_ID, 10) {}

contract AlfajoresExchangeForkTest11 is ExchangeForkTest(ALFAJORES_ID, 11) {}

contract AlfajoresExchangeForkTest12 is ExchangeForkTest(ALFAJORES_ID, 12) {}

contract AlfajoresExchangeForkTest13 is ExchangeForkTest(ALFAJORES_ID, 13) {}

contract CeloChainForkTest is ChainForkTest(CELO_ID, 14) {}

contract CeloExchangeForkTest0 is ExchangeForkTest(CELO_ID, 0) {}

contract CeloExchangeForkTest1 is ExchangeForkTest(CELO_ID, 1) {}

contract CeloExchangeForkTest2 is ExchangeForkTest(CELO_ID, 2) {}

contract CeloExchangeForkTest3 is ExchangeForkTest(CELO_ID, 3) {}

contract CeloExchangeForkTest4 is ExchangeForkTest(CELO_ID, 4) {}

contract CeloExchangeForkTest5 is ExchangeForkTest(CELO_ID, 5) {}

contract CeloExchangeForkTest6 is ExchangeForkTest(CELO_ID, 6) {}

contract CeloExchangeForkTest7 is ExchangeForkTest(CELO_ID, 7) {}

contract CeloExchangeForkTest8 is ExchangeForkTest(CELO_ID, 8) {}

contract CeloExchangeForkTest9 is ExchangeForkTest(CELO_ID, 9) {}

contract CeloExchangeForkTest10 is ExchangeForkTest(CELO_ID, 10) {}

contract CeloExchangeForkTest11 is ExchangeForkTest(CELO_ID, 11) {}

contract CeloExchangeForkTest12 is ExchangeForkTest(CELO_ID, 12) {}

contract CeloExchangeForkTest13 is ExchangeForkTest(CELO_ID, 13) {}
