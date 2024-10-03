# RWA Ecosystem

## What is the "RWA Ecosystem"?

The RWA Ecosystem is a collection of smart contracts mentioned in this README that encapsulate a collection of products built by the Tangible-REAL team to bring a yield generating and governance protocol to active investors. All contracts in this repo make up this ecosystem and interact with one another to bring the ecosystem to life.

## RWA Token

The RWA ERC-20 token is meant to replace the TNGBL token from Polygon. However, the RWA token does include a few different mechanisms that didn't exist before. Primarily, it consists of a taxing system that taxes buys & sells. By default the fee is 5% and is not applied on pier-to-pier transfers. Any holders of TNGBL tokens can migrate their tokens to RWA via our migration page.

Holders of RWA can lock their tokens in exchange for a veRWA NFT. This NFT grants you voting rights and revenue share.

## VotingEscrowRWA (veRWA)

This is meant to replace the 3,3+ Passive Income NFTs. Holders will be eligible to receive a portion of revenue share from the various streams through which the protocol generates revenue. All revenue will be sent to the **RevenueDistributor** contract where it is then distributed to the necessary **RevenueStream** contract where it can be claimed by eligible stakeholders. They can either claim it from the **RevenueStream** contract one by one as the revenue’s raw token, or claim all revenue through the **RevStreamSingleAsset** contract as a single asset.

You can read more about veRWA NFTs. You can also migrate from the 3,3+ NFTs on our migration page as well.

## Liquid Staked RWA

stRWA is a wrapped, rebasing version of veRWA. RWA holders can deposit/stake their tokens in exchange for stRWA tokens (minted 1-to-1). stRWA is natively cross-chain, using LZ OFT technology. This allows stRWA holders to bridge to and from various chains in the network.

The RWA staked will be locked into a single veRWA position which will earn passive yield. The yield accrued by the protocol will be distributed amongst the stRWA holders via rebase. It is also important to mention that 20% of rewards will be used to buy and burn RWA, while the remaining rewards are added to the lock position to earn the protocol more yield.


## Migration

This ecosystem takes advantage of LayerZero v1 to facilitate cross-chain messaging. The **CrossChainMigrator** contract will spark the migration by taking the current state of the migrated asset and transferring that state over to the new contracts on Real Chain.

Users who migrate their 3,3+ NFT will receive a veRWA NFT with an identical locked balance. Users who migrate TNGBL tokens will receive 1-to-1 minted RWA tokens.

The CrossChainMigrator will send a message to the LayerZero endpoint on Polygon to then be passed by their Relayer over to Real Chain where the message will be passed to the **RealReceiver** smart contract.

# Contracts

## Token

- [RWAToken](./src/RWAToken.sol) - Replaces TNGBL - ERC-20 contract for RWA token. This contract facilitates any minting or transferring of RWA tokens.
- [RoyaltyHandler](./src/RoyaltyHandler.sol) - Handles any royalties accrued from RWA swaps.
- [RWAVotingEscrow](./src/governance/RWAVotingEscrow.sol) - Replaces PassiveIncomeNFT - An ERC-721 token contract that inherits VotesUpgradeable and assigns voting power based on the quantity of locked tokens and their vesting duration. It is designed to incentivize long-term holding and participation in governance. Locked token of choice is RWAToken.

## Staking

- [stRWA](./src/staking/stRWA.sol) - This token is a cross-chain rebasing token. This token can only be minted in exchange for RWA tokens.
- [TokenSilo](./src/staking/TokenSilo.sol) - Serves as the token silo for the veRWA token being used as collateral for stRWA holders. This contract manages the veRWA lock position that earns the stRWA holders passive yield.
- [stRWARebaseManager](./src/staking/stRWARebaseManager.sol) - This contract manages the rebase and skim logic used to execute rebases on the stRWA contract and perform any skims necessary from a pool within the ecosystem.

## Governance

- [VotingEscrowVesting](./src/governance/VotingEscrowVesting.sol) - The VotingEscrowVesting contract manages the vesting schedules for tokens locked in the VotingEscrow system. It allows users to deposit their VotingEscrow tokens, undergo a vesting period, and then either withdraw them back or claim the underlying locked tokens upon vesting completion.
- [DelegateFactory](./src/governance/DelegateFactory.sol) - This contract acts as a factory for creating Delegator contracts.
- [Delegator](./src/governance/Delegator.sol) - This contract is used to delegate voting power of a single veRWA NFT to a specified account. This contract will be created by the DelegateFactory and will be assigned a delegatee. Upon creation, a veRWA NFT will be deposited and the voting power is delegated to the delegatee.

## Migration

- [CrossChainMigrator](./src/CrossChainMigrator.sol) - This contract handles migration of TNGBL holders and 3,3+ NFT holders. This contract will spark a migration from Polygon to Tangible's new Real Chain.
- [RealReceiver](./src/RealReceiverNFT.sol) - This contract inherits `ILayerZeroReceiver` and facilitates the migration message from the source on Polygon to the migration method on the destination contract. This contract specifically handles the migration messages for 3,3+ NFTs and TNGBL tokens. Once this contract receives the message from the REAL LZ endpoint, it’ll facilitate the completion of migration and mint the migrator the necessary NFT(s) on veRWA or $RWA on RWAToken.

## Revenue Management

- [RevenueDistributor](./src/RevenueDistributor.sol) - This contract is in charge of routing revenue streams to the RevenueStreamETH contract. This contract will hold all assets until the distribute method is executed. When distributing, ERC-20 assets are converted to ETH before being sent to the RevenueStreamETH contract.
- [RevenueStreamETH](./src/RevenueStreamETH.sol) - This contract facilitates the distribution of claimable ETH revenue to veRWA shareholders.

# Testing

This testing and development framework uses [foundry](https://book.getfoundry.sh/), a smart contract development toolchain that manages your dependencies, compiles your project, runs tests, deploys, and lets you interact with the chain from the command-line and via Solidity scripts.

To build project using forge:
`forge b` 

To run tests using forge:
`forge test` 

**Note**: Ensure you have the proper environment variables set.

## Tests

### Token

- [RWATokenTest](./test/RWAToken.t.sol) - Contains basic unit tests and integration tests for **RWAToken**.

### Staking

- [StakedRWATestUtility](./test/staking/utils/stRWA.setUp.sol) - Contains the deployment & configuration of the staking contracts and utility functions needed for all **StakedRWATest** test files.
- [StakedRWADepositTest](./test/staking/stRWA.deposit.t.sol) - Contains unit tests for **stRWA**. Primarily in regards to depositing/staking.
- [StakedRWARedeemTest](./test/staking/stRWA.redeem.t.sol) - Contains unit tests for **stRWA**. Primarily in regards to redeeming/unstaking.
- [StakedRWARebaseTest](./test/staking/stRWA.rebasing.t.sol) - Contains unit tests for **stRWA**. Primarily in regards to rebasing.

### Governance

- [RWAVotingEscrowTest](./test/RWAVotingEscrow.t.sol) - This test file contains the basic unit testing for the **RWAVotingEscrow** contract.
- [DelegationTest](./test/Delegation.t.sol) - This test file contains the basic unit testing for the **DelegateFactory** and **Delegator** contract.

### Migration

- [MigrationTest](./test/Migration.t.sol) - This test file contains the basic unit testing for the **CrossChainMigrator** contract.
- [MirgationIntegrationTest](./test/MigrationIntegration.t.sol) - This test file contains the basic integration testing for migration contracts. These tests reference the deployed Polygon contracts of [TangibleERC20](https://polygonscan.com/address/0x49e6A20f1BBdfEeC2a8222E052000BbB14EE6007) and [PassiveIncomeNFT](https://polygonscan.com/address/0xDc7ee66c43f35aC8C1d12Df90e61f05fbc2cD2c1).

### Revenue Management

- [RevenueDistributorTest](./test/RevenueDistribution.t.sol) - This test file contains the basic unit tests for the **RevenueDistributor** contract.
- [RWARevenueStreamETHTest](./test/RevenueStreamETH.t.sol) - This test file contains the basic unit tests for the **RevenueStreamETH** contract.