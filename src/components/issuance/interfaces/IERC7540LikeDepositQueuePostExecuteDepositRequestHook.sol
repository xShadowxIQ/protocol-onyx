// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IERC7540LikeDepositQueuePostExecuteDepositRequestHook Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Hook called by ERC7540LikeDepositQueue after executing a deposit request
interface IERC7540LikeDepositQueuePostExecuteDepositRequestHook {
    function postExecuteDepositRequest(
        address _originator,
        address _controller,
        uint256 _sharesAmount,
        uint256 _assetAmount
    ) external;
}
