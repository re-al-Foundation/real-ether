// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {Ownable} from "oz/access/Ownable.sol";
import {Ownable2Step} from "oz/access/Ownable2Step.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "oz/utils/math/SafeCast.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {ICurvePool} from "../interfaces/ICurvePool.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";

import {TickMath} from "v3-core-0.8/libraries/TickMath.sol";
import {FullMath} from "v3-core-0.8/libraries/FullMath.sol";

error SwapManager__SlippageNotSet();
error SwapManager__ZeroAddress();
error SwapManager__NoLiquidity();
error SwapManager__InvalidPoolToken();
error SwapManager__NoPool(address tokenIn);
error SwapManager__MIN_TWAP_DURATION(uint32 duration);
error SwapManager__ExceedPercentage(uint256 given, uint256 max);
error SwapManager__SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
error SwapManager__TooLittleRecieved(uint256 amountOut, uint256 minAmountOut);

contract SwapManager is Ownable2Step {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    enum DEX {
        Uniswap,
        Curve
    }

    uint256 internal constant ZERO = 0;
    uint256 internal constant ONE = 1;
    uint256 internal constant MIN_DEADLINE = 30; // 30 seconds
    uint32 public constant MIN_TWAP_DURATION = 3_600;
    uint256 internal constant ONE_HUNDRED_PERCENT = 100_0000;
    uint256 public constant DECIMAL_PRECISION = 10 ** 18;
    uint256 internal constant MAX_SLIPPAGE = 5_00_00; //5%

    uint32 public twapDuration;

    address public immutable NULL;
    address public immutable WETH9;
    address public immutable v3SwapRouter;

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
     * @notice Swap tokens from the uniswap v3 pools.
     * @param tokenIn The input token address.
     * @param amountIn The amount of input tokens.
     * @return amountOut The amount of output tokens.
     */
    function swapUinv3(address tokenIn, uint256 amountIn, uint256 amountOutMinimum)
        public
        returns (uint256 amountOut)
    {
        if (amountOutMinimum == 0) revert SwapManager__NoLiquidity();

        address pool = _getV3Pool(tokenIn);
        uint256 deadline = block.timestamp + MIN_DEADLINE;
        uint24 poolFee = IUniswapV3Pool(pool).fee();

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(v3SwapRouter, amountIn);
        amountOut = ISwapRouter(v3SwapRouter).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: WETH9,
                fee: poolFee,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );

        if (amountOut < amountOutMinimum) revert SwapManager__SlippageExceeded(amountOut, amountOutMinimum);
        uint256 weth9Balance = IWETH9(WETH9).balanceOf(address(this));
        if (weth9Balance > 0) IWETH9(WETH9).withdraw(weth9Balance);

        amountOut = address(this).balance;
        TransferHelper.safeTransferETH(msg.sender, amountOut);
    }

    /**
     * @notice Swap tokens from the curve pools.
     * @param tokenIn The input token address.
     * @param amountIn The amount of input tokens.
     * @return amountOut The amount of output tokens.
     */
    function swapCurve(address tokenIn, uint256 amountIn, uint256 amountOutMinimum)
        public
        returns (uint256 amountOut)
    {
        if (amountOutMinimum == 0) revert SwapManager__NoLiquidity();
        address pool = _getCurvePool(tokenIn);

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(pool, amountIn);

        (int128 _inIdx, int128 _outIdx) = _getCurveTokenIndex(pool, tokenIn);
        amountOut = ICurvePool(pool).exchange(_inIdx, _outIdx, amountIn, amountOutMinimum);

        amountOut = address(this).balance;
        TransferHelper.safeTransferETH(msg.sender, amountOut);
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
        int128 _i0 = int128(int256(ZERO));
        int128 _i1 = int128(int256(ONE));
        return token0 == tokenIn ? (_i0, _i1) : (_i1, _i0);
    }

    function getMinimumAmount(address token, uint256 amount) public view returns (uint256) {
        if (slippage[token] == 0) revert SwapManager__SlippageNotSet();
        uint256 oneMinusSlippage = ONE_HUNDRED_PERCENT - slippage[token];
        return FullMath.mulDiv(amount, oneMinusSlippage, ONE_HUNDRED_PERCENT);
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
        unchecked {
            uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
            // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
            if (sqrtRatioX96 <= type(uint128).max) {
                uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
                quoteAmount = baseToken < quoteToken
                    ? FullMath.mulDiv(ratioX192, baseAmount, ONE << 192)
                    : FullMath.mulDiv(ONE << 192, baseAmount, ratioX192);
            } else {
                uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, ONE << 64);
                quoteAmount = baseToken < quoteToken
                    ? FullMath.mulDiv(ratioX128, baseAmount, ONE << 128)
                    : FullMath.mulDiv(ONE << 128, baseAmount, ratioX128);
            }
        }
    }

    // [view functions]

    /**
     * @dev Fetches virtual price of the curve pool and
     * estimates the amount of tokenOut to receive for a given amount of tokenIn using a Curve pool
     * @param amountIn The amount of input tokens
     * @param tokenIn The address of the input token
     * @return amountOut The estimated amount of output tokens
     */
    function estimateCurveAmountOut(uint256 amountIn, address tokenIn) public view returns (uint256 amountOut) {
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

        int56 tickCumulativesDelta;
        unchecked {
            tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        }

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
            unchecked {
                tick--;
            }
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
        if (_slippage > MAX_SLIPPAGE) revert SwapManager__ExceedPercentage(_slippage, MAX_SLIPPAGE);

        (address token0, address token1) = (IUniswapV3Pool(_pool).token0(), IUniswapV3Pool(_pool).token1());

        if (token0 != _token && token0 != WETH9) revert SwapManager__InvalidPoolToken();
        if (token1 != _token && token1 != WETH9) revert SwapManager__InvalidPoolToken();

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
        if (_slippage > MAX_SLIPPAGE) revert SwapManager__ExceedPercentage(_slippage, MAX_SLIPPAGE);

        (address token0, address token1) = _getCurvPoolTokens(_pool);

        if (token0 != _token && token0 != NULL) revert SwapManager__InvalidPoolToken();
        if (token1 != _token && token1 != NULL) revert SwapManager__InvalidPoolToken();

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
        if (_slippage > MAX_SLIPPAGE) revert SwapManager__ExceedPercentage(_slippage, MAX_SLIPPAGE);
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
