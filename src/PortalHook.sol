// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import {Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

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
                beforeSwap: false, //
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

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        (address receiver, bool isBridgeTx) = abi.decode(
            hookData,
            (address, bool)
        );

        if (isBridgeTx) {
            int128 outputAmount = settleCurrency(
                key,
                delta,
                params.zeroForOne,
                receiver
            );
            return (BaseHook.afterSwap.selector, outputAmount);
        }

        // bool exactInput = params.amountSpecified < 0;

        // int128 unspecifiedAmount = exactInput == params.zeroForOne
        //     ? delta.amount1()
        //     : delta.amount0();
        // console.logInt(unspecifiedAmount);

        return (BaseHook.afterSwap.selector, 0);
    }

    function settleCurrency(
        PoolKey memory key,
        BalanceDelta delta,
        bool zeroForOne,
        address receiver
    ) internal returns (int128) {
        int128 outputAmount = zeroForOne ? delta.amount1() : delta.amount0();

        IERC20 outputToken;

        if (zeroForOne) {
            poolManager.take(
                key.currency1,
                address(this),
                uint128(outputAmount)
            );

            outputToken = IERC20(Currency.unwrap(key.currency1));
            IERC20(outputToken).approve(ccipRouter, uint128(outputAmount));
        } else {
            poolManager.take(
                key.currency0,
                address(this),
                uint128(outputAmount)
            );
            outputToken = IERC20(Currency.unwrap(key.currency0));
            IERC20(outputToken).approve(ccipRouter, uint128(outputAmount));
        }

        bridgeTokens(receiver, address(outputToken), uint128(outputAmount));

        return outputAmount;
    }

    function bridgeTokens(
        address receiver,
        address outputToken,
        uint256 outputAmount
    ) internal {
        // TODO refactor

        Client.EVMTokenAmount[]
            memory tokensToSendDetails = new Client.EVMTokenAmount[](1);

        Client.EVMTokenAmount memory tokenToSendDetails = Client
            .EVMTokenAmount({
                token: address(outputToken),
                amount: outputAmount
            });

        tokensToSendDetails[0] = tokenToSendDetails;

        // brdige

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            tokenAmounts: tokensToSendDetails,
            extraArgs: "",
            feeToken: bridgeFeeTokenType == PayFeesIn.LINK
                ? linkToken
                : address(0)
        });

        uint256 fee = IRouterClient(ccipRouter).getFee(
            destinationChainSelector,
            message
        );

        bytes32 messageId;

        if (bridgeFeeTokenType == PayFeesIn.LINK) {
            LinkTokenInterface(linkToken).approve(ccipRouter, fee);
            messageId = IRouterClient(ccipRouter).ccipSend(
                destinationChainSelector,
                message
            );
        } else {
            messageId = IRouterClient(ccipRouter).ccipSend{value: fee}(
                destinationChainSelector,
                message
            );
        }
    }
}
