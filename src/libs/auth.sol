pragma solidity ^0.8.19;


bytes32 constant OWNER_ROLE = keccak256("OWNER");
bytes32 constant ADMIN_ROLE = keccak256("ADMIN");
bytes32 constant PRIVILEGED_ROLE = keccak256("PRIVILEGED");


/// @title Auth
/// @notice Simple  ACL
contract Auth {
    /// @dev user not authorized with given role
    error NotAuthorized(bytes32 _role, address _user);

    mapping(bytes32 => mapping(address => bool)) public hasRole;

    constructor() {
        _updateRole(msg.sender, OWNER_ROLE, true);
    }

    function updateRole(
        address _user,
        bytes32 _role,
        bool _authorized
    ) external {
        onlyRole(OWNER_ROLE, msg.sender);
        _updateRole(_user, _role, _authorized);
    }

    function onlyRole(bytes32 _role, address _user) public view {
        if (!hasRole[_role][_user]) {
            revert NotAuthorized(_role, _user);
        }
    }

    function _updateRole(
        address _user,
        bytes32 _role,
        bool _authorized
    ) internal {
        hasRole[_role][_user] = _authorized;
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

    modifier onlyRole(bytes32 _role) {
        AUTH.onlyRole(_role, msg.sender);
        _;
    }
}
