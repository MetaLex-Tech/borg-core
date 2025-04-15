# Yearn BORG

## BORG Architectures

```mermaid
graph TD
    ychad[ychad.eth<br/>6/9 signers]
    ychadSigner[ychad.eth signer]
    yearnDaoVoting[Yearn DAO Voting Snapshot]
    
    oracleAddr[oracle]
    
    borg{{Yearn BORG<br>BORG Core}}
    
    ejectImplant{{Eject Implant}}
     
    snapshotExecutor[SnapshotExecutor]

    ychad -->|"owner / guard by"| borg
    ychad -->|"owner / execute()"| snapshotExecutor
    
    ychadSigner -->|signer| ychad
    ychadSigner -->|"selfEject()"| ejectImplant

    oracleAddr -->|"oracle / propose(member management func)"| snapshotExecutor      
    oracleAddr -->|monitor| yearnDaoVoting
    
    ejectImplant -->|module| ychad
    
    snapshotExecutor -->|"owner / member management func()"| ejectImplant
    
    %% Styling (optional, Mermaid supports limited styling)
    classDef default fill:#191918,stroke:#fff,stroke-width:2px,color:#fff;
    classDef borg fill:#191918,stroke:#E1FE52,stroke-width:2px,color:#E1FE52;
    classDef safe fill:#191918,stroke:#76FB8D,stroke-width:2px,color:#76FB8D;
    classDef todo fill:#191918,stroke:#F09B4A,stroke-width:2px,color:#F09B4A;
    class borg borg;
    class ejectImplant borg;
    class snapshotExecutor borg;
    class oracleAddr borg;
    class ychad safe;
```

## Member Management Workflow

1. Action is initiated on the MetaLeX OS webapp
2. A Snapshot proposal will be submitted via API using Yearn's existing voting settings
3. MetaLeX's Snapshot oracle will submit the results onchain to an executor contract, which will have the proposed transaction pending for co-approval
4. ychad.eth will submit co-approval / execute the action through the MetaLeX OS webapp

## Deployment

1. Run the deploy script
   ```bash
   forge script scripts/yearnBorg.s.sol --rpc-url <RPC URL> --optimize --optimizer-runs 200 --use solc:0.8.20 --via-ir --broadcast
   ```

2. If got the following errors, force clean the cache with flag `--force`
   ```
   Error: buffer overrun while deserializing
   ```

## Tests

### Integration Tests

Test the deployment scripts and verify the results.

```bash
forge test --optimize --optimizer-runs 200 --use solc:0.8.20 --via-ir --fork-url <eth-mainnet-archive-endpoint> --fork-block-number 22268905 --mc YearnBorgTest   
```

### Acceptance Tests

Verify the specified deployment results.

```bash
forge test --optimize --optimizer-runs 200 --use solc:0.8.20 --via-ir --fork-url <eth-mainnet-archive-endpoint> --fork-block-number <deployment-block-number> --mc YearnBorgAcceptanceTest   
```
