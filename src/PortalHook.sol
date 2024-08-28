// SPDX-License-Identifier: GPL-2.0-or-later
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
// import {EtherSenderReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/EtherSenderReceiver.sol";
// EtherSenderReceiver.sol
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
    // TODO remove
    uint64 defaultdestinationChainSelector = 16015286601757825753; // for local testing

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
                beforeSwap: false,
                afterSwap: true, //
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: true, //
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        (
            address receiver,
            bool isBridgeTx,
            uint64 destinationChainSelector
        ) = abi.decode(hookData, (address, bool, uint64));

        // add more validations
        // TODO killswitch
        if (isBridgeTx && destinationChainSelector != 0) {
            // TODO handle ETH
            int128 outputAmount = settleCurrency(
                key,
                delta,
                params.zeroForOne,
                receiver,
                destinationChainSelector
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
        address receiver,
        uint64 destinationChainSelector
    ) internal returns (int128) {
        int128 outputAmount = zeroForOne ? delta.amount1() : delta.amount0();
        Currency outputCurrency = zeroForOne ? key.currency1 : key.currency0;

        poolManager.take(outputCurrency, address(this), uint128(outputAmount));
        IERC20 outputToken = IERC20(Currency.unwrap(outputCurrency));
        IERC20(outputToken).approve(ccipRouter, uint128(outputAmount));

        bridgeTokens(
            receiver,
            address(outputToken),
            uint128(outputAmount),
            destinationChainSelector
        );

        return outputAmount;
    }

    function bridgeTokens(
        address receiver,
        address outputToken,
        uint256 outputAmount,
        uint64 destinationChainSelector
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

        // bridge

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
