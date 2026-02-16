// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { IFPMMCallee } from "contracts/interfaces/IFPMMCallee.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

contract FlashLoanReceiver is IFPMMCallee {
  FPMM public fpmm;
  address public token0;
  address public token1;
  bool public shouldRepay;
  bool public shouldRepayExactAmounts;
  uint256 public repayExactAmount0;
  uint256 public repayExactAmount1;
  uint256 public repayExtra0;
  uint256 public repayExtra1;
  address public sender;
  uint256 public amount0Received;
  uint256 public amount1Received;
  bytes public receivedData;
  bool public shouldRevert;

  constructor(address _fpmm, address _token0, address _token1) {
    fpmm = FPMM(_fpmm);
    token0 = _token0;
    token1 = _token1;
    shouldRepay = true;
    repayExtra0 = 0;
    repayExtra1 = 0;
  }

  function setRepayBehavior(bool _shouldRepay, uint256 _repayExtra0, uint256 _repayExtra1) external {
    shouldRepay = _shouldRepay;
    repayExtra0 = _repayExtra0;
    repayExtra1 = _repayExtra1;
  }

  function setRevertInHook(bool _shouldRevert) external {
    shouldRevert = _shouldRevert;
  }

  function enableRepayExactAmounts(uint256 _repayExactAmount0, uint256 _repayExactAmount1) external {
    shouldRepayExactAmounts = true;
    repayExactAmount0 = _repayExactAmount0;
    repayExactAmount1 = _repayExactAmount1;
  }

  function hook(address _sender, uint256 _amount0, uint256 _amount1, bytes calldata _data) external override {
    require(msg.sender == address(fpmm), "Not called by FPMM");

    // Store received values
    sender = _sender;
    amount0Received = _amount0;
    amount1Received = _amount1;
    receivedData = _data;

    if (shouldRevert) {
      revert("FlashLoanReceiver: Reverting as requested");
    }

    // Repay the flash loan if configured to do so
    if (shouldRepay) {
      if (shouldRepayExactAmounts) {
        repayExactAmounts();
      } else {
        repayWithExtra();
      }
    }
  }

  function repayWithExtra() internal {
    uint256 repayAmount0 = amount0Received + repayExtra0;
    uint256 repayAmount1 = amount1Received + repayExtra1;

    IERC20(token0).transfer(address(fpmm), repayAmount0);
    IERC20(token1).transfer(address(fpmm), repayAmount1);
  }

  function repayExactAmounts() internal {
    if (repayExactAmount0 > 0) {
      IERC20(token0).transfer(address(fpmm), repayExactAmount0);
    }
    if (repayExactAmount1 > 0) {
      IERC20(token1).transfer(address(fpmm), repayExactAmount1);
    }
  }
}
