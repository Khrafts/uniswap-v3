// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";

import "./ERC20Mintable.sol";
import "../src/UniswapV3Pool.sol";

contract UniswapV3PoolTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV3Pool pool;

    bool transferInMintCallback = true;
    bool transferInSwapCallback = true;

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool transferInMintCallback;
        bool transferInSwapCallback;
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
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 expectedAmount0 = Math.calcAmount0Delta(
            TickMath.getSqrtRatioAtTick(params.currentTick),
            TickMath.getSqrtRatioAtTick(params.upperTick),
            params.liquidity
        );
        uint256 expectedAmount1 = Math.calcAmount1Delta(
            TickMath.getSqrtRatioAtTick(params.currentTick),
            TickMath.getSqrtRatioAtTick(params.lowerTick),
            params.liquidity
        );

        assertEq(poolBalance0, expectedAmount0, "incorrect token0 deposited amount");
        assertEq(poolBalance1, expectedAmount1, "incorrect token1 deposited amount");

        assertEq(token0.balanceOf(address(pool)), expectedAmount0);
        assertEq(token1.balanceOf(address(pool)), expectedAmount1);

        bytes32 positionKey = keccak256(abi.encodePacked(address(this), params.lowerTick, params.upperTick));
        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquidity);

        (bool tickInitialized, uint128 tickLiquidity, ) = pool.ticks(params.lowerTick);
        assertTrue(tickInitialized, "lower tick not initialized");
        assertEq(tickLiquidity, params.liquidity, "lower tick liquidity mismatch");

        (tickInitialized, tickLiquidity, ) = pool.ticks(params.upperTick);
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
        pool.mint(address(this), -887273, 0, 0, "");
    }

    function testMintInvlaidTickRangeUpper() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);

        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(address(this), 0, 887273, 0, "");
    }

    function testMintInvalidTickRangeSame() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);

        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(address(this), 0, 0, 0, "");
    }

    function testMintZeroLiquidity() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);

        vm.expectRevert(UniswapV3Pool.ZeroLiquidity.selector);
        pool.mint(address(this), 0, 1, 0, "");
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
            transferInMintCallback: false,
            transferInSwapCallback: false,
            mintLiquidity: true
        });

        setupTestCase(params);

        vm.expectRevert(UniswapV3Pool.InsufficientInputAmount.selector);
        pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity, "");
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
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 swapAmount = 42 ether;
        token1.mint(address(this), swapAmount);
        token1.approve(address(this), swapAmount);

        uint256 userBalance0Before = token0.balanceOf(address(this));
        uint256 userBalance1Before = token1.balanceOf(address(this));

        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(address(this), false, swapAmount, extra);

        assertEq(
            token0.balanceOf(address(this)),
            uint256(int256(userBalance0Before) - amount0Delta),
            "Invalid user ETH balance"
        );

        assertEq(
            token1.balanceOf(address(this)), userBalance1Before - uint256(amount1Delta), "invalid user USDC balance"
        );

        assertEq(
            token0.balanceOf(address(pool)), uint256(int256(poolBalance0) + amount0Delta), "invalid pool ETH balance"
        );
        assertEq(
            token1.balanceOf(address(pool)), uint256(int256(poolBalance1) + amount1Delta), "invalid user USDC balance"
        );

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(tick, 85184, "invalid current tick");
        assertEq(sqrtPriceX96, 5604469350942327889444743441197, "invalid current sqrtP");
        assertEq(pool.liquidity(), 1517882343751509868544, "invalid current liquidity");
    }

    function testSwapBuyUSDC() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });

        bool zeroForOne = true;
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        // (uint160 sqrtPriceStartX96, ) = pool.slot0();
        uint256 swapAmount = 0.01337 ether;

        token0.mint(address(this), swapAmount);
        token0.approve(address(this), swapAmount);

        uint256 userBalance0Before = token0.balanceOf(address(this));
        uint256 userBalance1Before = token1.balanceOf(address(this));
        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(address(this), zeroForOne, swapAmount, extra);

        // assert amount deltas
        assertEq(
            uint256(amount0Delta), userBalance0Before - token0.balanceOf(address(this)), "Invalid user ETH swapped"
        );
        assertEq(
            uint256(-amount1Delta), token1.balanceOf(address(this)) - userBalance1Before, "Invalid user USDC received"
        );

        // assert pool balances
        assertEq(token0.balanceOf(address(pool)), poolBalance0 + uint256(amount0Delta), "Invalid pool ETH balance");
        assertEq(token1.balanceOf(address(pool)), poolBalance1 - uint256(-amount1Delta), "Invalid pool USDC balance");

        // calculate current tick and sqrtPriceX96
        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        uint160 sqrtPricNextX96 =
            Math.getNextSqrtPriceFromInput(params.currentSqrtP, params.liquidity, swapAmount, zeroForOne);
        int24 tickNext = TickMath.getTickAtSqrtRatio(sqrtPricNextX96);

        assertEq(tick, tickNext, "invalid current tick");
        assertEq(sqrtPriceX96, sqrtPricNextX96, "invalid current sqrtP");
    }

    function testSwapMixed() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        setupTestCase(params);
        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));
        uint160 sqrtPriceNextX96;
        int24 tickNext;

        {
            uint256 ethAmount = 0.01337 ether;
            token0.mint((address(this)), ethAmount);
            token0.approve(address(this), ethAmount);

            uint256 userBalance01 = uint256(token0.balanceOf(address(this)));
            uint256 userBalance11 = uint256(token1.balanceOf(address(this)));

            (int256 amount0Delta1, int256 amount1Delta1) = pool.swap(address(this), true, ethAmount, extra);

            assertEq(
                uint256(amount0Delta1), userBalance01 - token0.balanceOf(address(this)), "Invalid user ETH swapped"
            );
            assertEq(
                uint256(-amount1Delta1), token1.balanceOf(address(this)) - userBalance11, "Invalid user USDC received"
            );

            // calculate current tick and sqrtPriceX96
            (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
            sqrtPriceNextX96 = Math.getNextSqrtPriceFromInput(params.currentSqrtP, params.liquidity, ethAmount, true);
            tickNext = TickMath.getTickAtSqrtRatio(sqrtPriceNextX96);

            assertEq(tick, tickNext, "invalid current tick");
            assertEq(sqrtPriceX96, sqrtPriceNextX96, "invalid current sqrtP");
        }

        {
            uint256 usdcAmount = 55 ether;
            token1.mint(address(this), usdcAmount);
            token1.approve(address(this), usdcAmount);

            uint256 userBalance02 = uint256(token0.balanceOf(address(this)));
            uint256 userBalance12 = uint256(token1.balanceOf(address(this)));

            (int256 amount0Delta2, int256 amount1Delta2) = pool.swap(address(this), false, usdcAmount, extra);

            assertEq(
                uint256(-amount0Delta2), token0.balanceOf(address(this)) - userBalance02, "invalid user ETH received"
            );
            assertEq(
                uint256(amount1Delta2), userBalance12 - token1.balanceOf(address(this)), "invalid user USDC swapped"
            );

            // calculate current tick and sqrtPriceX96
            (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
            sqrtPriceNextX96 = Math.getNextSqrtPriceFromInput(sqrtPriceNextX96, params.liquidity, usdcAmount, false);
            tickNext = TickMath.getTickAtSqrtRatio(sqrtPriceNextX96);

            assertEq(tick, tickNext, "invalid current tick");
            assertEq(sqrtPriceX96, sqrtPriceNextX96, "invalid current sqrtP");
        }
    }

    function testSwapBuyEthNotEnoughLiquidity() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        setupTestCase(params);

        uint256 swapAmount = 5300 ether;
        console.log(token1.balanceOf(address(pool)));
        token1.mint(address(this), swapAmount);
        token1.approve(address(this), swapAmount);

        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        vm.expectRevert(stdError.arithmeticError);
        pool.swap(address(this), false, swapAmount, extra);
    }

    function testSwapBuyUSDCNotEnoughLiquidity() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        setupTestCase(params);

        uint256 swapAmount = 1.1 ether;
        token0.mint(address(this), swapAmount);
        token0.approve(address(this), swapAmount);

        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        vm.expectRevert(stdError.arithmeticError);
        pool.swap(address(this), true, swapAmount, extra);
    }

    function testSwapInsufficientInputAmount() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: false,
            mintLiquidity: true
        });
        setupTestCase(params);

        vm.expectRevert(UniswapV3Pool.InsufficientInputAmount.selector);
        pool.swap(address(this), false, 42 ether, "");
    }

    function encodeExtra(address token0_, address token1_, address payer) internal pure returns (bytes memory) {
        return abi.encode(UniswapV3Pool.CallbackData({token0: token0_, token1: token1_, payer: payer}));
    }

    function decodeExtra(bytes memory data) internal pure returns (UniswapV3Pool.CallbackData memory) {
        return abi.decode(data, (UniswapV3Pool.CallbackData));
    }

    function setupTestCase(TestCaseParams memory params)
        internal
        returns (uint256 poolBalance0, uint256 poolBalance1)
    {
        token0.mint(address(this), params.wethBalance);
        token1.mint(address(this), params.usdcBalance);

        pool = new UniswapV3Pool(address(token0), address(token1), params.currentSqrtP, params.currentTick);

        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        if (params.mintLiquidity) {
            token0.approve(address(this), params.wethBalance);
            token1.approve(address(this), params.usdcBalance);

            (poolBalance0, poolBalance1) =
                pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity, extra);
        }

        transferInMintCallback = params.transferInMintCallback;
        transferInSwapCallback = params.transferInSwapCallback;
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        if (!transferInMintCallback) return;
        UniswapV3Pool.CallbackData memory extra = decodeExtra(data);
        IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
        IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data) public {
        if (!transferInSwapCallback) return;
        UniswapV3Pool.CallbackData memory extra = decodeExtra(data);
        if (amount0 > 0) {
            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint256(amount0));
        }

        if (amount1 > 0) {
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, uint256(amount1));
        }
    }
}
