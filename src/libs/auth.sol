// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAuthAdapter {
    function isAuthorized(address user) external view returns (bool);
}

bytes32 constant OWNER_ROLE = keccak256("OWNER");
bytes32 constant ADMIN_ROLE = keccak256("ADMIN");
bytes32 constant PRIVILEGED_ROLE = keccak256("PRIVILEGED");

/// @title Auth
/// @notice Simple ACL with extensibility for different role adapters
contract Auth {
    /// @dev user not authorized with given role
    error NotAuthorized(bytes32 role, address user);

    mapping(bytes32 => mapping(address => bool)) public hasRole;
    // Mapping from role to adapters
    mapping(bytes32 => IAuthAdapter) public roleAdapters;

    constructor() {
        _updateRole(msg.sender, OWNER_ROLE, true);
    }

    function updateRole(
        address user,
        bytes32 role,
        bool authorized
    ) external {
        onlyRole(OWNER_ROLE, msg.sender);
        _updateRole(user, role, authorized);
    }

    function setRoleAdapter(bytes32 role, IAuthAdapter adapter) external {
        onlyRole(OWNER_ROLE, msg.sender);
        roleAdapters[role] = adapter;
    }

    function onlyRole(bytes32 role, address user) public view {
        bool authorized = hasRole[role][user];
        IAuthAdapter adapter = roleAdapters[role];
        if (address(adapter) != address(0)) {
            authorized = authorized || adapter.isAuthorized(user);
        }
        if (!authorized) {
            revert NotAuthorized(role, user);
        }
    }

    function _updateRole(
        address user,
        bytes32 role,
        bool authorized
    ) internal {
        hasRole[role][user] = authorized;
    }
}

abstract contract GlobalACL {
    Auth public immutable AUTH;

    constructor(Auth _auth) {
        require(address(_auth) != address(0), "GlobalACL: zero address");
        AUTH = _auth;
    }

    modifier onlyOwner() {
        AUTH.onlyRole(OWNER_ROLE, msg.sender);
        _;
    }

    modifier onlyAdmin() {
        AUTH.onlyRole(ADMIN_ROLE, msg.sender);
        _;
    }

    modifier onlyPriv() {
        AUTH.onlyRole(PRIVILEGED_ROLE, msg.sender);
        _;
    }


    modifier onlyRole(bytes32 _role) {
        AUTH.onlyRole(_role, msg.sender);
        _;
    }
}
