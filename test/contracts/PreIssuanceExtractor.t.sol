// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {PreIssuanceExtractor} from "src/components/issuance-validators/PreIssuanceExtractor.sol";
import {IPreIssuanceHook} from "src/interfaces/IPreIssuanceHook.sol";

contract PreIssuanceExtractorTest is Test {
    PreIssuanceExtractor extractor;

    address caller = makeAddr("caller");
    address receiver = makeAddr("receiver");
    address onBehalf = makeAddr("onBehalf");
    address asset = makeAddr("asset");
    address sender = makeAddr("sender");
    uint256 amount = 100;

    function setUp() public {
        extractor = new PreIssuanceExtractor();
    }

    function test_typeAndVersion() public view {
        assertEq(extractor.typeAndVersion(), "PreIssuanceExtractor 1.0.0");
    }

    function test_extract_success() public view {
        // `sender` differs from `caller` to prove the extractor reads from `data`, not `payload.sender`.
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: IPreIssuanceHook.preIssuance.selector,
            sender: sender,
            data: abi.encode(caller, receiver, onBehalf, asset, amount),
            context: bytes("")
        });

        IPolicyEngine.Parameter[] memory params = extractor.extract(payload);

        assertEq(params.length, 5, "unexpected param count");

        assertEq(params[0].name, extractor.PARAM_CALLER(), "param 0 name");
        assertEq(abi.decode(params[0].value, (address)), caller, "param 0 value");

        assertEq(params[1].name, extractor.PARAM_RECEIVER(), "param 1 name");
        assertEq(abi.decode(params[1].value, (address)), receiver, "param 1 value");

        assertEq(params[2].name, extractor.PARAM_ON_BEHALF(), "param 2 name");
        assertEq(abi.decode(params[2].value, (address)), onBehalf, "param 2 value");

        assertEq(params[3].name, extractor.PARAM_ASSET(), "param 3 name");
        assertEq(abi.decode(params[3].value, (address)), asset, "param 3 value");

        assertEq(params[4].name, extractor.PARAM_AMOUNT(), "param 4 name");
        assertEq(abi.decode(params[4].value, (uint256)), amount, "param 4 value");
    }

    function test_extract_fail_unsupportedSelector() public {
        bytes4 badSelector = bytes4(keccak256("notIssuanceAction()"));

        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: badSelector,
            sender: sender,
            data: abi.encode(caller, receiver, onBehalf, asset, amount),
            context: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(IPolicyEngine.UnsupportedSelector.selector, badSelector));
        extractor.extract(payload);
    }
}
