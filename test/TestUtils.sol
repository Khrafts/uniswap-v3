// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../src/UniswapV3Pool.sol";
import "abdk-math/ABDKMath64x64.sol";
import "../src/lib/FixedPoint96.sol";

abstract contract TestUtils {
    function encodeError(string memory error) internal pure returns (bytes memory encoded) {
        encoded = abi.encodeWithSignature(error);
    }

    function encodeExtra(address token0_, address token1_, address payer) internal pure returns (bytes memory) {
        return abi.encode(UniswapV3Pool.CallbackData({token0: token0_, token1: token1_, payer: payer}));
    }

    function tick(uint256 price) internal pure returns (int24 tick_) {
        tick_ = TickMath.getTickAtSqrtRatio(
            uint160(
                int160(
                    ABDKMath64x64.sqrt(int128(int256(price << 64))) <<
                        (FixedPoint96.RESOLUTION - 64)
                )
            )
        );
    }

    function tickInBitMap(UniswapV3Pool pool, int24 tick_)
        internal
        view
        returns (bool initialized)
    {
        int16 wordPos = int16(tick_ >> 8);
        uint8 bitPos = uint8(uint24(tick_ % 256));

        uint256 word = pool.tickBitmap(wordPos);

        initialized = (word & (1 << bitPos)) != 0;
    }
}
