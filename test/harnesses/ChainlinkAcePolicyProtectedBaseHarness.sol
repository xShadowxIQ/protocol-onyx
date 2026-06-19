// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {ChainlinkAcePolicyProtectedBase} from "src/infra/chainlink-ace/ChainlinkAcePolicyProtectedBase.sol";

contract ChainlinkAcePolicyProtectedBaseHarness is ChainlinkAcePolicyProtectedBase {
    function exposed__ChainlinkAcePolicyProtectedBase_init(address _policyEngine) external initializer {
        __ChainlinkAcePolicyProtectedBase_init(_policyEngine);
    }
}
