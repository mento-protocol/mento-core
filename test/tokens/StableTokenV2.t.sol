// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8.0;

import { console } from "forge-std-next/console.sol";
import { Arrays } from "../utils/Arrays.sol";
import { BaseTest } from "../utils/BaseTest.next.sol";

import { StableTokenV2 } from "contracts/tokens/StableTokenV2.sol";

contract StableTokenV2Test is BaseTest {
  event TransferComment(string comment);

  bytes32 private constant _PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
  bytes32 private constant _TYPE_HASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  bytes32 private _HASHED_NAME;
  bytes32 private _HASHED_VERSION;

  address validators = address(0x1001);
  address broker = address(0x1002);
  address exchange = address(0x1003);

  address holder0 = address(0x2001);
  address holder1 = address(0x2002);
  address holder2;
  uint256 holder2Pk = uint256(0x31337);

  address feeRecipient = address(0x3001);
  address gatewayFeeRecipient = address(0x3002);
  address conmunityFund = address(0x3003);

  StableTokenV2 private token;

  function setUp() public {
    holder2 = vm.addr(holder2Pk);

    _HASHED_NAME = keccak256(bytes("cUSD"));
    _HASHED_VERSION = keccak256(bytes("1"));

    token = new StableTokenV2(false);
    token.initialize(
      "cUSD",
      "cUSD",
      0, // deprecated
      address(0), // deprecated
      0, // deprecated
      0, // deprecated
      Arrays.addresses(holder0, holder1, holder2, broker, exchange),
      Arrays.uints(1000, 1000, 1000, 1000, 1000),
      "" // deprecated
    );
    token.initializeV2(broker, validators, exchange);
  }

  function mintAndAssert(
    address minter,
    address to,
    uint256 value
  ) public {
    uint256 balanceBefore = token.balanceOf(to);
    vm.prank(minter);
    token.mint(to, value);
    assertEq(token.balanceOf(to), balanceBefore + value);
  }

  function test_initializers_disabled() public {
    StableTokenV2 disabledToken = new StableTokenV2(true);

    address[] memory initialAddresses = new address[](0);
    uint256[] memory initialBalances = new uint256[](0);

    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    disabledToken.initialize(
      "cUSD",
      "cUSD",
      0, // deprecated
      address(0), // deprecated
      0, // deprecated
      0, // deprecated
      initialAddresses,
      initialBalances,
      "" // deprecated
    );

    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    token.initializeV2(broker, validators, exchange);
  }

  function test_transferWithComment_shouldEmitCorrectMessage() public {
    vm.expectEmit(true, true, true, true);
    emit TransferComment("Hello World");

    vm.prank(holder0);
    token.transferWithComment(holder1, 100, "Hello World");
  }

  function test_mint_whenCalledByExchange_shouldMintTokens() public {
    mintAndAssert(exchange, holder0, 100);
  }

  function test_mint_whenCalledByValidators_shouldMintTokens() public {
    mintAndAssert(validators, holder0, 100);
  }

  function test_mint_whenCalledByBroker_shouldMintTokens() public {
    mintAndAssert(broker, holder0, 100);
  }

  function test_mint_whenSenderIsNotAuthorized_shouldRevert() public {
    vm.prank(holder0);
    vm.expectRevert(bytes("StableTokenV2: not allowed to mint"));
    token.mint(holder0, 100);
  }

  function test_burn_whenCalledByExchange_shouldBurnTokens() public {
    vm.prank(exchange);
    token.burn(100);
    assertEq(900, token.balanceOf(exchange));
  }

  function test_burn_whenCalledByBroker_shouldBurnTokens() public {
    vm.prank(broker);
    token.burn(100);
    assertEq(900, token.balanceOf(broker));
  }

  function test_burn_whenSenderIsNotAuthorized_shouldRevert() public {
    vm.prank(holder0);
    vm.expectRevert(bytes("StableTokenV2: not allowed to burn"));
    token.burn(100);
  }

  function test_permit_whenSenderPermits_shouldIncreaseAllowance() public {
    uint256 allowanceBefore = token.allowance(holder2, holder0);
    assertEq(0, allowanceBefore);

    uint256 deadline = block.timestamp + 1000;
    bytes32 structHash = buildTypedDataHash(holder2, holder0, 100, deadline);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(holder2Pk, structHash);

    vm.prank(holder0);
    token.permit(holder2, holder0, 100, deadline, v, r, s);
    assertEq(100, token.allowance(holder2, holder0));
  }

  function test_debitGasFees_whenCallerNotVM_shouldRevert() public {
    vm.expectRevert("Only VM can call");
    token.debitGasFees(holder0, 100);
  }

  function test_debitGasFees_whenCallerIsVM_shouldDebitGasFees() public {
    uint256 amount = 100;
    assertEq(token.balanceOf(holder0), 1000);

    vm.prank(address(0));
    token.debitGasFees(holder0, 100);

    assertEq(1000 - amount, token.balanceOf(holder0));
  }

  function test_creditGasFees_whenCallerNotVM_shouldRevert() public {
    vm.expectRevert("Only VM can call");
    token.creditGasFees(holder0, feeRecipient, gatewayFeeRecipient, conmunityFund, 25, 25, 25, 25);
  }

  function test_creditGasFees_whenCalledByVm_shouldCreditFees() public {
    uint256 refund = 25;
    uint256 tipTxFee = 25;
    uint256 gatewayFee = 25;
    uint256 baseTxFee = 25;

    vm.prank(address(0));
    token.creditGasFees(
      holder0,
      feeRecipient,
      gatewayFeeRecipient,
      conmunityFund,
      refund,
      tipTxFee,
      gatewayFee,
      baseTxFee
    );

    assertEq(1000 + refund, token.balanceOf(holder0));
    assertEq(tipTxFee, token.balanceOf(feeRecipient));
    assertEq(gatewayFee, token.balanceOf(gatewayFeeRecipient));
    assertEq(baseTxFee, token.balanceOf(conmunityFund));
  }

  function buildTypedDataHash(
    address owner,
    address spender,
    uint256 amount,
    uint256 deadline
  ) internal view returns (bytes32) {
    uint256 nonce = token.nonces(owner);
    bytes32 digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        keccak256(abi.encode(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION, block.chainid, address(token))),
        keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, amount, nonce, deadline))
      )
    );
    return digest;
  }
}
