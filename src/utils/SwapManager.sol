// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {Ownable} from "oz/access/Ownable.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {ICurvePool} from "../interfaces/ICurvePool.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";

import {TickMath} from "../libraries/TickMath.sol";
import {FullMath} from "../libraries/FullMath.sol";

error SwapManager__SlippageNotSet();
error SwapManager__ZeroAddress();
error SwapManager__NoLiquidity();
error SwapManager__InvalidPoolToken();
error SwapManager__NotLidoStEthStrategy();
error SwapManager__NoPool(address tokenIn);
error SwapManager__MIN_TWAP_DURATION(uint32 duration);
error SwapManager__ExceedPercentage(uint256 given, uint256 max);
error SwapManager__SlippageExceeded(uint256 amountOut, uint256 minAmountOut);

contract SwapManager is Ownable {
    enum DEX {
        Uniswap,
        Curve
    }

    uint256 internal constant ZERO = 0;
    uint256 internal constant ONE = 1;
    uint256 internal constant MIN_DEADLINE = 30; // 30 seconds
    uint32 public constant MIN_TWAP_DURATION = 36_00;
    uint256 internal constant ONE_HUNDRED_PERCENT = 1000_000;
    uint256 public constant DECIMAL_PRECISION = 10 ** 18;
    uint32 public twapDuration;

    address NULL;
    address WETH9;
    address v3SwapRouter;
    address lidoStEthStrategy;

    // token => pool
    mapping(address => address) public v3Pools;
    mapping(address => address) public curvePools;
    mapping(address => uint24) public slippage;

    event UniswapV3PoolUpdated(address token, address pool);
    event CurvePoolUpdated(address token, address pool);
    event TokenSlippageUpdated(address token, uint24 slippage);
    event TwapDurationUpdated(uint32 duration);

    constructor(address _intialOwner, address _weth9, address _null, address _v3SwapRouter) Ownable(_intialOwner) {
        if (_weth9 == address(0) || _v3SwapRouter == address(0) || _v3SwapRouter == address(0)) {
            revert SwapManager__ZeroAddress();
        }
        WETH9 = _weth9;
        NULL = _null;
        v3SwapRouter = _v3SwapRouter;
        twapDuration = MIN_TWAP_DURATION;
    }

    /**
     * @notice Swaps tokens using Uniswap V3 or Curve pool.
     * @param tokenIn The input token address.
     * @param amountIn The amount of input tokens.
     * @return amountOut The amount of output tokens.
     */
    function swap(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        DEX dexType;
        (dexType,) = getFairQuote(amountIn, tokenIn);

        if (dexType == DEX.Uniswap) {
            amountOut = swapUinv3(tokenIn, amountIn);
        }

        if (dexType == DEX.Curve) {
            amountOut = swapCurve(tokenIn, amountIn);
        }
    }

    /**
     * @notice swap tokens from the uniswap v3 pools
     */
    function swapUinv3(address tokenIn, uint256 amountIn) public returns (uint256 amountOut) {
        // estimate price using the twap
        uint256 quoteOut = estimateV3AmountOut(uint128(amountIn), tokenIn, WETH9);
        uint256 amountOutMinimum = _getMinimumAmount(WETH9, quoteOut);
        if (amountOutMinimum == 0) revert SwapManager__NoLiquidity();

        address pool = _getV3Pool(tokenIn);
        uint256 deadline = block.timestamp + MIN_DEADLINE;
        uint24 poolFee = IUniswapV3Pool(pool).fee();

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, v3SwapRouter, amountIn);
        amountOut = ISwapRouter(v3SwapRouter).exactInputSingle(
            ISwapRouter.ExactInputSingleParams(
                tokenIn, WETH9, poolFee, address(this), deadline, amountIn, amountOutMinimum, 0
            )
        );

        if (amountOut < amountOutMinimum) revert SwapManager__SlippageExceeded(amountOut, amountOutMinimum);
        uint256 weth9Balance = IWETH9(WETH9).balanceOf(address(this));
        if (weth9Balance > 0) IWETH9(WETH9).withdraw(weth9Balance);
        TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    /**
     * @notice swap tokens from the curve pools
     */
    function swapCurve(address tokenIn, uint256 amountIn) public returns (uint256 amountOut) {
        address pool = _getCurvePool(tokenIn);
        (address token0, address token1) = _getCurvPoolTokens(pool);
        address tokenOut = token0 == tokenIn ? token1 : token0;

        uint256 quoteOut = estimateCurveAmountOut(amountIn, tokenIn, tokenOut);
        uint256 amountOutMinimum = _getMinimumAmount(tokenOut, quoteOut);
        if (amountOutMinimum == 0) revert SwapManager__NoLiquidity();

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, pool, amountIn);

        (int128 _inIdx, int128 _outIdx) = _getCurveTokenIndex(pool, tokenIn);
        amountOut = ICurvePool(pool).exchange(_inIdx, _outIdx, amountIn, amountOutMinimum);
        TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    // [internal functions]

    function _getV3Pool(address tokenIn) internal view returns (address pool) {
        pool = v3Pools[tokenIn];
        if (pool == address(0)) revert SwapManager__NoPool(tokenIn);
    }

    function _getCurvePool(address tokenIn) internal view returns (address pool) {
        pool = curvePools[tokenIn];
        if (pool == address(0)) revert SwapManager__NoPool(tokenIn);
    }

    function _getCurveTokenIndex(address pool, address tokenIn) internal view returns (int128 _inIdx, int128 _outIdx) {
        (address token0,) = _getCurvPoolTokens(pool);
        int128 _i0 = int128(0);
        int128 _i1 = int128(1);
        return token0 == tokenIn ? (_i0, _i1) : (_i1, _i0);
    }

    function _getMinimumAmount(address token, uint256 amount) internal view returns (uint256) {
        if (slippage[token] == 0) revert SwapManager__SlippageNotSet();
        return (amount * slippage[token]) / ONE_HUNDRED_PERCENT;
    }

    function _getCurvPoolTokens(address pool) internal view returns (address token0, address token1) {
        token0 = ICurvePool(pool).coins(ZERO);
        token1 = ICurvePool(pool).coins(ONE);
    }

    /// @notice Given a tick and a token amount, calculates the amount of token received in exchange
    /// @param tick Tick value used to calculate the quote
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
    function _getQuoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken)
        internal
        pure
        returns (uint256 quoteAmount)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    // [view functions]

    /**
     * @notice Gets the fair quote for swapping tokens.
     * @param amountIn The amount of input tokens.
     * @param tokenIn The input token address.
     * @return dexType The DEX (Decentralized Exchange) type (Uniswap or Curve).
     * @return amountOut The estimated output amount of tokens.
     */
    function getFairQuote(uint256 amountIn, address tokenIn) public view returns (DEX dexType, uint256 amountOut) {
        // estimate price using the twap
        uint256 v3Out = estimateV3AmountOut(uint128(amountIn), tokenIn, WETH9);
        uint256 curveOut = estimateCurveAmountOut(uint128(amountIn), tokenIn, NULL);
        if (v3Out == 0 && curveOut == 0) revert SwapManager__NoLiquidity();
        return v3Out > curveOut ? (DEX.Uniswap, v3Out) : (DEX.Curve, curveOut);
    }

    /**
     * @dev Fetches virtual price of the curve pool and
     * estimates the amount of tokenOut to receive for a given amount of tokenIn using a Curve pool
     * @param amountIn The amount of input tokens
     * @param tokenIn The address of the input token
     * @return amountOut The estimated amount of output tokens
     */
    function estimateCurveAmountOut(uint256 amountIn, address tokenIn, address)
        public
        view
        returns (uint256 amountOut)
    {
        address pool = _getCurvePool(tokenIn);
        (int128 i, int128 j) = _getCurveTokenIndex(pool, tokenIn);
        amountOut = ICurvePool(pool).get_dy(i, j, amountIn);
    }

    /**
     * @dev Fetches time-weighted average price in ticks from Uniswap pool and
     * estimates the amount of tokenOut to receive for a given amount of tokenIn using a Uniswap V3 pool
     * @param amountIn The amount of input tokens
     * @param tokenIn The address of the input token
     * @param tokenOut The address of the output token
     * @return amountOut The estimated amount of output tokens
     */
    function estimateV3AmountOut(uint128 amountIn, address tokenIn, address tokenOut)
        public
        view
        returns (uint256 amountOut)
    {
        address pool = _getV3Pool(tokenIn);
        uint32 secondsAgo = twapDuration;
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo; // secondsAgo
        secondsAgos[1] = 0;

        // int56 since tick * time = int24 * uint32
        // 56 = 24 + 32
        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // int56 / uint32 = int24
        int24 tick = int24(tickCumulativesDelta / int32(secondsAgo));
        // Always round to negative infinity
        /*
        int doesn't round down when it is negative

        int56 a = -3
        -3 / 10 = -3.3333... so round down to -4
        but we get
        a / 10 = -3

        so if tickCumulativeDelta < 0 and division has remainder, then round
        down
        */
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int32(secondsAgo) != 0)) {
            tick--;
        }

        amountOut = _getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    }

    // [setter functions]

    /**
     * @dev Sets the Uniswap V3 pool address for a given token along with the slippage tolerance
     * @param _token The address of the token
     * @param _pool The address of the Uniswap V3 pool
     * @param _slippage The slippage tolerance for the pool
     */
    function setWhitelistV3Pool(address _token, address _pool, uint24 _slippage) external onlyOwner {
        if (_token == address(0) || _pool == address(0)) revert SwapManager__ZeroAddress();
        if (_slippage > ONE_HUNDRED_PERCENT) revert SwapManager__ExceedPercentage(_slippage, ONE_HUNDRED_PERCENT);

        (address token0, address token1) = (IUniswapV3Pool(_pool).token0(), IUniswapV3Pool(_pool).token1());
        if ((token0 != WETH9 && token1 != WETH9) || ((token0 != _token && token1 != _token))) {
            revert SwapManager__InvalidPoolToken();
        }

        v3Pools[_token] = _pool;
        slippage[_token] = _slippage;
        emit UniswapV3PoolUpdated(_token, _pool);
    }

    /**
     * @dev Sets the Curve pool address for a given token along with the slippage tolerance
     * @param _token The address of the token
     * @param _pool The address of the Curve pool
     * @param _slippage The slippage tolerance for the pool
     */
    function setWhitelistCurvePool(address _token, address _pool, uint24 _slippage) external onlyOwner {
        if (_token == address(0) || _pool == address(0)) revert SwapManager__ZeroAddress();
        if (_slippage > ONE_HUNDRED_PERCENT) revert SwapManager__ExceedPercentage(_slippage, ONE_HUNDRED_PERCENT);

        (address token0, address token1) = _getCurvPoolTokens(_pool);
        if ((token0 != NULL && token1 != NULL) || ((token0 != _token && token1 != _token))) {
            revert SwapManager__InvalidPoolToken();
        }

        curvePools[_token] = _pool;
        slippage[_token] = _slippage;
        emit CurvePoolUpdated(_token, _pool);
    }

    /**
     * @dev Sets the slippage tolerance for a given token
     * @param _token The address of the token
     * @param _slippage The slippage tolerance for the token
     */
    function setTokenSlippage(address _token, uint24 _slippage) external onlyOwner {
        if (_slippage > ONE_HUNDRED_PERCENT) revert SwapManager__ExceedPercentage(_slippage, ONE_HUNDRED_PERCENT);
        slippage[_token] = _slippage;
        emit TokenSlippageUpdated(_token, _slippage);
    }

    /**
     * @dev Sets the duration for time-weighted average price (TWAP) calculations
     * @param _duration The duration in seconds
     */
    function setTwapDuration(uint32 _duration) external onlyOwner {
        if (_duration < MIN_TWAP_DURATION) revert SwapManager__MIN_TWAP_DURATION(_duration);
        twapDuration = _duration;
        emit TwapDurationUpdated(_duration);
    }

    receive() external payable {}
}
