// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IExtractor} from "@chainlink/policy-management/interfaces/IExtractor.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {IPostIssuanceHook} from "src/interfaces/IPostIssuanceHook.sol";

/// @title PostIssuanceExtractor Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Decodes the payload emitted by `ChainlinkAcePostIssuanceValidator` into the named
/// `caller` / `receiver` / `onBehalf` / `asset` / `sharesAmount` / `assetAmount` parameters that
/// post-execution policies consume.
contract PostIssuanceExtractor is IExtractor {
    /// @notice Type and version of the extractor
    string public constant override typeAndVersion = "PostIssuanceExtractor 1.0.0";

    /// @notice Parameter key for the post-execution caller
    bytes32 public constant PARAM_CALLER = keccak256("caller");

    /// @notice Parameter key for the post-execution receiver
    bytes32 public constant PARAM_RECEIVER = keccak256("receiver");

    /// @notice Parameter key for the party on whose behalf the action was performed
    bytes32 public constant PARAM_ON_BEHALF = keccak256("onBehalf");

    /// @notice Parameter key for the post-execution asset
    bytes32 public constant PARAM_ASSET = keccak256("asset");

    /// @notice Parameter key for the post-execution shares amount
    bytes32 public constant PARAM_SHARES_AMOUNT = keccak256("sharesAmount");

    /// @notice Parameter key for the post-execution asset amount
    bytes32 public constant PARAM_ASSET_AMOUNT = keccak256("assetAmount");

    /// @inheritdoc IExtractor
    /// @param _payload The policy engine payload containing the function selector and calldata
    /// @return An array of six parameters: PARAM_CALLER, PARAM_RECEIVER, PARAM_ON_BEHALF, PARAM_ASSET,
    /// PARAM_SHARES_AMOUNT, PARAM_ASSET_AMOUNT
    function extract(IPolicyEngine.Payload calldata _payload) external pure returns (IPolicyEngine.Parameter[] memory) {
        require(
            _payload.selector == IPostIssuanceHook.postIssuance.selector,
            IPolicyEngine.UnsupportedSelector(_payload.selector)
        );

        (address caller, address receiver, address onBehalf, address asset, uint256 sharesAmount, uint256 assetAmount) =
            abi.decode(_payload.data, (address, address, address, address, uint256, uint256));

        IPolicyEngine.Parameter[] memory result = new IPolicyEngine.Parameter[](6);
        result[0] = IPolicyEngine.Parameter(PARAM_CALLER, abi.encode(caller));
        result[1] = IPolicyEngine.Parameter(PARAM_RECEIVER, abi.encode(receiver));
        result[2] = IPolicyEngine.Parameter(PARAM_ON_BEHALF, abi.encode(onBehalf));
        result[3] = IPolicyEngine.Parameter(PARAM_ASSET, abi.encode(asset));
        result[4] = IPolicyEngine.Parameter(PARAM_SHARES_AMOUNT, abi.encode(sharesAmount));
        result[5] = IPolicyEngine.Parameter(PARAM_ASSET_AMOUNT, abi.encode(assetAmount));

        return result;
    }
}
