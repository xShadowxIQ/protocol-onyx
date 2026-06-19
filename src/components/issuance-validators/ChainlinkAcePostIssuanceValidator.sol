// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {IPostIssuanceHook} from "src/interfaces/IPostIssuanceHook.sol";

import {ChainlinkAceIssuanceValidatorBase} from "./ChainlinkAceIssuanceValidatorBase.sol";

/// @title ChainlinkAcePostIssuanceValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates issuance actions (deposit / redeem executions) after they settle by running
/// them through a Chainlink ACE `IPolicyEngine`.
contract ChainlinkAcePostIssuanceValidator is ChainlinkAceIssuanceValidatorBase, IPostIssuanceHook {
    //==================================================================================================================
    // Required: IPostIssuanceHook
    //==================================================================================================================

    /// @inheritdoc IPostIssuanceHook
    function postIssuance(
        address _caller,
        address _receiver,
        address _onBehalf,
        address _asset,
        uint256 _sharesAmount,
        uint256 _assetAmount
    ) external override onlyHandler {
        IPolicyEngine(getPolicyEngine())
            .run(
                IPolicyEngine.Payload({
                selector: IPostIssuanceHook.postIssuance.selector,
                sender: _caller,
                data: abi.encode(_caller, _receiver, _onBehalf, _asset, _sharesAmount, _assetAmount),
                context: getSenderContext(_caller)
            })
            );
    }
}
