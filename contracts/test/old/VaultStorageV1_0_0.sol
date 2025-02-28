// SPDX-License-Identifier: ISC
/**
* By using this software, you understand, acknowledge and accept that Tetu
* and/or the underlying software are provided “as is” and “as available”
* basis and without warranties or representations of any kind either expressed
* or implied. Any use of this open source software released under the ISC
* Internet Systems Consortium license is done at your own risk to the fullest
* extent permissible pursuant to applicable law any and all liability as well
* as all warranties, including any fitness for a particular purpose with respect
* to Tetu and/or the underlying software and the use thereof are disclaimed.
*/

pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./ISmartVaultV1_0_0.sol";

/// @title Eternal storage + getters and setters pattern
/// @dev If you will change a key value it will require setup it again
///      Implements IVault interface for reducing code base
/// @author belbix
abstract contract VaultStorageV1_0_0 is Initializable, ISmartVaultV1_0_0 {

  // don't change names or ordering!
  mapping(bytes32 => uint256) private uintStorage;
  mapping(bytes32 => address) private addressStorage;
  mapping(bytes32 => bool) private boolStorage;

  /// @notice Boolean value changed the variable with `name`
  event UpdatedBoolSlot(string indexed name, bool oldValue, bool newValue);
  /// @notice Address changed the variable with `name`
  event UpdatedAddressSlot(string indexed name, address oldValue, address newValue);
  /// @notice Value changed the variable with `name`
  event UpdatedUint256Slot(string indexed name, uint256 oldValue, uint256 newValue);

  /// @notice Initialize contract after setup it as proxy implementation
  /// @dev Use it only once after first logic setup
  /// @param _underlyingToken Vault underlying token
  /// @param _durationValue Reward vesting period
  function initializeVaultStorage(
    address _underlyingToken,
    uint256 _durationValue
  ) public initializer {
    _setUnderlying(_underlyingToken);
    _setDuration(_durationValue);
    _setActive(true);
  }

  // ******************* SETTERS AND GETTERS **********************

  function _setStrategy(address _address) internal {
    emit UpdatedAddressSlot("strategy", strategy(), _address);
    setAddress("strategy", _address);
  }

  /// @notice Current strategy that vault use for farming
  function strategy() public override view returns (address) {
    return getAddress("strategy");
  }

  function _setUnderlying(address _address) private {
    emit UpdatedAddressSlot("underlying", strategy(), _address);
    setAddress("underlying", _address);
  }

  /// @notice Vault underlying
  function underlying() public view override returns (address) {
    return getAddress("underlying");
  }

  function _setDuration(uint256 _value) internal {
    emit UpdatedUint256Slot("duration", duration(), _value);
    setUint256("duration", _value);
  }

  /// @notice Rewards vesting period
  function duration() public view override returns (uint256) {
    return getUint256("duration");
  }

  function _setActive(bool _value) internal {
    emit UpdatedBoolSlot("active", active(), _value);
    setBoolean("active", _value);
  }

  /// @notice Vault status
  function active() public view override returns (bool) {
    return getBoolean("active");
  }

  // ******************** STORAGE INTERNAL FUNCTIONS ********************

  function setBoolean(string memory key, bool _value) internal {
    boolStorage[keccak256(abi.encodePacked(key))] = _value;
  }

  function getBoolean(string memory key) internal view returns (bool) {
    return boolStorage[keccak256(abi.encodePacked(key))];
  }

  function setAddress(string memory key, address _address) private {
    addressStorage[keccak256(abi.encodePacked(key))] = _address;
  }

  function getAddress(string memory key) private view returns (address) {
    return addressStorage[keccak256(abi.encodePacked(key))];
  }

  function setUint256(string memory key, uint256 _value) private {
    uintStorage[keccak256(abi.encodePacked(key))] = _value;
  }

  function getUint256(string memory key) private view returns (uint256) {
    return uintStorage[keccak256(abi.encodePacked(key))];
  }

  //slither-disable-next-line unused-state
  uint256[50] private ______gap;
}
