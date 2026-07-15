// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {ChainlinkAcePolicyProtectedBase} from "src/infra/chainlink-ace/ChainlinkAcePolicyProtectedBase.sol";
import {ISharesTransferValidator} from "src/interfaces/ISharesTransferValidator.sol";

/// @title ChainlinkAceSharesTransferValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates shares transfers by running them through a Chainlink ACE
contract ChainlinkAceSharesTransferValidator is
    ChainlinkAcePolicyProtectedBase,
    ComponentHelpersMixin,
    ISharesTransferValidator
{
    //==================================================================================================================
    // Init
    //==================================================================================================================

    /// @notice Initializer
    /// @param _policyEngine The policy engine to attach (set once, immutable thereafter)
    function init(address _policyEngine) external initializer {
        __ChainlinkAcePolicyProtectedBase_init(_policyEngine);
    }

    //==================================================================================================================
    // Required: ISharesTransferValidator
    //==================================================================================================================

    /// @inheritdoc ISharesTransferValidator
    function validateSharesTransfer(
        address, /* _originator */
        address _from,
        address _to,
        uint256 _amount
    )
        external
        override
        onlyShares
    {
        IPolicyEngine engine = IPolicyEngine(getPolicyEngine());

        engine.run(
            IPolicyEngine.Payload({
                selector: IERC20.transfer.selector, sender: _from, data: abi.encode(_to, _amount), context: bytes("")
            })
        );
    }
}
