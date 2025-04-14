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
     
    signatureCondition[Signature Condition]        

    snapshotExecutor[SnapshotExecutor]

    ychad -->|"owner / guard by"| borg
    ychad -->|"sign() / revokeSignature()"| signatureCondition
    
    ychadSigner -->|signer| ychad
    ychadSigner -->|"selfEject()"| ejectImplant

    oracleAddr -->|monitor| yearnDaoVoting
    oracleAddr -->|"propose(member management func)"| snapshotExecutor      
    
    ejectImplant -->|module| ychad
    
    signatureCondition -->|"conditions(member management func)"| ejectImplant
    
    snapshotExecutor -->|owner| ejectImplant
    snapshotExecutor -->|"call member management func"| ejectImplant
    
    %% Styling (optional, Mermaid supports limited styling)
    classDef default fill:#191918,stroke:#fff,stroke-width:2px,color:#fff;
    classDef borg fill:#191918,stroke:#E1FE52,stroke-width:2px,color:#E1FE52;
    classDef safe fill:#191918,stroke:#76FB8D,stroke-width:2px,color:#76FB8D;
    classDef todo fill:#191918,stroke:#F09B4A,stroke-width:2px,color:#F09B4A;
    class borg borg;
    class ejectImplant borg;
    class signatureCondition borg;
    class snapshotExecutor borg;
    class oracleAddr borg;
    class ychad safe;
```

## Member Management Workflow

Example below demonstrates adding `alice` as a new signer to `ychad.eth`.

1. DAO proposes adding `alice` to `ychad.eth` through SnapshotExecutor service
2. Once passed on Snapshot voting, `oracle` calls `SnapshotExecutor.propose(addOwner(alice))`
3. `ychad.eth` does one of the following:
   - To approve it, call `SignatureCondition.sign()` if not yet done
   - To reject it, call `SignatureCondition.revokeSignature()` if not yet done
3. Once `ychad.eth` approved and the proposal waiting period is passed, anyone can call `SnapshotExecutor.execute(proposalId)`
4. `alice` is now added to `ychad.eth`
