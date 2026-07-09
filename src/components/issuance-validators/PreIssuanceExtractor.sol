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

import {IPreIssuanceHook} from "src/interfaces/IPreIssuanceHook.sol";

/// @title PreIssuanceExtractor Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Decodes the payload emitted by `ChainlinkAcePreIssuanceValidator` into the named
/// `caller` / `receiver` / `onBehalf` / `asset` / `amount` parameters that issuance policies consume.
contract PreIssuanceExtractor is IExtractor {
    /// @notice Type and version of the extractor
    string public constant override typeAndVersion = "PreIssuanceExtractor 1.0.0";

    /// @notice Parameter key for the issuance action caller
    bytes32 public constant PARAM_CALLER = keccak256("caller");

    /// @notice Parameter key for the issuance action receiver
    bytes32 public constant PARAM_RECEIVER = keccak256("receiver");

    /// @notice Parameter key for the party on whose behalf the issuance action is performed
    bytes32 public constant PARAM_ON_BEHALF = keccak256("onBehalf");

    /// @notice Parameter key for the issuance action asset
    bytes32 public constant PARAM_ASSET = keccak256("asset");

    /// @notice Parameter key for the issuance action amount
    bytes32 public constant PARAM_AMOUNT = keccak256("amount");

    /// @inheritdoc IExtractor
    /// @param _payload The policy engine payload containing the function selector and calldata
    /// @return An array of five parameters: PARAM_CALLER, PARAM_RECEIVER, PARAM_ON_BEHALF, PARAM_ASSET, PARAM_AMOUNT
    function extract(IPolicyEngine.Payload calldata _payload) external pure returns (IPolicyEngine.Parameter[] memory) {
        require(
            _payload.selector == IPreIssuanceHook.preIssuance.selector,
            IPolicyEngine.UnsupportedSelector(_payload.selector)
        );

        (address caller, address receiver, address onBehalf, address asset, uint256 amount) =
            abi.decode(_payload.data, (address, address, address, address, uint256));

        IPolicyEngine.Parameter[] memory result = new IPolicyEngine.Parameter[](5);
        result[0] = IPolicyEngine.Parameter(PARAM_CALLER, abi.encode(caller));
        result[1] = IPolicyEngine.Parameter(PARAM_RECEIVER, abi.encode(receiver));
        result[2] = IPolicyEngine.Parameter(PARAM_ON_BEHALF, abi.encode(onBehalf));
        result[3] = IPolicyEngine.Parameter(PARAM_ASSET, abi.encode(asset));
        result[4] = IPolicyEngine.Parameter(PARAM_AMOUNT, abi.encode(amount));

        return result;
    }
}
