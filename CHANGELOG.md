# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- src/implants/sudoImplant.sol
  - A Module (implant) for enforcing BORG, DAO co-approvals on Safe admin operations such as toggling Modules or setting Guards

- src/libs/governance/snapShotExecutor.sol
  - An off-chain (snapshot) voting coordinator contract that enforces BORG, DAO co-approvals on proposals

- scripts/yearnBorg.s.sol
  - Scripts for deploying Yearn BORG contracts

### Updated

- src/borgCore.sol
  - Blocks delegate calls by default in blacklist mode and allow whitelisting specific contracts
  - Maintains the same behaviors in whitelist mode

- src/implants/ejectImplant.sol
  - Allows admin to allow/disallow a member to reduce threshold when resigning
