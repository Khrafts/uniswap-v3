// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IUniswapV3Pool {
    function swap(address receiver, bool zeroForOne, uint256 amountIn, bytes calldata extra)
        external
        returns (int256 amount0Delta, int256 amount1Delta);

    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick);
}
