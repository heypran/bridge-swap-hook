# Portal (Cross Chain Swap Hook)

### **A template for writing Uniswap v4 Hooks 🦄**

[`Made using V4 Template`](https://github.com/uniswapfoundation/v4-template/generate)

---

## Check Forge Installation

_Ensure that you have correctly installed Foundry (Forge) and that it's up to date. You can update Foundry by running:_

```
foundryup
```

## Set up

_requires [foundry](https://book.getfoundry.sh)_

```
forge install
forge test
```

---

###### Cross Chain Swap- CCIP Hook

A hook to perform cross chain swaps using CCIP.

With increase in number of L2s and web3 applications with good use case being scattered across different L2s, users has the need to bridge tokens more than ever.

This demand is also fueled by various DEFI yield opportunities which almost always exists in the market since DEFI is still innovating, with new applications such as Pendle, Eigen, Ethena, etc.

The swap and bridging solution can help improve user experience without doing multiple transactions across different dexes and bridges. Moreover, most of the bridging solution out there are mostly centralized, CCIP is more reliable, decentralized and also backed by a renowned brand. The established trust in Uniswap and Chainlink may help in driving adoption for such solutions.

Improvements

- Add signature based verification for hook data, to make it more secure to provide swapper address and destination chain etc.
- Handle some edge cases as marked as TODOs in the code.
- Apart from improving existing solutions to add support for native ETH bridging etc.
