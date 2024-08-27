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
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PortalHook} from "../src/PortalHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PositionConfig} from "v4-periphery/src/libraries/PositionConfig.sol";
import {SortTokens} from "v4-core/test/utils/SortTokens.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {CCIPLocalSimulator, IRouterClient, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract PortalHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    PortalHook hook;
    PoolId poolId;

    uint256 tokenId;
    PositionConfig config;

    // CCIP
    CCIPLocalSimulator public ccipLocalSimulator;
    address alice = vm.addr(1);
    address bob;
    IRouterClient ccipRouter;
    uint64 destinationChainSelector;
    BurnMintERC677Helper ccipBnMToken;
    BurnMintERC677Helper currencyC0;
    BurnMintERC677Helper currencyC1;
    LinkToken linkToken;

    function setUp() public {
        ccipLocalSimulator = new CCIPLocalSimulator();
        (
            uint64 chainSelector,
            IRouterClient sourceRouter,
            ,
            ,
            LinkToken link,
            BurnMintERC677Helper ccipBnM, // not using this

        ) = ccipLocalSimulator.configuration();

        ccipRouter = sourceRouter;
        destinationChainSelector = chainSelector;

        linkToken = link;

        // BurnMintERC677Helper Create Liquidity Pool tokens
        currencyC0 = new BurnMintERC677Helper("cc0", "cc0");
        currencyC1 = new BurnMintERC677Helper("cc1", "cc1");

        // Add support in CCIP
        ccipLocalSimulator.supportNewToken(address(currencyC0));
        ccipLocalSimulator.supportNewToken(address(currencyC1));

        // Wrap for usage with v4
        (Currency currencyC0W, Currency currencyC1W) = SortTokens.sort(
            MockERC20(address(currencyC0)),
            MockERC20(address(currencyC1))
        );

        // creates the pool manager, utility routers
        deployFreshManagerAndRouters();
        //deployMintAndApprove2Currencies();

        // Approve router
        address modifyLiqRouter = address(modifyLiquidityRouter);
        MockERC20(address(currencyC0)).approve(modifyLiqRouter, 10000000 ether);
        MockERC20(address(currencyC1)).approve(modifyLiqRouter, 10000000 ether);
        MockERC20(address(currencyC0)).approve(
            address(swapRouter),
            10000000 ether
        );
        MockERC20(address(currencyC1)).approve(
            address(swapRouter),
            10000000 ether
        );

        // mint some ccip tokens to hook
        // (internal function is modified to mint
        // many tokens in one go)
        // alternative is run the internal function in a loop
        currencyC0.drip(address(this), 2 ** 255);
        currencyC1.drip(address(this), 2 ** 255);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4441 << 144) // Namespace the hook to avoid collisions
        );

        deployCodeTo(
            "PortalHook.sol:PortalHook",
            abi.encode(manager, address(ccipRouter), address(linkToken)),
            flags
        );
        hook = PortalHook(payable(flags));

        // Create the pool
        key = PoolKey(currencyC0W, currencyC1W, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // SQRT 0.001 18,6 - 79228162514264337593543950
        // Provide full-range liquidity to the pool
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(60),
                TickMath.maxUsableTick(60),
                10_000 ether,
                0
            ),
            ZERO_BYTES
        );
    }

    function dripToUser(
        Currency currency,
        address user,
        uint256 amount
    ) internal {
        currencyC1.drip(address(alice), 10 ether);
        currencyC1.drip(address(alice), 10 ether);
    }

    function test_SwapZeroForOneExactInput_noBridge() public {
        // positions were created in setup()

        uint256 balanceOfC1AliceBefore = currencyC1.balanceOf(address(alice));
        assertEq(balanceOfC1AliceBefore, 0);

        // Perform a test swap //

        // pass alice address to receive bridge funds & set bridging to false
        bytes memory hookData = abi.encode(address(alice), false);

        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountSpecified,
            hookData
        );

        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        // alice balance should be zero
        uint256 balanceOfC1AliceAfter = currencyC1.balanceOf(address(alice));
        assertEq(balanceOfC1AliceAfter, 0);
    }

    function test_SwapOneForZeroExactInput_noBridge() public {
        // positions were created in setup()

        uint256 balanceC0AliceBefore = currencyC0.balanceOf(address(alice));
        assertEq(balanceC0AliceBefore, 0);

        // Perform a test swap //

        // pass alice address to receive bridge funds & set bridging to false
        bytes memory hookData = abi.encode(address(alice), false);

        // Perform a test swap //
        bool zeroForOne = false;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountSpecified,
            hookData
        );
        // ------------------- //

        assertEq(int256(swapDelta.amount1()), amountSpecified);

        // alice should receive bridged funds
        uint256 balanceC0AliceAfter = currencyC0.balanceOf(address(alice));
        assertEq(balanceC0AliceAfter, 0);
    }

    function test_SwapAndBridge_zeroForOne() public {
        // positions were created in setup()

        // MockERC20(address(currencyC0)).approve(address(hook), 1 ether);

        uint256 balanceC0AliceBefore = currencyC0.balanceOf(alice);
        uint256 balanceC1AliceBefore = currencyC1.balanceOf(alice);

        // Perform a test swap //
        bytes memory hookData = abi.encode(alice, true);
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountSpecified,
            hookData
        );
        // ------------------- //

        uint256 balanceC0AliceAfter = currencyC0.balanceOf(alice);
        uint256 balanceC1AliceAfter = currencyC1.balanceOf(alice);

        // Input Token
        // assertEq(
        //     balanceC0AliceAfter,
        //     balanceC0AliceBefore - uint256(-amountSpecified)
        // );

        // Output Token
        // TODO improve this
        console.log(balanceC1AliceAfter);
        assertEq(balanceC1AliceAfter, 996900609009281774);

        assertEq(int256(swapDelta.amount0()), amountSpecified);
    }

    function test_SwapAndBridge_oneForZero() public {
        // positions were created in setup()

        // MockERC20(address(currencyC0)).approve(address(hook), 1 ether);

        uint256 balanceC0AliceBefore = currencyC0.balanceOf(alice);
        uint256 balanceC1AliceBefore = currencyC1.balanceOf(alice);

        // Perform a test swap //
        bytes memory hookData = abi.encode(alice, true);
        bool zeroForOne = false;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountSpecified,
            hookData
        );
        // ------------------- //

        uint256 balanceC0AliceAfter = currencyC0.balanceOf(alice);
        uint256 balanceC1AliceAfter = currencyC1.balanceOf(alice);

        // Input Token
        // assertEq(
        //     balanceC0AliceAfter,
        //     balanceC0AliceBefore - uint256(-amountSpecified)
        // );

        // Output Token
        // TODO improve this
        console.log(balanceC0AliceAfter);
        assertEq(balanceC0AliceAfter, 996900609009281774);

        assertEq(int256(swapDelta.amount1()), amountSpecified);
    }
}
