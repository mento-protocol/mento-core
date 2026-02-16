// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;
// solhint-disable-next-line max-line-length
import { ERC20PermitUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { IStableTokenSpoke } from "../interfaces/IStableTokenSpoke.sol";

/**
 * @title StableTokenSpoke
 * @notice A spoke version of the StableTokenV3 contract.
 * @dev This contract is used to mint and burn tokens on a different chain.
 */
contract StableTokenSpoke is ERC20PermitUpgradeable, OwnableUpgradeable, IStableTokenSpoke {
  /* ========================================================= */
  /* ==================== State Variables ==================== */
  /* ========================================================= */

  // Mapping of allowed addresses that can mint
  mapping(address => bool) public isMinter;
  // Mapping of allowed addresses that can burn
  mapping(address => bool) public isBurner;

  /* ========================================================= */
  /* ======================== Events ========================= */
  /* ========================================================= */

  event MinterUpdated(address indexed minter, bool isMinter);
  event BurnerUpdated(address indexed burner, bool isBurner);

  /* ========================================================= */
  /* ====================== Modifiers ======================== */
  /* ========================================================= */

  modifier onlyMinter() {
    address sender = _msgSender();
    require(isMinter[sender], "StableToken: not allowed to mint");
    _;
  }

  modifier onlyBurner() {
    address sender = _msgSender();
    require(isBurner[sender], "StableToken: not allowed to burn");
    _;
  }

  /* ========================================================= */
  /* ====================== Constructor ====================== */
  /* ========================================================= */

  /**
   * @notice The constructor for the StableTokenSpoke contract.
   * @dev Should be called with disable=true in deployments when
   * it's accessed through a Proxy.
   * Call this with disable=false during testing, when used
   * without a proxy.
   * @param disable Set to true to run `_disableInitializers()` inherited from
   * openzeppelin-contracts-upgradeable/Initializable.sol
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /// @inheritdoc IStableTokenSpoke
  function initialize(
    string memory name,
    string memory symbol,
    address[] memory initialBalanceAddresses,
    uint256[] memory initialBalanceValues,
    address[] memory _minters,
    address[] memory _burners
  ) public initializer {
    __ERC20_init(name, symbol);
    __EIP712_init_unchained(name, "3");
    _transferOwnership(_msgSender());

    require(initialBalanceAddresses.length == initialBalanceValues.length, "Array length mismatch");
    for (uint256 i = 0; i < initialBalanceAddresses.length; i += 1) {
      _mint(initialBalanceAddresses[i], initialBalanceValues[i]);
    }
    for (uint256 i = 0; i < _minters.length; i += 1) {
      _setMinter(_minters[i], true);
    }
    for (uint256 i = 0; i < _burners.length; i += 1) {
      _setBurner(_burners[i], true);
    }
  }

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc IStableTokenSpoke
  function setMinter(address _minter, bool _isMinter) external onlyOwner {
    _setMinter(_minter, _isMinter);
  }

  /// @inheritdoc IStableTokenSpoke
  function setBurner(address _burner, bool _isBurner) external onlyOwner {
    _setBurner(_burner, _isBurner);
  }

  /// @inheritdoc IStableTokenSpoke
  function mint(address to, uint256 value) external onlyMinter returns (bool) {
    _mint(to, value);
    return true;
  }

  /// @inheritdoc IStableTokenSpoke
  function burn(uint256 value) external onlyBurner returns (bool) {
    _burn(msg.sender, value);
    return true;
  }

  /* =========================================================== */
  /* ==================== Private Functions ==================== */
  /* =========================================================== */

  function _setMinter(address _minter, bool _isMinter) internal {
    isMinter[_minter] = _isMinter;
    emit MinterUpdated(_minter, _isMinter);
  }

  function _setBurner(address _burner, bool _isBurner) internal {
    isBurner[_burner] = _isBurner;
    emit BurnerUpdated(_burner, _isBurner);
  }
}
