# Yearn BORG

## BORG Architectures

```mermaid
graph TD
    ychad[ychad.eth<br/>6/9 signers]
    yearnDaoVoting[Yearn DAO Snapshot Voting]
    
    %% TODO TBD
    tempOwner[/TODO owner?/]
    recoveryAddr[/TODO recovery address?/]
    oracleAddr[/TODO oracle address?/]
    
    borg{{Yearn BORG<br>BORG Core}}
    
    subgraph implants
        failSafeImplant{{Failsafe Implant}}
        ejectImplant{{Eject Implant}}
        
        signatureCondition{{Signature Condition}}        
    end
    
    snapshotExecutor[SnapshotExecutor<br><br>TODO Waiting period?]
    
    ychad -->|"sign() / revokeSignature()"| signatureCondition

    oracleAddr -->|monitor| yearnDaoVoting
    oracleAddr -->|"propose(addOwner() / swapOwner())"| snapshotExecutor      
    
    borg -->|guard| ychad
    
    implants -->|modules| ychad
    
    failSafeImplant -->|failSafe| ejectImplant
    
    signatureCondition -->|conditions| ejectImplant
    
    snapshotExecutor -->|"addOwner() / swapOwner()"| ejectImplant
    
    tempOwner -->|owner| borg
    tempOwner -->|owner| implants
    
    recoveryAddr -->|recovery address| failSafeImplant
    
    %% Styling (optional, Mermaid supports limited styling)
    classDef default fill:#191918,stroke:#fff,stroke-width:2px,color:#fff;
    classDef borg fill:#191918,stroke:#E1FE52,stroke-width:2px,color:#E1FE52;
    classDef safe fill:#191918,stroke:#76FB8D,stroke-width:2px,color:#76FB8D;
    classDef todo fill:#191918,stroke:#F09B4A,stroke-width:2px,color:#F09B4A;
    class borg borg;
    class failSafeImplant borg;
    class ejectImplant borg;
    class voteImplant borg;
    class signatureCondition borg;
    class ychad safe;
    class tempOwner todo;
    class recoveryAddr todo;
    class oracleAddr todo;
    class govExecutor todo;
    class snapshotProposer todo;
```

## Member Management Voting Workflow

Example below demonstrates adding `alice` as a new signer to `ychad.eth`.

1. DAO proposes to add `alice` to `ychad.eth`
2. Once passed on Snapshot voting, `oracle` calls `SnapshotExecutor.propose(addOwner(alice))`
3. `ychad.eth` does one of the following:
   - To approve it, call `SignatureCondition.sign()` if not yet done
   - To reject it, call `SignatureCondition.revokeSignature()` if not yet done
3. Once `ychad.eth` approved and the proposal waiting period is passed, any can call `SnapshotExecutor.execute(proposalId)`
4. `alice` is now added to `ychad.eth`
