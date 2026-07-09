// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {IPostIssuanceHook} from "src/interfaces/IPostIssuanceHook.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title PostIssuanceHookHandlerBase Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A base contract giving issuance handlers the common functions to attach and run a post-issuance hook
abstract contract PostIssuanceHookHandlerBase is ComponentHelpersMixin {
    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant POST_ISSUANCE_HOOK_HANDLER_BASE_STORAGE_LOCATION =
        0x49a4709527bdebfd0f62ab790df8e5919975922f9e248dce4388f77cd5024600;
    string private constant POST_ISSUANCE_HOOK_HANDLER_BASE_STORAGE_LOCATION_ID = "PostIssuanceHookHandlerBase";

    /// @custom:storage-location erc7201:enzyme.PostIssuanceHookHandlerBase
    /// @param postIssuanceHook A contract validating actions after they settle (`address(0)` disables it)
    struct PostIssuanceHookHandlerBaseStorage {
        address postIssuanceHook;
    }

    function __getPostIssuanceHookHandlerBaseStorage()
        private
        pure
        returns (PostIssuanceHookHandlerBaseStorage storage $)
    {
        bytes32 location = POST_ISSUANCE_HOOK_HANDLER_BASE_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event PostIssuanceHookSet(address hook);

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: POST_ISSUANCE_HOOK_HANDLER_BASE_STORAGE_LOCATION,
            _id: POST_ISSUANCE_HOOK_HANDLER_BASE_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    /// @notice Sets the post-issuance hook (`address(0)` disables post-issuance validation)
    function setPostIssuanceHook(address _postIssuanceHook) external onlyAdminOrOwner {
        __getPostIssuanceHookHandlerBaseStorage().postIssuanceHook = _postIssuanceHook;

        emit PostIssuanceHookSet(_postIssuanceHook);
    }

    //==================================================================================================================
    // Validation
    //==================================================================================================================

    /// @dev Runs the action through the attached post-issuance hook, if any. No-op when unset.
    function __postIssuance(
        address _caller,
        address _receiver,
        address _onBehalf,
        address _asset,
        uint256 _sharesAmount,
        uint256 _assetAmount
    ) internal {
        address postIssuanceHook = getPostIssuanceHook();

        if (postIssuanceHook == address(0)) {
            return;
        }

        IPostIssuanceHook(postIssuanceHook)
            .postIssuance({
            _caller: _caller,
            _receiver: _receiver,
            _onBehalf: _onBehalf,
            _asset: _asset,
            _sharesAmount: _sharesAmount,
            _assetAmount: _assetAmount
        });
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the contract that validates actions after they settle
    function getPostIssuanceHook() public view returns (address) {
        return __getPostIssuanceHookHandlerBaseStorage().postIssuanceHook;
    }
}
