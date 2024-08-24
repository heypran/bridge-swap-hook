// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import "forge-std/console.sol";

contract PortalHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    enum PayFeesIn {
        Native,
        LINK
    }

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => uint256 count) public afterSwapCount;

    mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;

    // CCIP
    address immutable ccipRouter;
    address immutable linkToken;

    PayFeesIn public bridgeFeeTokenType = PayFeesIn.Native; // for local testing
    uint64 destinationChainSelector = 16015286601757825753; // for local testing

    constructor(
        IPoolManager _poolManager,
        address _router,
        address _link
    ) BaseHook(_poolManager) {
        ccipRouter = _router;
        linkToken = _link;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true, //
                afterSwap: true, //
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: true, //
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        beforeSwapCount[key.toId()]++;
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // TODO remove later
        afterSwapCount[key.toId()]++;

        // isBridgeTx

        int128 outputAmount = settleCurrency(key, delta, params.zeroForOne);

        // bool exactInput = params.amountSpecified < 0;

        // int128 unspecifiedAmount = exactInput == params.zeroForOne
        //     ? delta.amount1()
        //     : delta.amount0();
        // console.logInt(unspecifiedAmount);

        return (BaseHook.afterSwap.selector, outputAmount);
    }

    function settleCurrency(
        PoolKey memory key,
        BalanceDelta delta,
        bool zeroForOne
    ) internal returns (int128) {
        int128 outputAmount = zeroForOne ? delta.amount1() : delta.amount0();
        console.log("deltas");
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());

        if (zeroForOne) {
            poolManager.take(
                key.currency1,
                address(this),
                uint128(outputAmount)
            );
        } else {
            poolManager.take(
                key.currency0,
                address(this),
                uint128(outputAmount)
            );
        }

        return outputAmount;
    }
}
