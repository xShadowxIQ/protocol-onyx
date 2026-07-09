// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IPolicyProtected} from "@chainlink/policy-management/interfaces/IPolicyProtected.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title ChainlinkAcePolicyProtectedBase Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Base for integrating Onyx contracts with a Chainlink ACE policy engine.
/// @dev Context is a flexible data channel carrying the sender's optional extra values (e.g. signatures,
/// proofs, risk params) through to the policy validators. It is stored per-sender and read — but never
/// cleared — when a protected action runs. The contract does not enforce this, so the caller is responsible
/// for following a 3-step pattern within a single atomic transaction (e.g. via multicall):
///   1. setContext(context)
///   2. execute the protected action(s)
///   3. setContext("") to clear
/// Because context is not auto-cleared on consumption, the caller decides whether one context applies to a
/// whole batch of actions or to a single action. Setting and clearing it in the same transaction is in line
/// with Chainlink's recommendation (avoids stale or reused context):
/// https://github.com/smartcontractkit/chainlink-ace/blob/46738579f57e362b5203b66d5fdca13df07892fb/packages/policy-management/docs/CONCEPTS.md#the-context-parameter-a-flexible-data-channel
abstract contract ChainlinkAcePolicyProtectedBase is Initializable {
    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant CHAINLINK_ACE_POLICY_PROTECTED_BASE_STORAGE_LOCATION =
        0xb8dd5559d2d5e4a394940e95b77fae900b42d6f51d6b2f323593e278ae2cd500;
    string private constant CHAINLINK_ACE_POLICY_PROTECTED_BASE_STORAGE_LOCATION_ID = "ChainlinkAcePolicyProtectedBase";

    /// @custom:storage-location erc7201:enzyme.ChainlinkAcePolicyProtectedBase
    /// @param policyEngine The attached policy engine (zero until set in init)
    /// @param senderContext Per-sender context bytes consumed by policy validators
    struct ChainlinkAcePolicyProtectedBaseStorage {
        IPolicyEngine policyEngine;
        mapping(address sender => bytes context) senderContext;
    }

    function __getChainlinkAcePolicyProtectedBaseStorage()
        internal
        pure
        returns (ChainlinkAcePolicyProtectedBaseStorage storage $)
    {
        bytes32 location = CHAINLINK_ACE_POLICY_PROTECTED_BASE_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error ChainlinkAcePolicyProtectedBase__Init__ZeroAddress();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: CHAINLINK_ACE_POLICY_PROTECTED_BASE_STORAGE_LOCATION,
            _id: CHAINLINK_ACE_POLICY_PROTECTED_BASE_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Policy engine
    //==================================================================================================================

    function __ChainlinkAcePolicyProtectedBase_init(address _policyEngine) internal onlyInitializing {
        require(_policyEngine != address(0), ChainlinkAcePolicyProtectedBase__Init__ZeroAddress());

        __getChainlinkAcePolicyProtectedBaseStorage().policyEngine = IPolicyEngine(_policyEngine);

        IPolicyEngine(_policyEngine).attach();

        emit IPolicyProtected.PolicyEngineAttached(_policyEngine);
    }

    /// @notice Gets the policy engine attached to this contract.
    /// @return The attached policy engine address (zero until set in init).
    function getPolicyEngine() public view returns (address) {
        return address(__getChainlinkAcePolicyProtectedBaseStorage().policyEngine);
    }

    //==================================================================================================================
    // Sender context
    //==================================================================================================================

    /// @notice Sets the per-sender policy context for the caller.
    /// @param _context The context to set.
    function setContext(bytes calldata _context) public {
        __getChainlinkAcePolicyProtectedBaseStorage().senderContext[msg.sender] = _context;
    }

    /// @notice Gets the per-sender policy context for a given sender.
    /// @param _sender The sender whose context to read.
    /// @return The context stored for the sender.
    function getSenderContext(address _sender) public view returns (bytes memory) {
        return __getChainlinkAcePolicyProtectedBaseStorage().senderContext[_sender];
    }
}
