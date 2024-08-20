// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

//Adapter interface for custom auth roles. Allows extensibility for different auth protocols i.e. hats.
interface IAuthAdapter {
    function isAuthorized(address user) external view returns (uint256);
}