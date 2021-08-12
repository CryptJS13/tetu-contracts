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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../base/governance/Controllable.sol";
import "../base/interface/ISmartVault.sol";
import "../base/interface/IStrategy.sol";
import "../base/interface/IController.sol";
import "../third_party/uniswap/IUniswapV2Pair.sol";
import "../third_party/uniswap/IUniswapV2Router02.sol";
import "./IPriceCalculator.sol";
import "./IMultiSwap.sol";

/// @title Dedicated solution for interacting with vaults.
///        Able to zap in/out assets to vaults
/// @dev Use with ProxyGov
/// @author belbix
contract ZapContract is Controllable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  string public constant VERSION = "1.0.0";
  bytes32 internal constant _MULTI_SWAP_SLOT = 0x268C7387BB3D6C63B06B7390ECC1422F60B0BA31459D23A25507C9F998F216E3;

  event UpdateMultiSwap(address oldValue, address newValue);

  struct ZapInfo {
    address lp;
    address tokenIn;
    address asset0;
    address[] asset0Route;
    address asset1;
    address[] asset1Route;
    uint256 tokenInAmount;
    uint256 slippageTolerance;
  }

  constructor() {
    assert(_MULTI_SWAP_SLOT == bytes32(uint256(keccak256("eip1967.multiSwap")) - 1));
  }

  function initialize(address _controller) external initializer {
    Controllable.initializeControllable(_controller);
  }

  // ******************* VIEWS *****************************

  /// @dev Return address of MultiSwap contract
  function multiSwap() public view returns (IMultiSwap) {
    bytes32 slot = _MULTI_SWAP_SLOT;
    address adr;
    assembly {
      adr := sload(slot)
    }
    return IMultiSwap(adr);
  }

  // ******************** USERS ACTIONS *********************

  /// @dev Approval for token is assumed.
  ///      Add liquidity and deposit to given vault
  ///      Token should be declared as keyToken from priceCalculator
  ///      Slippage tolerance is a number from 0 to 100 that reflect is a percent of acceptable slippage
  function zapIntoLp(
    address _vault,
    address _tokenIn,
    address _asset0,
    address[] memory _asset0Route,
    address _asset1,
    address[] memory _asset1Route,
    uint256 _tokenInAmount,
    uint256 slippageTolerance
  ) external {
    require(_tokenInAmount > 1, "not enough amount");

    IUniswapV2Pair lp = IUniswapV2Pair(ISmartVault(_vault).underlying());

    require(_asset0 == lp.token0() || _asset0 == lp.token1(), "asset 0 not exist in lp tokens");
    require(_asset1 == lp.token0() || _asset1 == lp.token1(), "asset 1 not exist in lp tokens");

    // transfer only require amount
    IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _tokenInAmount.div(2).mul(2));

    // asset0 multi-swap
    callMultiSwap(
      _tokenIn,
      _tokenInAmount.div(2),
      _asset0Route,
      _asset0,
      slippageTolerance
    );

    // asset0 multi-swap
    callMultiSwap(
      _tokenIn,
      _tokenInAmount.div(2),
      _asset1Route,
      _asset1,
      slippageTolerance
    );
    // assume that final outcome amounts was checked on the multiSwap contract side

    uint256 liquidity = addLiquidity(
      ZapInfo(
        address(lp),
        _tokenIn,
        _asset0,
        _asset0Route,
        _asset1,
        _asset1Route,
        _tokenInAmount,
        slippageTolerance
      )
    );

    require(liquidity != 0, "zero liq");

    depositToVault(_vault, liquidity, address(lp));

  }

  function zapOutLp(
    address _vault,
    address _tokenOut,
    address _asset0,
    address[] memory _asset0Route,
    address _asset1,
    address[] memory _asset1Route,
    uint256 _shareTokenAmount,
    uint256 slippageTolerance
  ) external {
    require(_shareTokenAmount != 0, "zero amount");

    IUniswapV2Pair lp = IUniswapV2Pair(ISmartVault(_vault).underlying());

    require(_asset0 == lp.token0() || _asset0 == lp.token1(), "asset 0 not exist in lp token");
    require(_asset1 == lp.token0() || _asset1 == lp.token1(), "asset 1 not exist in lp token");

    IERC20(_vault).safeTransferFrom(msg.sender, address(this), _shareTokenAmount);

    uint256 lpBalance = withdrawFromVault(_vault, _shareTokenAmount, address(lp));

    IUniswapV2Router02 router = IUniswapV2Router02(multiSwap().routerForPair(address(lp)));

    IERC20(address(lp)).safeApprove(address(router), lpBalance);
    // without care about slippage
    router.removeLiquidity(
      _asset0,
      _asset1,
      lpBalance,
      1,
      1,
      address(this),
      block.timestamp
    );

    // asset0 multi-swap
    callMultiSwap(
      _asset0,
      IERC20(_asset0).balanceOf(address(this)),
      _asset0Route,
      _tokenOut,
      slippageTolerance
    );

    // asset1 multi-swap
    callMultiSwap(
      _asset1,
      IERC20(_asset1).balanceOf(address(this)),
      _asset1Route,
      _tokenOut,
      slippageTolerance
    );

    uint256 tokenOutBalance = IERC20(_tokenOut).balanceOf(address(this));
    IERC20(_tokenOut).safeTransfer(msg.sender, tokenOutBalance);
  }

  // ************************* INTERNAL *******************

  function addLiquidity(ZapInfo memory zapInfo) internal returns (uint256){
    uint256 asset0Amount = IERC20(zapInfo.asset0).balanceOf(address(this));
    uint256 asset1Amount = IERC20(zapInfo.asset1).balanceOf(address(this));

    uint256 asset0AmountMin = asset0Amount.sub(
      asset0Amount.mul(zapInfo.slippageTolerance).div(100)
    );

    uint256 asset1AmountMin = asset1Amount.sub(
      asset1Amount.mul(zapInfo.slippageTolerance).div(100)
    );

    IUniswapV2Router02 router = IUniswapV2Router02(multiSwap().routerForPair(zapInfo.lp));

    IERC20(zapInfo.asset0).safeApprove(address(router), asset0Amount);
    IERC20(zapInfo.asset1).safeApprove(address(router), asset1Amount);
    (,, uint256 liquidity) = router.addLiquidity(
      zapInfo.asset0,
      zapInfo.asset1,
      asset0Amount,
      asset1Amount,
      asset0AmountMin,
      asset1AmountMin,
      address(this),
      block.timestamp
    );

    // send back change if exist
    sendBackAssets(zapInfo);
    return liquidity;
  }

  function sendBackAssets(ZapInfo memory zapInfo) internal {
    uint256 bal0 = IERC20(zapInfo.asset0).balanceOf(address(this));
    uint256 bal1 = IERC20(zapInfo.asset1).balanceOf(address(this));
    if (bal0 != 0) {
      address[] memory reverseRoute = new address[](zapInfo.asset0Route.length);

      for (uint256 i = zapInfo.asset0Route.length; i > 0; i--) {
        reverseRoute[zapInfo.asset0Route.length - i] = zapInfo.asset0Route[i - 1];
      }

      callMultiSwap(
        zapInfo.asset0,
        bal0,
        reverseRoute,
        zapInfo.tokenIn,
        zapInfo.slippageTolerance
      );
    }
    if (bal1 != 0) {
      address[] memory reverseRoute = new address[](zapInfo.asset1Route.length);

      for (uint256 i = zapInfo.asset1Route.length; i > 0; i--) {
        reverseRoute[zapInfo.asset1Route.length - i] = zapInfo.asset1Route[i - 1];
      }

      callMultiSwap(
        zapInfo.asset1,
        bal1,
        reverseRoute,
        zapInfo.tokenIn,
        zapInfo.slippageTolerance
      );
    }

    uint256 tokenBal = IERC20(zapInfo.tokenIn).balanceOf(address(this));
    if (tokenBal != 0) {
      IERC20(zapInfo.tokenIn).safeTransfer(msg.sender, tokenBal);
    }
  }

  function callMultiSwap(
    address _tokenIn,
    uint256 _tokenInAmount,
    address[] memory _lpRoute,
    address _tokenOut,
    uint256 slippageTolerance
  ) internal {
    if (_tokenIn == _tokenOut) {
      // no actions if we already have required token
      return;
    }
    IERC20(_tokenIn).safeApprove(address(multiSwap()), _tokenInAmount);
    multiSwap().multiSwap(_lpRoute, _tokenIn, _tokenOut, _tokenInAmount, slippageTolerance);
  }

  /// @dev Deposit into vault, check the result and send share token to msg.sender
  function depositToVault(address _vault, uint256 _amount, address _underlying) internal {
    require(ISmartVault(_vault).underlying() == _underlying, "wrong lp for vault");

    IERC20(_underlying).safeApprove(_vault, _amount);
    ISmartVault(_vault).deposit(_amount);

    uint256 shareBalance = IERC20(_vault).balanceOf(address(this));
    require(shareBalance != 0, "zero shareBalance");

    IERC20(_vault).safeTransfer(msg.sender, shareBalance);
  }

  /// @dev Withdraw from vault and check the result
  function withdrawFromVault(address _vault, uint256 _amount, address _underlying) internal returns (uint256){
    ISmartVault(_vault).withdraw(_amount);

    uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
    require(underlyingBalance != 0, "zero underlying balance");
    return underlyingBalance;
  }

  // ************************* GOV ACTIONS *******************

  /// @dev Set MultiSwap contract address
  function setMultiSwap(address _newValue) external onlyControllerOrGovernance {
    require(_newValue != address(0), "zero address");
    emit UpdateMultiSwap(address(multiSwap()), _newValue);
    bytes32 slot = _MULTI_SWAP_SLOT;
    assembly {
      sstore(slot, _newValue)
    }
  }

}
