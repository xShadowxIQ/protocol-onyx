// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IPreIssuanceHook Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IPreIssuanceHook {
    /// @param _amount The asset amount for deposit requests, or the shares amount for redeem requests
    function preIssuance(address _caller, address _receiver, address _onBehalf, address _asset, uint256 _amount)
        external;
}
