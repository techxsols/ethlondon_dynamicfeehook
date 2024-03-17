// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {VolBasedDynamicFeeHook} from "../src/VolBasedDynamicFee.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SwapFeeLibrary} from "v4-core/src/libraries/SwapFeeLibrary.sol";
import {MarketDataProvider} from "../src/MarketDataProvider.sol";

contract LowVolDynamicFeeHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for uint256;

    VolBasedDynamicFeeHook hook;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), 5384450); // 2 Feb 2024
        assertEq(block.number, 5384450);

        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        MarketDataProvider md = new MarketDataProvider();
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this), flags, type(VolBasedDynamicFeeHook).creationCode, abi.encode(address(manager), address(md))
        );
        hook = new VolBasedDynamicFeeHook{salt: salt}(IPoolManager(address(manager)), md);
        require(address(hook) == hookAddress, "VolBasedDynamicFeeHookTest: hook address mismatch");

        // Create the pool with dynamic fees enabled
        key = PoolKey(currency0, currency1, SwapFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(address(hook)));
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Provide liquidity to the pool
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, 10000 ether), ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-120, 120, 1000 ether), ZERO_BYTES
        );
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10000 ether),
            ZERO_BYTES
        );
    }

    function test_low_vol_low_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        assertEq(fee, 1034); // 0.1034%
        assertEq(int256(swapDelta.amount0()), amountSpecified);
        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), -int256(token1Output));

        assertEq(token1Output, 998918481638098662);
    }

    function test_low_vol_mid_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 15 ether;

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        assertEq(fee, 1224); // 0.1224%
        assertEq(int256(swapDelta.amount0()), amountSpecified);
        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), -int256(token1Output));

        assertEq(token1Output, 14970959546362944145);
    }

    function test_low_vol_high_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 30 ether;

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        assertEq(fee, 1426); // 0.1426%
        assertEq(int256(swapDelta.amount0()), amountSpecified);
        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), -int256(token1Output));

        assertEq(token1Output, 29914545874668212948);
    }
}
