// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { addresses, uints } from "mento-std/Array.sol";
import { Test } from "mento-std/Test.sol";

import { StableTokenV3 } from "contracts/tokens/StableTokenV3.sol";

contract StableTokenV3Test is Test {
  event Transfer(address indexed from, address indexed to, uint256 value);
  event MinterUpdated(address indexed minter, bool isMinter);
  event BurnerUpdated(address indexed burner, bool isBurner);
  event OperatorUpdated(address indexed operator, bool isOperator);

  bytes32 private constant _PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
  bytes32 private constant _TYPE_HASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  bytes32 private _HASHED_NAME;
  bytes32 private _HASHED_VERSION;

  address holder0 = makeAddr("holder0");
  address holder1 = makeAddr("holder1");
  address holder2 = makeAddr("holder2");
  uint256 holder2Pk = uint256(0x31337);

  address validators = makeAddr("validators");
  address borrowerOperations = makeAddr("borrowerOperations");
  address activePool = makeAddr("activePool");
  address collateralRegistry = makeAddr("collateralRegistry");
  address troveManager = makeAddr("troveManager");
  address stabilityPool1 = makeAddr("stabilityPool1");
  address stabilityPool2 = makeAddr("stabilityPool2");

  address feeRecipient = makeAddr("feeRecipient");
  address gatewayFeeRecipient = makeAddr("gatewayFeeRecipient");
  address communityFund = makeAddr("communityFund");

  StableTokenV3 private token;

  function setUp() public {
    holder2 = vm.addr(holder2Pk);

    _HASHED_NAME = keccak256(bytes("cUSD"));
    _HASHED_VERSION = keccak256(bytes("1"));

    address[] memory minters = new address[](3);
    minters[0] = validators;
    minters[1] = borrowerOperations;
    minters[2] = activePool;

    address[] memory burners = new address[](4);
    burners[0] = collateralRegistry;
    burners[1] = borrowerOperations;
    burners[2] = troveManager;
    burners[3] = stabilityPool1;

    address[] memory operators = new address[](2);
    operators[0] = stabilityPool1;
    operators[1] = stabilityPool2;

    token = new StableTokenV3(false);
    token.initialize(
      "cUSD",
      "cUSD",
      address(this),
      addresses(holder0, holder1, holder2, validators, borrowerOperations, activePool, troveManager, stabilityPool1),
      uints(1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000),
      minters,
      burners,
      operators
    );

    assertEq(token.isMinter(validators), true);
    assertEq(token.isMinter(borrowerOperations), true);
    assertEq(token.isMinter(activePool), true);
    assertEq(token.isBurner(collateralRegistry), true);
    assertEq(token.isBurner(borrowerOperations), true);
    assertEq(token.isBurner(troveManager), true);
    assertEq(token.isBurner(stabilityPool1), true);
    assertEq(token.isOperator(stabilityPool1), true);
    assertEq(token.isOperator(stabilityPool2), true);
    bytes32 slot0 = vm.load(address(token), bytes32(0));
    uint8 initialized = uint8(uint256(slot0) >> 160);
    assertEq(initialized, 3);
  }

  function mintAndAssert(address minter, address to, uint256 value) public {
    uint256 balanceBefore = token.balanceOf(to);
    vm.prank(minter);
    token.mint(to, value);
    assertEq(token.balanceOf(to), balanceBefore + value);
  }

  function test_initializers_disabled() public {
    StableTokenV3 disabledToken = new StableTokenV3(true);

    address[] memory initialAddresses = new address[](0);
    uint256[] memory initialBalances = new uint256[](0);
    address[] memory minters = new address[](0);
    address[] memory burners = new address[](0);
    address[] memory operators = new address[](0);

    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    disabledToken.initialize(
      "cUSD",
      "cUSD",
      address(this),
      initialAddresses,
      initialBalances,
      minters,
      burners,
      operators
    );

    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    token.initializeV3(minters, burners, operators);
  }

  function test_setOperator_whenCalledByOwner_shouldSetOperatorAndEmitEvent() public {
    address newOperator = makeAddr("newOperator");
    vm.expectEmit(true, true, true, true);
    emit OperatorUpdated(newOperator, true);
    token.setOperator(newOperator, true);
    assertEq(token.isOperator(newOperator), true);

    vm.expectEmit(true, true, true, true);
    emit OperatorUpdated(newOperator, false);
    token.setOperator(newOperator, false);
    assertEq(token.isOperator(newOperator), false);
  }

  function test_setOperator_whenCalledByNotOwner_shouldRevert() public {
    address newOperator = makeAddr("newOperator");
    vm.prank(holder0);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    token.setOperator(newOperator, true);
  }

  function test_setMinter_whenCalledByOwner_shouldSetMinterAndEmitEvent() public {
    address newMinter = makeAddr("newMinter");
    vm.expectEmit(true, true, true, true);
    emit MinterUpdated(newMinter, true);
    token.setMinter(newMinter, true);
    assertEq(token.isMinter(newMinter), true);

    vm.expectEmit(true, true, true, true);
    emit MinterUpdated(newMinter, false);
    token.setMinter(newMinter, false);
    assertEq(token.isMinter(newMinter), false);
  }

  function test_setMinter_whenCalledByNotOwner_shouldRevert() public {
    address newMinter = makeAddr("newMinter");
    vm.prank(holder0);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    token.setMinter(newMinter, true);
  }

  function test_setBurner_whenCalledByOwner_shouldSetBurnerAndEmitEvent() public {
    address newBurner = makeAddr("newBurner");
    vm.expectEmit(true, true, true, true);
    emit BurnerUpdated(newBurner, true);
    token.setBurner(newBurner, true);
    assertEq(token.isBurner(newBurner), true);

    vm.expectEmit(true, true, true, true);
    emit BurnerUpdated(newBurner, false);
    token.setBurner(newBurner, false);
    assertEq(token.isBurner(newBurner), false);
  }

  function test_setBurner_whenCalledByNotOwner_shouldRevert() public {
    address newBurner = makeAddr("newBurner");
    vm.prank(holder0);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    token.setBurner(newBurner, true);
  }

  function test_mint_whenCalledByMinter_shouldMintTokens() public {
    mintAndAssert(validators, holder0, 100);
  }

  function test_mint_whenSenderIsNotAuthorized_shouldRevert() public {
    vm.prank(holder0);
    vm.expectRevert(bytes("StableTokenV3: not allowed to mint"));
    token.mint(holder0, 100);
  }

  function test_burn_whenCalledByBurner_shouldBurnTokens() public {
    vm.prank(stabilityPool1);
    token.burn(100);
    assertEq(900, token.balanceOf(stabilityPool1));
  }

  function test_burn_whenSenderIsNotAuthorized_shouldRevert() public {
    vm.prank(holder0);
    vm.expectRevert(bytes("StableTokenV3: not allowed to burn"));
    token.burn(100);
  }

  function test_sendToPool_whenCalledByOperator_shouldTransferTokens() public {
    uint256 balanceBefore = token.balanceOf(holder0);
    uint256 balanceBeforeStabilityPool = token.balanceOf(stabilityPool1);
    assertEq(token.allowance(holder0, stabilityPool1), 0);

    vm.prank(stabilityPool1);
    token.sendToPool(holder0, stabilityPool1, 100);
    assertEq(balanceBefore - 100, token.balanceOf(holder0));
    assertEq(balanceBeforeStabilityPool + 100, token.balanceOf(stabilityPool1));
  }

  function test_sendToPool_whenCalledByNonOperator_shouldRevert() public {
    vm.prank(holder0);
    vm.expectRevert("StableTokenV3: not allowed to call only by operator");
    token.sendToPool(holder0, stabilityPool1, 100);
  }

  function test_returnFromPool_whenCalledByStabilityPool_shouldTransferTokens() public {
    uint256 balanceBefore = token.balanceOf(holder0);
    uint256 balanceBeforeStabilityPool = token.balanceOf(stabilityPool1);
    assertEq(token.allowance(stabilityPool1, holder0), 0);

    vm.prank(stabilityPool1);
    token.returnFromPool(stabilityPool1, holder0, 100);
    assertEq(balanceBefore + 100, token.balanceOf(holder0));
    assertEq(balanceBeforeStabilityPool - 100, token.balanceOf(stabilityPool1));
  }

  function test_returnFromPool_whenCalledByNonOperator_shouldRevert() public {
    vm.prank(holder0);
    vm.expectRevert("StableTokenV3: not allowed to call only by operator");
    token.returnFromPool(stabilityPool1, holder0, 100);
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

    assertEq(token.balanceOf(holder0), 1000 - amount);
  }

  function test_creditGasFees_whenCallerNotVM_shouldRevert() public {
    vm.expectRevert("Only VM can call");
    token.creditGasFees(holder0, feeRecipient, gatewayFeeRecipient, communityFund, 25, 25, 25, 25);
  }

  function test_creditGasFees_whenCalledByVm_shouldCreditFees() public {
    uint256 refund = 20;
    uint256 tipTxFee = 30;
    uint256 baseTxFee = 40;
    uint256 tokenSupplyBefore = token.totalSupply();

    vm.prank(address(0));
    token.creditGasFees(
      holder0,
      feeRecipient,
      address(0), // gatewayFeeRecipient will always be 0
      communityFund,
      refund,
      tipTxFee,
      0, // gatewayFee will always be 0
      baseTxFee
    );

    assertEq(token.balanceOf(holder0), 1000 + refund);
    assertEq(token.balanceOf(feeRecipient), tipTxFee);
    assertEq(token.balanceOf(communityFund), baseTxFee);
    assertEq(token.totalSupply(), tokenSupplyBefore + refund + tipTxFee + baseTxFee);
  }

  function test_creditGasFees_whenCalledByVm_withMultiple0Amounts_shouldReturnFeesToHolder0() public {
    uint256 refund = 20;
    uint256 holder0InitialBalance = token.balanceOf(holder0);
    uint256 tokenSupplyBefore0 = token.totalSupply();

    vm.prank(address(0));
    token.creditGasFees(holder0, feeRecipient, gatewayFeeRecipient, communityFund, refund, 0, 0, 0);

    assertEq(token.balanceOf(holder0), holder0InitialBalance + refund);
    assertEq(token.balanceOf(feeRecipient), 0);
    assertEq(token.balanceOf(gatewayFeeRecipient), 0);
    assertEq(token.balanceOf(communityFund), 0);
    assertEq(token.totalSupply(), tokenSupplyBefore0 + refund);
  }

  function test_creditGasFees_whenCalledByVm_withAllZeroAmounts_shouldNotChangeBalances() public {
    uint256 holder0InitialBalance = token.balanceOf(holder0);
    uint256 tokenSupplyBefore = token.totalSupply();

    vm.prank(address(0));
    token.creditGasFees(holder0, feeRecipient, gatewayFeeRecipient, communityFund, 0, 0, 0, 0);

    assertEq(token.balanceOf(holder0), holder0InitialBalance);
    assertEq(token.balanceOf(feeRecipient), 0);
    assertEq(token.balanceOf(gatewayFeeRecipient), 0);
    assertEq(token.balanceOf(communityFund), 0);
    assertEq(token.totalSupply(), tokenSupplyBefore);
  }

  function test_creditGasFees_whenCalledByVm_withOnlyTipTxFee_shouldCreditOnlyFeeRecipient() public {
    uint256 tipTxFee = 50;
    uint256 tokenSupplyBefore = token.totalSupply();

    vm.prank(address(0));
    token.creditGasFees(holder0, feeRecipient, gatewayFeeRecipient, communityFund, 0, tipTxFee, 0, 0);

    assertEq(token.balanceOf(holder0), 1000);
    assertEq(token.balanceOf(feeRecipient), tipTxFee);
    assertEq(token.balanceOf(gatewayFeeRecipient), 0);
    assertEq(token.balanceOf(communityFund), 0);
    assertEq(token.totalSupply(), tokenSupplyBefore + tipTxFee);
  }

  function test_creditGasFees_whenCalledByVm_withOnlyBaseTxFee_shouldCreditOnlyCommunityFund() public {
    uint256 baseTxFee = 60;
    uint256 tokenSupplyBefore = token.totalSupply();

    vm.prank(address(0));
    token.creditGasFees(holder0, feeRecipient, gatewayFeeRecipient, communityFund, 0, 0, 0, baseTxFee);

    assertEq(token.balanceOf(holder0), 1000);
    assertEq(token.balanceOf(feeRecipient), 0);
    assertEq(token.balanceOf(gatewayFeeRecipient), 0);
    assertEq(token.balanceOf(communityFund), baseTxFee);
    assertEq(token.totalSupply(), tokenSupplyBefore + baseTxFee);
  }

  function test_creditGasFees_whenCalledByVm_withGatewayFee_shouldIgnoreGatewayFee() public {
    uint256 refund = 10;
    uint256 tipTxFee = 20;
    uint256 gatewayFee = 100; // This should be ignored even if it's not 0
    uint256 baseTxFee = 30;
    uint256 tokenSupplyBefore = token.totalSupply();

    vm.prank(address(0));
    token.creditGasFees(
      holder0,
      feeRecipient,
      address(0), // gatewayFeeRecipient
      communityFund,
      refund,
      tipTxFee,
      gatewayFee,
      baseTxFee
    );

    assertEq(token.balanceOf(holder0), 1000 + refund);
    assertEq(token.balanceOf(feeRecipient), tipTxFee);
    assertEq(token.balanceOf(communityFund), baseTxFee);
    // Gateway fee is ignored, so total supply should increase by refund + tipTxFee + baseTxFee only
    assertEq(token.totalSupply(), tokenSupplyBefore + refund + tipTxFee + baseTxFee);
  }

  function test_creditGasFeesArray_whenCallerNotVM_shouldRevert() public {
    address[] memory recipients = new address[](1);
    recipients[0] = holder0;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 100;

    vm.expectRevert("Only VM can call");
    token.creditGasFees(recipients, amounts);
  }

  function test_creditGasFeesArray_whenCalledByVm_withSingleRecipient_shouldCreditCorrectly() public {
    address[] memory recipients = new address[](1);
    recipients[0] = holder0;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 100;
    uint256 tokenSupplyBefore = token.totalSupply();

    vm.prank(address(0));
    token.creditGasFees(recipients, amounts);

    assertEq(token.balanceOf(holder0), 1000 + 100);
    assertEq(token.totalSupply(), tokenSupplyBefore + 100);
  }

  function test_creditGasFeesArray_whenCalledByVm_withMultipleRecipients_shouldCreditCorrectly() public {
    address[] memory recipients = new address[](3);
    recipients[0] = holder0;
    recipients[1] = feeRecipient;
    recipients[2] = communityFund;
    uint256[] memory amounts = new uint256[](3);
    amounts[0] = 50;
    amounts[1] = 100;
    amounts[2] = 150;
    uint256 tokenSupplyBefore = token.totalSupply();

    vm.prank(address(0));
    token.creditGasFees(recipients, amounts);

    assertEq(token.balanceOf(holder0), 1000 + 50);
    assertEq(token.balanceOf(feeRecipient), 100);
    assertEq(token.balanceOf(communityFund), 150);
    assertEq(token.totalSupply(), tokenSupplyBefore + 50 + 100 + 150);
  }

  function test_creditGasFeesArray_whenCalledByVm_withEmptyArrays_shouldDoNothing() public {
    address[] memory recipients = new address[](0);
    uint256[] memory amounts = new uint256[](0);
    uint256 tokenSupplyBefore = token.totalSupply();

    vm.prank(address(0));
    token.creditGasFees(recipients, amounts);

    assertEq(token.totalSupply(), tokenSupplyBefore);
  }

  function test_creditGasFeesArray_whenCalledByVm_withMismatchedArrayLengths_shouldRevert() public {
    address[] memory recipients = new address[](2);
    recipients[0] = holder0;
    recipients[1] = holder1;
    uint256[] memory amounts = new uint256[](3);
    amounts[0] = 50;
    amounts[1] = 100;
    amounts[2] = 150;

    vm.prank(address(0));
    vm.expectRevert("StableTokenV3: recipients and amounts must be the same length.");
    token.creditGasFees(recipients, amounts);
  }

  function test_creditGasFeesArray_whenCalledByVm_withZeroAmounts_shouldnotRevert() public {
    address[] memory recipients = new address[](2);
    recipients[0] = holder0;
    recipients[1] = holder1;
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 0;
    amounts[1] = 0;
    uint256 holder0BalanceBefore = token.balanceOf(holder0);
    uint256 holder1BalanceBefore = token.balanceOf(holder1);
    uint256 tokenSupplyBefore = token.totalSupply();

    vm.prank(address(0));
    token.creditGasFees(recipients, amounts);

    assertEq(token.balanceOf(holder0), holder0BalanceBefore);
    assertEq(token.balanceOf(holder1), holder1BalanceBefore);
    assertEq(token.totalSupply(), tokenSupplyBefore);
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
