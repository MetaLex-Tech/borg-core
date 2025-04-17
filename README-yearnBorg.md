# Yearn BORG

## BORG Architectures

```mermaid
graph TD
    ychad[ychad.eth<br/>6/9 signers]
    ychadSigner[Signer EOA]
    yearnDaoVoting[Yearn DAO Voting Snapshot]
    
    oracleAddr[oracle]
    
    borg{{Yearn BORG<br>BORG Core}}

    subgraph implants["Implants (Modules)"]
        ejectImplant{{Eject Implant}}
        sudoImplant{{Sudo Implant}}
    end
     
    snapshotExecutor[SnapshotExecutor]
    
    borg -->|"guard"| ychad

    ychad -->|"owner<br>execute(proposalId)"| snapshotExecutor
    
    %% implants -->|modules| ychad
    
    ychadSigner -->|signer| ychad
    ychadSigner -->|"selfEject()"| ejectImplant

    oracleAddr -->|"oracle<br>propose(admin operation)"| snapshotExecutor      
    oracleAddr -->|monitor| yearnDaoVoting
    
    snapshotExecutor -->|"owner<br>guard & module management operation()"| sudoImplant
    snapshotExecutor -->|"owner<br>member management operation()"| ejectImplant
    
    %% Styling (optional, Mermaid supports limited styling)
    classDef default fill:#191918,stroke:#fff,stroke-width:2px,color:#fff;
    classDef borg fill:#191918,stroke:#E1FE52,stroke-width:2px,color:#E1FE52;
    classDef yearn fill:#191918,stroke:#2C68DB,stroke-width:2px,color:#2C68DB;
    classDef safe fill:#191918,stroke:#76FB8D,stroke-width:2px,color:#76FB8D;
    classDef todo fill:#191918,stroke:#F09B4A,stroke-width:2px,color:#F09B4A;
    class borg borg;
    class ejectImplant borg;
    class sudoImplant borg;
    class snapshotExecutor borg;
    class oracleAddr borg;
    class ychad yearn;
    class ychadSigner yearn;
    class yearnDaoVoting yearn;
```

## Restricted Admin Workflows

`ychad.eth` will be prohibited from unilaterally performing the following admin operations:

- Add / remove / swap signers / change threshold
- Add / disable Modules
- Set Guards

Except existing signers, Modules (BORG Implants), Guard (BORG Core) and its set rules,
all coming operations as listed above will require approval of both `ychad.eth` and DAO, with process as such:

1. Operation is initiated on the MetaLeX OS webapp
2. A Snapshot proposal will be submitted via API using Yearn's existing voting settings
3. MetaLeX's Snapshot oracle (`oracle`) will submit the results on-chain to an executor contract (`SnapShotExecutor`), which will have the proposed transaction pending for co-approval
4. After waiting period, `ychad.eth` can co-approve it by executing the operation through the MetaLeX OS webapp
5. After an extra waiting period, anyone can cancel the proposal if it hasn't been executed

### Future On-chain Governance Transition

The veYFI Snapshot governance will be replaced with on-chain governance at some point (ex. `YearnGovExecutor`). 
To integrate with the co-approval process, `YearnGovExecutor` must satisfy:
- Each proposal should have generic transaction fields (`target`, `value`, `calldata`) or equivalents so that `YearnGovExecutor` knows how to execute after the proposal is passed
- Proposals related to the BORG [Restricted Admin Workflows](#restricted-admin-workflows) should be exclusively executed by `ychad.eth` so it enforces the co-approval requirements

The transition process from Snapshot to on-chain governance is listed as follows:

1. A final Snapshot proposal will be submitted to replace `SnapShotExecutor` with `YearnGovExecutor`. 
   More specifically, it is done by transferring `SudoImplant`'s and `EjectImplant`'s owner to `YearnGovExecutor`
2. Once co-approved and executed by `ychad.eth`, the transition process is complete

After the transition, the co-approval process will become:

1. Operation is initiated on the MetaLeX OS webapp
2. An on-chain proposal will be submitted to `YearnGovExecutor`
3. Once the vote passed, `ychad.eth` will co-approve it by executing the operation through the MetaLeX OS webapp 

## Key Parameters

| ID                             | Value      | Descriptions                                            |
|--------------------------------|------------|---------------------------------------------------------|
| `borgIdentifier`               | Yearn BORG | BORG name                                               |
| `borgMode`                     | blacklist  | Every operation is allowed unless blacklisted           |
| `borgType`                     | 3          |                                                         |
| `snapShotWaitingPeriod`        | 3 days     | Waiting period before a proposal can be executed        |
| `snapShotCancelPeriod`         | 2 days     | Extra waiting period before a proposal can be cancelled |
| `snapShotPendingProposalLimit` | 3          | Maximum pending proposals                               |
| `oracle`                       | `address`  | MetaLeX Snapshot oracle                                 |

## Deployment

1. Run the deploy script
   ```bash
   forge script scripts/yearnBorg.s.sol --rpc-url <RPC URL> --optimize --optimizer-runs 200 --use solc:0.8.20 --via-ir --broadcast
   ```

2. If got the following errors, force clean the cache with flag `--force`
   ```
   Error: buffer overrun while deserializing
   ```      
   
3. Take notes of the output Safe TXs (for setting guard & adding modules), for examples:
   ```
   Safe TXs:
    # 0
      to: 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
      value: 0
      data:
   0x610b59250000000000000000000000006faa027c062868424287af2faef3ddaca802bff7

    # 1
      to: 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
      value: 0
      data:
   0x610b5925000000000000000000000000a21f6d7aa0b320b8669caef53f790b1a2ac838d7
   
    # 2
      to: 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
      value: 0
      data:
   0xe19a9dd9000000000000000000000000bc19387f5b8ae73fad41cd2294f928a735c60534
   ```   
4. Ask `ychad.eth` to sign and execute the Safe TXs 

## Tests

### Integration Tests

Test the deployment scripts and verify the results.

```bash
forge test --optimize --optimizer-runs 200 --use solc:0.8.20 --via-ir --fork-url <eth-mainnet-archive-endpoint> --fork-block-number 22268905 --mc YearnBorgTest   
```

### Acceptance Tests

Verify a specific deployment results.

```bash
forge test --optimize --optimizer-runs 200 --use solc:0.8.20 --via-ir --fork-url <eth-mainnet-archive-endpoint> --fork-block-number <deployment-block-number> --mc YearnBorgAcceptanceTest   
```
