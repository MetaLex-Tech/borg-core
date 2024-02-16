
# Metalex Guard

## Overview: Task: Extend Gnosis Safe

Approach: The ideal solution allows for full compatability with Gnosis [Global] Safe: multisig factory contracts, toolset, web ui, cli, 3rd party apps, et al. 

My solution for this task, MetalexGuard, inherets Gnosis' BaseGuard class allowing to be set as a Guard contract for all existing and future Gnosis safe contracts. This is ideal as it can be added to any existing Safe contract and would not require any migration of funds for existing multisigs when adding this Guard. The Guard allows a pre- and post- check for every execTransaction call, effectively allowing us to impose any restrictions necessary for any action attempted by the Safe contract. Future Metalex smart contract products can leverage the Guard and Module classes to extend or restrict Safe functionality to suite the needs of DAO's legal or governance restrictions.

This implementation of MetalexGuard features a whitelist for transaction receipients and amounts, as well as a whitelist for ERC20 token contracts and amounts. Any transaction to a contract that is not on the whitelist is reverted with an appropriate error message. This implementation uses Ownable for access control, to be set by the guarded or an authorizing multisig. All whitelist add/removes require the OnlyOwner modifier. See metalexGuard.t.sol for case and testing coverage. Future iterations of Guard contracts can include much more restrictive, or flexible behavior including whitelisting specific contract methods.

## Testing 

I've created a reusable test setup for this task that will simulate gnosis Safe transactions in a forked EVM environment  My implementation is expecting a deployed 1:1 Gnosis safe and the pk of the Safe owner in .env to create the signed transaction data for approvals. As we build the product, I plan to devote time building a comprensive testing environment which would fully automate the Safe factory deployment as well as our own contract factory deployments and other tools for invariant, fuzz, and edge case forked testing.

### Set up
```sh
  //Set our initial state:
  // 1. Set up the safe
  // 2. Set up the guard with the safe as the owner
  // 3. Allow the safe as a contract on the guard
  // 4. Set balances for tests
  function setUp() public {
    safe = IGnosisSafe(MULTISIG);
    g = new metaLexGuard(MULTISIG);
    executeSingle(getAddContractGuardData(address(g), address(g), 10 ether));
    deal(owner, 2 ether);
    deal(MULTISIG, 2 ether);
    deal(address(usdc), MULTISIG, 10000e18);
    deal(address(dai), MULTISIG, 10000e18);
  }
```

### Example Test Case
```sh
  /// @dev An ERC20 payment that is over the limit of the recepient, not token contract, should still revert.
  function testFailOnUSDCLimit() public {
    executeSingle(getSetGuardData(address(MULTISIG)));
    executeSingle(getAddContractGuardData(address(g), address(usdc), .01 ether));
    executeSingle(getAddRecepientGuardData(address(g), owner, 1 ether));
    executeSingle(getTransferData(address(usdc), owner, 1 ether));
  }
```

```sh
Test result: ok. 12 passed; 0 failed; finished in 4.40s
```

[See full test print out in test-results.txt]



## Install

```sh
forge install
```

required repos:
forge-std
safe-contracts
safe-tools

## Run tests

Check remappings
- Set PRIVATE_KEY in .env
- Tests set to run on Arbitrum Mainnet (Can change RPC and token addresses to test another EVM chain)
-- use a Arb Mainnet RPC for the fork test url
-- Deploy a 1/1 Gnosis Safe multisig 
- Set MULTISIG and OWNER with the addresses used

```sh
forge test --fork-url <url_here> -vvvv --optimize --optimizer-runs 200 --use solc:0.8.19 --via-ir
```

## Compile Contracts

```sh
forge build
```

## Author

Skills evaluation for Luke S./Delphi Labs/Metalex

* Twitter: [@prepopai](https://twitter.com/prepopai)

