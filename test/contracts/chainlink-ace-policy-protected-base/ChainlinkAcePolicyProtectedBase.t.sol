// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ChainlinkAcePolicyProtectedBase} from "src/infra/chainlink-ace/ChainlinkAcePolicyProtectedBase.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IPolicyProtected} from "@chainlink/policy-management/interfaces/IPolicyProtected.sol";

import {ChainlinkAcePolicyProtectedBaseHarness} from "test/harnesses/ChainlinkAcePolicyProtectedBaseHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ChainlinkAcePolicyProtectedBaseTest is TestHelpers {
    ChainlinkAcePolicyProtectedBaseHarness harness;

    address caller = makeAddr("caller");
    address otherCaller = makeAddr("otherCaller");
    address policyEngine;

    function setUp() public {
        harness = new ChainlinkAcePolicyProtectedBaseHarness();

        policyEngine = deployPolicyEngine({_defaultAllow: true, _uniqueId: bytes32("engine")});
    }

    //==================================================================================================================
    // __ChainlinkAcePolicyProtectedBase_init
    //==================================================================================================================

    function test_RevertWhen_TheNewEngineIsZero() external {
        // It should revert with {ChainlinkAcePolicyProtectedBase__Init__ZeroAddress}.
        vm.expectRevert(ChainlinkAcePolicyProtectedBase.ChainlinkAcePolicyProtectedBase__Init__ZeroAddress.selector);

        harness.exposed__ChainlinkAcePolicyProtectedBase_init(address(0));
    }

    function test_WhenTheNewEngineIsNonZero() external {
        // It should call attach on the new engine.
        vm.expectCall(policyEngine, abi.encodeWithSelector(IPolicyEngine.attach.selector));

        // It should emit a {PolicyEngineAttached} event with the new engine address.
        vm.expectEmit(address(harness));
        emit IPolicyProtected.PolicyEngineAttached(policyEngine);

        harness.exposed__ChainlinkAcePolicyProtectedBase_init(policyEngine);

        // It should set the stored policy engine to the new engine.
        assertEq(harness.getPolicyEngine(), policyEngine, "engine not stored");
    }

    //==================================================================================================================
    // getPolicyEngine
    //==================================================================================================================

    function test_GivenNoEngineIsAttached_GetPolicyEngine() external view {
        // It should return the zero address.
        assertEq(harness.getPolicyEngine(), address(0), "engine should be zero");
    }

    function test_GivenAnEngineIsAttached_GetPolicyEngine() external {
        harness.exposed__ChainlinkAcePolicyProtectedBase_init(policyEngine);

        // It should return the attached engine address.
        assertEq(harness.getPolicyEngine(), policyEngine, "engine mismatch");
    }

    //==================================================================================================================
    // setContext
    //==================================================================================================================

    function test_WhenCallingSetContext() external {
        bytes memory contextA = bytes("contextA");
        bytes memory contextB = bytes("contextB");

        vm.prank(caller);
        harness.setContext(contextA);

        vm.prank(otherCaller);
        harness.setContext(contextB);

        // It should store the context for the caller.
        assertEq(harness.getSenderContext(caller), contextA, "caller context mismatch");

        // It should not affect the context of other senders.
        assertEq(harness.getSenderContext(otherCaller), contextB, "other caller context mismatch");
    }

    //==================================================================================================================
    // getSenderContext
    //==================================================================================================================

    function test_GivenNoContextIsSetForTheSender_GetSenderContext() external view {
        // It should return empty bytes.
        assertEq(harness.getSenderContext(caller), bytes(""), "context should be empty");
    }

    function test_GivenAContextIsSetForTheSender_GetSenderContext() external {
        bytes memory context = bytes("ctx");

        vm.prank(caller);
        harness.setContext(context);

        // It should return the stored context for the sender.
        assertEq(harness.getSenderContext(caller), context, "context mismatch");
    }
}
