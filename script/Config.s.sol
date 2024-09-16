// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Config {
    address public constant CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    address public constant POOLMANAGER_OP =
        address(0x7B2B5A2c377B34079589DDbCeA20427cdb7C8219);

    address public constant POOL_SWAP_TEST_OP =
        address(0x1C7915edd185303a374fB7C332478C7dD599501a);
    address public constant LP_ROUTER_OP =
        address(0x1C76e579b40739f33d6Ee75741Be91bc361076c0);

    address public constant HOOK_ADDRESS =
        address(0xCE5DBC14F6D414cB5e040C079D129A1C21f3A080);

    address public constant CCIP_ROUTER_OP =
        address(0x114A20A10b43D4115e5aeef7345a1A71d2a60C57);
    // 0xE4aB69C077896252FAFBD49EFD26B5D171A32410

    address public constant LINK_OP =
        address(0xE4aB69C077896252FAFBD49EFD26B5D171A32410);

    address public constant MUNI_ADDRESS =
        address(0xa513E6E4b8f2a923D98304ec87F64353C4D5C853); // mUNI deployed to GOERLI -- insert your own contract address here
    address public constant MUSDC_ADDRESS =
        address(0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9); // mUSDC deployed to GOERLI -- insert your own contract address here
}
