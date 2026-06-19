// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {IPreIssuanceHook} from "src/interfaces/IPreIssuanceHook.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title PreIssuanceHookHandlerBase Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A base contract giving issuance handlers the common functions to attach and run a pre-issuance hook
abstract contract PreIssuanceHookHandlerBase is ComponentHelpersMixin {
    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant PRE_ISSUANCE_HOOK_HANDLER_BASE_STORAGE_LOCATION =
        0x5b857c6e7c1a6fe1f2381598a12e1c9ca80fb1149f0cb0b1207211d4625b8c00;
    string private constant PRE_ISSUANCE_HOOK_HANDLER_BASE_STORAGE_LOCATION_ID = "PreIssuanceHookHandlerBase";

    /// @custom:storage-location erc7201:enzyme.PreIssuanceHookHandlerBase
    /// @param preIssuanceHook A contract validating actions before they are committed (`address(0)` disables it)
    struct PreIssuanceHookHandlerBaseStorage {
        address preIssuanceHook;
    }

    function __getPreIssuanceHookHandlerBaseStorage()
        private
        pure
        returns (PreIssuanceHookHandlerBaseStorage storage $)
    {
        bytes32 location = PRE_ISSUANCE_HOOK_HANDLER_BASE_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event PreIssuanceHookSet(address hook);

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: PRE_ISSUANCE_HOOK_HANDLER_BASE_STORAGE_LOCATION,
            _id: PRE_ISSUANCE_HOOK_HANDLER_BASE_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    /// @notice Sets the pre-issuance hook (`address(0)` disables pre-issuance validation)
    function setPreIssuanceHook(address _preIssuanceHook) external onlyAdminOrOwner {
        __getPreIssuanceHookHandlerBaseStorage().preIssuanceHook = _preIssuanceHook;

        emit PreIssuanceHookSet(_preIssuanceHook);
    }

    //==================================================================================================================
    // Validation
    //==================================================================================================================

    /// @dev Runs the action through the attached pre-issuance hook, if any. No-op when unset.
    function __preIssuance(address _caller, address _receiver, address _onBehalf, address _asset, uint256 _amount)
        internal
    {
        address preIssuanceHook = getPreIssuanceHook();

        if (preIssuanceHook == address(0)) {
            return;
        }

        IPreIssuanceHook(preIssuanceHook)
            .preIssuance({
            _caller: _caller, _receiver: _receiver, _onBehalf: _onBehalf, _asset: _asset, _amount: _amount
        });
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the contract that validates actions before they are committed
    function getPreIssuanceHook() public view returns (address) {
        return __getPreIssuanceHookHandlerBaseStorage().preIssuanceHook;
    }
}
