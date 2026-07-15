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
import {Shares} from "src/shares/Shares.sol";

import {
    ChainlinkAceSharesTransferValidatorHarness
} from "test/harnesses/ChainlinkAceSharesTransferValidatorHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ChainlinkAceSharesTransferValidatorTest is TestHelpers {
    Shares shares;
    address policyEngine;
    ChainlinkAceSharesTransferValidatorHarness validator;

    // The originator is accepted and ignored by the validator; the payload is built from the transfer args
    address originator = makeAddr("originator");
    address from = makeAddr("from");
    address to = makeAddr("to");
    uint256 amount = 123;

    function setUp() public {
        shares = createShares();
        policyEngine = deployPolicyEngine({_defaultAllow: true, _uniqueId: bytes32("engine")});

        // Deploy the validator harness UNINITIALIZED; init is exercised explicitly per test.
        validator = new ChainlinkAceSharesTransferValidatorHarness(address(shares));
    }

    modifier whenInitializing() {
        _;
    }

    function test_WhenThePolicyEngineIsTheZeroAddress() external whenInitializing {
        // It should revert with {ChainlinkAcePolicyProtectedBase__Init__ZeroAddress}.
        vm.expectRevert(
            ChainlinkAcePolicyProtectedBase.ChainlinkAcePolicyProtectedBase__Init__ZeroAddress.selector,
            address(validator)
        );
        validator.init(address(0));
    }

    function test_WhenThePolicyEngineIsANon_zeroAddress() external whenInitializing {
        // It should attach the validator to the policy engine.
        vm.expectCall(policyEngine, abi.encodeWithSelector(IPolicyEngine.attach.selector));

        validator.init(policyEngine);

        // It should store the policy engine as the attached engine.
        assertEq(validator.getPolicyEngine(), policyEngine, "engine not stored as attached engine");
    }

    modifier whenValidatingASharesTransfer() {
        validator.init(policyEngine);
        _;
    }

    function test_WhenTheCallerIsNotTheSharesContract() external whenValidatingASharesTransfer {
        address notShares = makeAddr("notShares");

        // It should revert with {ComponentHelpersMixin__OnlyShares__Unauthorized}.
        vm.expectRevert(
            ComponentHelpersMixin.ComponentHelpersMixin__OnlyShares__Unauthorized.selector, address(validator)
        );

        vm.prank(notShares);
        validator.validateSharesTransfer(originator, from, to, amount);
    }

    modifier whenTheCallerIsTheSharesContract() {
        _;
    }

    function test_WhenTheCallerIsTheSharesContract()
        external
        whenValidatingASharesTransfer
        whenTheCallerIsTheSharesContract
    {
        IPolicyEngine.Payload memory expectedPayload = IPolicyEngine.Payload({
            selector: IERC20.transfer.selector, sender: from, data: abi.encode(to, amount), context: ""
        });

        // It should call the policy engine with the ERC20 transfer selector.
        // It should call the policy engine with the from address as the sender.
        // It should call the policy engine with the abi-encoded to and amount as data.
        vm.expectCall(policyEngine, abi.encodeCall(IPolicyEngine.run, (expectedPayload)));

        vm.prank(address(shares));
        validator.validateSharesTransfer(originator, from, to, amount);
    }

    function test_GivenThePolicyEngineRejectsTheRun()
        external
        whenValidatingASharesTransfer
        whenTheCallerIsTheSharesContract
    {
        IPolicyEngine.Payload memory payload = IPolicyEngine.Payload({
            selector: IERC20.transfer.selector, sender: from, data: abi.encode(to, amount), context: ""
        });
        bytes memory rejection =
            abi.encodeWithSelector(IPolicyEngine.PolicyRunRejected.selector, makeAddr("policy"), "rejected", payload);

        // Make the policy engine reject the run.
        vm.mockCallRevert(policyEngine, abi.encodeWithSelector(IPolicyEngine.run.selector), rejection);

        // It should revert with {PolicyRunRejected}.
        vm.expectRevert(rejection, policyEngine);

        vm.prank(address(shares));
        validator.validateSharesTransfer(originator, from, to, amount);
    }

    function test_GivenThePolicyEngineAllowsTheRun()
        external
        whenValidatingASharesTransfer
        whenTheCallerIsTheSharesContract
    {
        // Real engine deployed with defaultAllow=true and no policies allows the run.
        // It should not revert.
        vm.prank(address(shares));
        validator.validateSharesTransfer(originator, from, to, amount);
    }

    function test_ShouldCallThePolicyEngineWithEmptyContext()
        external
        whenValidatingASharesTransfer
        whenTheCallerIsTheSharesContract
    {
        IPolicyEngine.Payload memory expectedPayload = IPolicyEngine.Payload({
            selector: IERC20.transfer.selector, sender: from, data: abi.encode(to, amount), context: ""
        });

        // It should call the policy engine with empty context.
        vm.expectCall(policyEngine, abi.encodeCall(IPolicyEngine.run, (expectedPayload)));

        vm.prank(address(shares));
        validator.validateSharesTransfer(originator, from, to, amount);
    }
}
