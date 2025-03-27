// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {Tick} from "./lib/Tick.sol";
import {Position} from "./lib/Position.sol";

contract UniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Pool tokens, immutable
    address public immutable token0;
    address public immutable token1;
    
    struct Slot0 {
        // current sqrt(P)
        uint160 sqrtPriceX96;
        // current tick
        int24 tick;
    }

    Slot0 public slot0;

    // Amount of liquidity in the pool, L
    uint128 public liquidity;

    // Ticks info
    mapping(int24 => Tick.Info) public ticks;
    // Positions info
    mapping(bytes32 => Position.Info) public positions;
}