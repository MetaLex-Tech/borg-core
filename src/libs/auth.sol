// SPDX-License-Identifier: AGPL-3.0-only

/*                                                                                           
    _/_/_/      _/_/    _/_/_/      _/_/_/        _/_/    _/    _/  _/_/_/_/_/  _/    _/   
   _/    _/  _/    _/  _/    _/  _/            _/    _/  _/    _/      _/      _/    _/    
  _/_/_/    _/    _/  _/_/_/    _/  _/_/      _/_/_/_/  _/    _/      _/      _/_/_/_/     
 _/    _/  _/    _/  _/    _/  _/    _/      _/    _/  _/    _/      _/      _/    _/      
_/_/_/      _/_/    _/    _/    _/_/_/      _/    _/    _/_/        _/      _/    */ 
pragma solidity 0.8.20;

import "../interfaces/IAuthAdapter.sol";

/// @title  BorgAuth
/// @author MetaLeX Labs, Inc.
/// @notice ACL with extensibility for different role hierarchies and custom adapters
contract BorgAuth {
    //cosntants built-in roles, authority works as a hierarchy
    uint256 public constant OWNER_ROLE = 99;
    uint256 public constant ADMIN_ROLE = 98;
    uint256 public constant PRIVILEGED_ROLE = 97;
    address pendingOwner;

    //mappings and events
    mapping(address => uint256) public userRoles;
    mapping(uint256 => address) public roleAdapters;

    event RoleUpdated(address indexed user, uint256 role);
    event AdapterUpdated(uint256 indexed role, address adapter);

    /// @dev user not authorized with given role
    error BorgAuth_NotAuthorized(uint256 role, address user);
    error BorgAuth_SetAnotherOwner();
    error BorgAuth_ZeroAddress();

    /// @notice deployer is owner
    constructor() {
        _updateRole(msg.sender, OWNER_ROLE);
    }

    /// @notice update role for user
    /// @param user address of user
    /// @param role role to update
    function updateRole(
        address user,
        uint256 role
    ) external {
         onlyRole(OWNER_ROLE, msg.sender);
         if(user == msg.sender && role < OWNER_ROLE) revert BorgAuth_SetAnotherOwner();
        _updateRole(user, role);
    }
    
    /// @notice initialize ownership transfer
    /// @param newOwner address of new owner
    function initTransferOwnership(address newOwner) external {
        if (newOwner == address(0) || newOwner == msg.sender) revert BorgAuth_ZeroAddress();
        onlyRole(OWNER_ROLE, msg.sender);
        pendingOwner = newOwner;
    }

    /// @notice accept ownership transfer
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert BorgAuth_NotAuthorized(OWNER_ROLE, msg.sender);
        _updateRole(pendingOwner, OWNER_ROLE);
        pendingOwner = address(0);
        emit RoleUpdated(pendingOwner, OWNER_ROLE);
    }

    /// @notice function to purposefully revoke all roles from owner, rendering subsequent role updates impossible
    /// @dev this function is intended for use to remove admin controls from subsequent contracts using this auth
    function zeroOwner() external {
        onlyRole(OWNER_ROLE, msg.sender);
        _updateRole(msg.sender, 0);
    }

    /// @notice set adapter for role
    /// @param _role role to set adapter for
    /// @param _adapter address of adapter
    function setRoleAdapter(uint256 _role, address _adapter) external {
        onlyRole(OWNER_ROLE, msg.sender);
        roleAdapters[_role] = _adapter;
        emit AdapterUpdated(_role, _adapter);
    }

    /// @notice check role for user, revert if not authorized
    /// @param user address of user
    /// @param role of user
    function onlyRole(uint256 role, address user) public view {
        uint256 authorized = userRoles[user];

        if (authorized < role) {
            address adapter = roleAdapters[role];
            if (adapter != address(0)) 
                if (IAuthAdapter(adapter).isAuthorized(user) >= role) 
                    return;
            revert BorgAuth_NotAuthorized(role, user);
        }
    }

    /// @notice interal function to add a role to a user
    /// @param role role to update
    /// @param user address of user
    function _updateRole(
        address user,
        uint256 role
    ) internal {
        userRoles[user] = role;
        emit RoleUpdated(user, role);
    }
}

/// @title BorgAuthACL
/// @notice ACL with modifiers for different roles
abstract contract BorgAuthACL {
    //BorgAuth instance
    BorgAuth public immutable AUTH;

    // @dev zero address error
    error BorgAuthACL_ZeroAddress();

    /// @notice set AUTH to BorgAuth instance
    constructor(BorgAuth _auth) {
        if(address(_auth) == address(0)) revert BorgAuthACL_ZeroAddress();
        AUTH = _auth;
    }

    //common modifiers and general access control onlyRole
    modifier onlyOwner() {
        AUTH.onlyRole(AUTH.OWNER_ROLE(), msg.sender);
        _;
    }

    modifier onlyAdmin() {
        AUTH.onlyRole(AUTH.ADMIN_ROLE(), msg.sender);
        _;
    }

    modifier onlyPriv() {
        AUTH.onlyRole(AUTH.PRIVILEGED_ROLE(), msg.sender);
        _;
    }

    modifier onlyRole(uint256 _role) {
        AUTH.onlyRole(_role, msg.sender);
        _;
    }
}
