// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {UniswapV3Pool} from "./UniswapV3Pool.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolDeployer} from "./interfaces/IUniswapV3PoolDeployer.sol";

contract UniswapV3Factory is IUniswapV3PoolDeployer {
    error TokensMustBeDifferent();
    error UnsupportedTickSpacing();
    error PoolAlreadyExists();
    error ZeroAddressNotAllowed();

    event PoolCreated(address indexed token0, address indexed token1, uint24 indexed tickSpacing, address pool);

    mapping(uint24 => bool) public tickSpacings;

    PoolParameters public parameters;
    mapping(address => mapping(address => mapping(uint24 => address))) public pools;

    constructor() {
        tickSpacings[10] = true;
        tickSpacings[60] = true;
        tickSpacings[200] = true;
    }

    function createPool(address tokenX, address tokenY, uint24 tickSpacing) public returns (address pool) {
        if (tokenX == tokenY) revert TokensMustBeDifferent();
        if (!tickSpacings[tickSpacing]) revert UnsupportedTickSpacing();

        (tokenX, tokenY) = tokenX < tokenY ? (tokenX, tokenY) : (tokenY, tokenX);

        if (tokenX == address(0)) revert ZeroAddressNotAllowed();
        if (pools[tokenX][tokenY][tickSpacing] != address(0)) revert PoolAlreadyExists();

        parameters = PoolParameters({factory: address(this), token0: tokenX, token1: tokenY, tickSpacing: tickSpacing});

        pool = address(new UniswapV3Pool{salt: keccak256(abi.encodePacked(tokenX, tokenY, tickSpacing))}());

        delete parameters;

        pools[tokenX][tokenY][tickSpacing] = pool;
        pools[tokenY][tokenX][tickSpacing] = pool;

        emit PoolCreated(tokenX, tokenY, tickSpacing, pool);
    }
}
