// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../src/UniswapV3Pool.sol";
import "../src/interfaces/IUniswapV3Pool.sol";
import "../src/interfaces/IERC20.sol";
import "../src/interfaces/IUniswapV3Manager.sol";
import "../src/lib/Path.sol";
import "../src/lib/PoolAddress.sol";

contract UniswapV3Manager is IUniswapV3Manager {
    using Path for bytes;

    error SlippageCheckFailed(uint256 amount0, uint256 amount1);
    error TooLittleReceived(uint256 amountOut);

    address public immutable factory;

    constructor(address factory_) {
        factory = factory_;
    }

    function mint(MintParams calldata params) public returns (uint256 amount0, uint256 amount1) {
        address poolAddress = PoolAddress.computeAddress(factory, params.tokenA, params.tokenB, params.tickSpacing);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96,) = pool.slot0();
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(params.lowerTick);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(params.upperTick);

        uint128 liquidity = LiquidityMath.getLiquidityForAmounts(
            sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, params.amount0Desired, params.amount1Desired
        );

        (amount0, amount1) = pool.mint(
            msg.sender,
            params.lowerTick,
            params.upperTick,
            liquidity,
            abi.encode(IUniswapV3Pool.CallbackData({token0: pool.token0(), token1: pool.token1(), payer: msg.sender}))
        );

        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert SlippageCheckFailed(amount0, amount1);
        }
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external {
        IUniswapV3Pool.CallbackData memory callbackData = abi.decode(data, (IUniswapV3Pool.CallbackData));
        IERC20(callbackData.token0).transferFrom(callbackData.payer, msg.sender, amount0);
        IERC20(callbackData.token1).transferFrom(callbackData.payer, msg.sender, amount1);
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data) external {
        SwapCallbackData memory callbackData = abi.decode(data, (SwapCallbackData));
        (address tokenIn, address tokenOut,) = callbackData.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;
        int256 amount = zeroForOne ? amount0 : amount1;

        if (callbackData.payer == address(this)) {
            IERC20(tokenIn).transfer(msg.sender, uint256(amount));
        } else {
            IERC20(tokenIn).transferFrom(callbackData.payer, msg.sender, uint256(amount));
        }
    }

    function swapSingle(SwapSingleParams calldata params) public returns (uint256 amountOut) {
        amountOut = _swap(
            params.amountIn,
            msg.sender,
            params.sqrtPriceLimitX96,
            SwapCallbackData({
                path: abi.encodePacked(params.tokenIn, params.tickSpacing, params.tokenOut),
                payer: msg.sender
            })
        );
    }

    function swap(SwapParams memory params) public returns (uint256 amountOut) {
        address payer = msg.sender;
        bool hasMultiplePools;

        while (true) {
            hasMultiplePools = params.path.hasMultiplePools();

            params.amountIn = _swap(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient,
                0,
                SwapCallbackData({path: params.path.getFirstPool(), payer: payer})
            );

            if (hasMultiplePools) {
                payer = address(this);
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        if (amountOut < params.minAmountOut) revert TooLittleReceived(amountOut);
    }

    function _swap(uint256 amountIn, address recipient, uint160 sqrtPriceLimitX96, SwapCallbackData memory data)
        internal
        returns (uint256 amountOut)
    {
        (address tokenIn, address tokenOut, uint24 tickSpacing) = data.path.decodeFirstPool();
        bool zeroForOne = tokenIn < tokenOut;
        (int256 amount0, int256 amount1) = getPool(tokenIn, tokenOut, tickSpacing).swap(
            recipient,
            zeroForOne,
            amountIn,
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        amountOut = uint256(-(zeroForOne ? amount1 : amount0));
    }

    function getPool(address token0, address token1, uint24 tickSpacing) internal view returns (IUniswapV3Pool pool) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, token0, token1, tickSpacing));
    }
}
