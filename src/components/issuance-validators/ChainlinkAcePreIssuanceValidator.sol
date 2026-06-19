// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {IPreIssuanceHook} from "src/interfaces/IPreIssuanceHook.sol";

import {ChainlinkAceIssuanceValidatorBase} from "./ChainlinkAceIssuanceValidatorBase.sol";

/// @title ChainlinkAcePreIssuanceValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates issuance actions (deposit / redeem requests) before they are committed by running
/// them through a Chainlink ACE `IPolicyEngine`.
contract ChainlinkAcePreIssuanceValidator is ChainlinkAceIssuanceValidatorBase, IPreIssuanceHook {
    //==================================================================================================================
    // Required: IPreIssuanceHook
    //==================================================================================================================

    /// @inheritdoc IPreIssuanceHook
    function preIssuance(address _caller, address _receiver, address _onBehalf, address _asset, uint256 _amount)
        external
        override
        onlyHandler
    {
        IPolicyEngine(getPolicyEngine())
            .run(
                IPolicyEngine.Payload({
                selector: IPreIssuanceHook.preIssuance.selector,
                sender: _caller,
                data: abi.encode(_caller, _receiver, _onBehalf, _asset, _amount),
                context: getSenderContext(_caller)
            })
            );
    }
}
