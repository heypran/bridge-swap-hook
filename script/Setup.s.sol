// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";
import {Config} from "./Config.s.sol";
import {PortalHook} from "../src/PortalHook.sol";
import {CreateCall} from "../src/CreateCall.sol";

contract SetupScript is Script {
    address constant CREATE2_DEPLOYER =
        address(0x2df22F0cE86Ceea066289Cb94c408a4448f3bD71);
    address constant GOERLI_POOLMANAGER =
        address(0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b);
    address hook;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address pm = Config.POOLMANAGER_OP;
        console.log("PoolManagerScript");
        console.log(address(pm));

        address swapRouter = Config.POOL_SWAP_TEST_OP; // new PoolSwapTest(IPoolManager(pm));
        console.log("PoolSwapTestScript");
        console.log(address(swapRouter));

        address lpRouter = Config.LP_ROUTER_OP; // new PoolModifyLiquidityTest(IPoolManager(pm));

        console.log("PoolModifyLiquidityTestScript");
        console.log(address(lpRouter));

        ///////////////////////////////
        deployHook(address(pm));

        ///////////////////////////////
        // MockToken t0 = new MockToken();
        // t0.initialize("Token0", "T0", 18);
        // t0.mint(
        //     0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        //     100000000000_000 ether
        // );
        // MockToken t1 = new MockToken();
        // t1.initialize("Token1", "T1", 18);
        // t1.mint(
        //     0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        //     1000000000000000000000000_000 ether
        // );

        // // sort the tokens!
        // address token0 = uint160(address(t0)) < uint160(address(t1))
        //     ? address(t0)
        //     : address(t1);
        // address token1 = uint160(address(t0)) < uint160(address(t1))
        //     ? address(t1)
        //     : address(t0);
        // // uint24 swapFee = 4000;
        // int24 tickSpacing = 10;

        // // floor(sqrt(1) * 2^96)
        // // 79228162514264337593543950336 // 1
        // // 1577962434701330639133920932131763
        // // 3543191142285914205922034323214 //2000
        // uint160 startingPrice = 3543191142285914205922034323214;

        // bytes memory hookData = abi.encode(block.timestamp);

        // console.log("Token 0");
        // console.log(address(token0));
        // console.log(MockToken(token0).decimals());
        // console.log("Token 1");
        // console.log(address(token1));
        // console.log(MockToken(token1).decimals());

        // PoolKey memory pool = PoolKey({
        //     currency0: Currency.wrap(token0),
        //     currency1: Currency.wrap(token1),
        //     fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
        //     tickSpacing: tickSpacing,
        //     hooks: IHooks(hook)
        // });

        // // Turn the Pool into an ID so you can use it for modifying positions, swapping, etc.
        // PoolId id = PoolIdLibrary.toId(pool);
        // bytes32 idBytes = PoolId.unwrap(id);

        // console.log("Pool ID Below");
        // console.logBytes32(bytes32(idBytes));

        // pm.initialize(pool, startingPrice, hookData);

        // //////////////////////////////////////////

        // MockToken(token0).approve(address(lpRouter), 100000000000000e18);

        // MockToken(token1).approve(address(lpRouter), 100000000000000e18);

        // MockToken(token0).approve(
        //     AnvilConfig.POOL_SWAP_TEST,
        //     100000000000000e18
        // );

        // MockToken(token1).approve(
        //     address(AnvilConfig.POOL_SWAP_TEST),
        //     100000000000000e18
        // );

        // // optionally specify hookData if the hook depends on arbitrary data for liquidity modification
        // // bytes memory hookData = new bytes(0);

        // // logging the pool ID

        // // Provide 10_000e18 worth of liquidity on the range of [-600, 600]

        // lpRouter.modifyLiquidity(
        //     pool,
        //     IPoolManager.ModifyLiquidityParams(
        //         -100000,
        //         100000, // 196271,
        //         1000_000e18,
        //         0
        //     ),
        //     hookData
        // );

        vm.stopBroadcast();
    }

    function deployHook(address pm) public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory initCode = abi.encodePacked(
            type(PortalHook).creationCode,
            abi.encode(pm, Config.CCIP_ROUTER_OP, Config.LINK_OP)
        );

        CreateCall createCall = CreateCall(CREATE2_DEPLOYER);

        // Mine a salt that will produce a hook address with the correct flags
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(PortalHook).creationCode,
            abi.encode(pm, Config.CCIP_ROUTER_OP, Config.LINK_OP)
        );

        // Deploy the hook using CREATE2
        // PortalHook portalHook = new PortalHook{salt: salt}(
        //     IPoolManager(pm),
        //     Config.CCIP_ROUTER_OP,
        //     Config.LINK_OP
        // );

        address portalHook = createCall.performCreate2(
            0, // value
            initCode,
            salt
        );

        console.log("PortalHook");
        console.log(address(portalHook));

        require(
            address(portalHook) == hookAddress,
            "SetupScript: hook address mismatch"
        );
        hook = hookAddress;
    }
}
