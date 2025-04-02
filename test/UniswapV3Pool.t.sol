// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";

import "./ERC20Mintable.sol";
import "../src/UniswapV3Pool.sol";

contract UniswapV3PoolTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV3Pool pool;

    bool shouldTransferInCallback = true;

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool shouldTransferInCallback;
        bool mintLiquidity;
    }

    function setUp() public {
        token0 = new ERC20Mintable("Ether", "ETH", 18);
        token1 = new ERC20Mintable("USDC", "USDC", 18);
    }

    function testMintSuccess() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            shouldTransferInCallback: true,
            mintLiquidity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 expectedAmount0 = 0.99897661834742528 ether;
        uint256 expectedAmount1 = 5000 ether;

        assertEq(poolBalance0, expectedAmount0, "incorrect token0 deposited amount");
        assertEq(poolBalance1, expectedAmount1, "incorrect token1 deposited amount");

        assertEq(token0.balanceOf(address(pool)), expectedAmount0);
        assertEq(token1.balanceOf(address(pool)), expectedAmount1);

        bytes32 positionKey = keccak256(abi.encodePacked(address(this), params.lowerTick, params.upperTick));
        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquidity);

        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(params.lowerTick);
        assertTrue(tickInitialized, "lower tick not initialized");
        assertEq(tickLiquidity, params.liquidity, "lower tick liquidity mismatch");

        (tickInitialized, tickLiquidity) = pool.ticks(params.upperTick);
        assertTrue(tickInitialized, "upper tick not initialized");
        assertEq(tickLiquidity, params.liquidity, "upper tick liquidity mismatch");

        // Check for Root P and L:
        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, params.currentSqrtP, "incorrect sqrtPriceX96");
        assertEq(tick, params.currentTick, "incorrect tick");
        assertEq(pool.liquidity(), params.liquidity, "incorrect liquidity");
    }

    function testMintInvlaidTickRangeLower() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);

        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(address(this), -887273, 0, 0);
    }

    function testMintInvlaidTickRangeUpper() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);

        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(address(this), 0, 887273, 0);
    }

    function testMintInvalidTickRangeSame() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);

        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(address(this), 0, 0, 0);
    }

    function testMintZeroLiquidity() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);

        vm.expectRevert(UniswapV3Pool.ZeroLiquidity.selector);
        pool.mint(address(this), 0, 1, 0);
    }

    function testMintInsufficientInputAmount() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            shouldTransferInCallback: false,
            mintLiquidity: true
        });

        setupTestCase(params);

        vm.expectRevert(UniswapV3Pool.InsufficientInputAmount.selector);
        pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity);
    }

    function testSwapBuyEth() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            shouldTransferInCallback: true,
            mintLiquidity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        token1.mint(address(this), 42 ether);

        uint256 userBalance0Before = token0.balanceOf(address(this));

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(address(this));

        assertEq(
            token0.balanceOf(address(this)),
            uint256(int256(userBalance0Before) - amount0Delta),
            "Invalid user ETH balance"
        );

        assertEq(token1.balanceOf(address(this)), 0, "invalid user USDC balance");

        assertEq(
            token0.balanceOf(address(pool)), uint256(int256(poolBalance0) + amount0Delta), "invalid pool ETH balance"
        );
        assertEq(
            token1.balanceOf(address(pool)), uint256(int256(poolBalance1) + amount1Delta), "invalid user USDC balance"
        );

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, 5604469350942327889444743441197, "invalid current sqrtP");
        assertEq(pool.liquidity(), 1517882343751509868544, "invalid current liquidity");
    }

    function setupTestCase(TestCaseParams memory params)
        internal
        returns (uint256 poolBalance0, uint256 poolBalance1)
    {
        token0.mint(address(this), params.wethBalance);
        token1.mint(address(this), params.usdcBalance);

        pool = new UniswapV3Pool(address(token0), address(token1), params.currentSqrtP, params.currentTick);

        if (params.mintLiquidity) {
            (poolBalance0, poolBalance1) =
                pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity);
        }

        shouldTransferInCallback = params.shouldTransferInCallback;
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1) public {
        if (shouldTransferInCallback) {
            token0.transfer(msg.sender, amount0);
            token1.transfer(msg.sender, amount1);
        }
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1) public {
        if (amount0 > 0) {
            token0.transfer(msg.sender, uint256(amount0));
        }

        if (amount1 > 0) {
            token1.transfer(msg.sender, uint256(amount1));
        }
    }
}
