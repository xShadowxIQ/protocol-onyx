// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IPolicyProtected} from "@chainlink/policy-management/interfaces/IPolicyProtected.sol";

import {
    ChainlinkAceIssuanceValidatorBase
} from "src/components/issuance-validators/ChainlinkAceIssuanceValidatorBase.sol";
import {ChainlinkAcePolicyProtectedBase} from "src/infra/chainlink-ace/ChainlinkAcePolicyProtectedBase.sol";
import {IPreIssuanceHook} from "src/interfaces/IPreIssuanceHook.sol";
import {Shares} from "src/shares/Shares.sol";

import {ChainlinkAcePreIssuanceValidatorHarness} from "test/harnesses/ChainlinkAcePreIssuanceValidatorHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ChainlinkAcePreIssuanceValidatorTest is TestHelpers {
    Shares shares;

    address handler = makeAddr("handler");
    address caller = makeAddr("caller");
    address receiver = makeAddr("receiver");
    address onBehalf = makeAddr("onBehalf");
    address asset = makeAddr("asset");
    address otherSender = makeAddr("otherSender");
    uint256 amount = 123;

    function setUp() public {
        shares = createShares();
    }

    // Deploys a real policy engine, the validator harness, and initializes it.
    function __deployInitializedValidator(bool _defaultAllow)
        internal
        returns (ChainlinkAcePreIssuanceValidatorHarness validator_, address engine_)
    {
        engine_ = deployPolicyEngine(_defaultAllow);
        validator_ = new ChainlinkAcePreIssuanceValidatorHarness(address(shares));
        validator_.init(handler, engine_);
    }

    // Builds the exact payload the validator should forward to engine.run.
    function __expectedPayload(bytes memory _context) internal view returns (IPolicyEngine.Payload memory) {
        return IPolicyEngine.Payload({
            selector: IPreIssuanceHook.preIssuance.selector,
            sender: caller,
            data: abi.encode(caller, receiver, onBehalf, asset, amount),
            context: _context
        });
    }

    modifier whenInitializing() {
        _;
    }

    function test_WhenTheHandlerIsTheZeroAddress() external whenInitializing {
        ChainlinkAcePreIssuanceValidatorHarness validator = new ChainlinkAcePreIssuanceValidatorHarness(address(shares));
        address engine = makeAddr("engine");

        // It should revert with {ChainlinkAceIssuanceValidatorBase__Init__EmptyHandler}.
        vm.expectRevert(
            ChainlinkAceIssuanceValidatorBase.ChainlinkAceIssuanceValidatorBase__Init__EmptyHandler.selector,
            address(validator)
        );
        validator.init({_handler: address(0), _policyEngine: engine});
    }

    function test_WhenThePolicyEngineIsTheZeroAddress() external whenInitializing {
        ChainlinkAcePreIssuanceValidatorHarness validator = new ChainlinkAcePreIssuanceValidatorHarness(address(shares));

        // It should revert with {ChainlinkAcePolicyProtectedBase__Init__ZeroAddress}.
        vm.expectRevert(
            ChainlinkAcePolicyProtectedBase.ChainlinkAcePolicyProtectedBase__Init__ZeroAddress.selector,
            address(validator)
        );
        validator.init({_handler: handler, _policyEngine: address(0)});
    }

    function test_WhenBothTheHandlerAndThePolicyEngineAreNon_zeroAddresses() external whenInitializing {
        ChainlinkAcePreIssuanceValidatorHarness validator = new ChainlinkAcePreIssuanceValidatorHarness(address(shares));
        address engine = deployPolicyEngine({_defaultAllow: true});

        // It should attach the validator to the policy engine.
        vm.expectCall(engine, abi.encodeCall(IPolicyEngine.attach, ()));

        vm.expectEmit(address(validator));
        emit IPolicyProtected.PolicyEngineAttached(engine);

        validator.init({_handler: handler, _policyEngine: engine});

        // It should store the policy engine as the attached engine.
        assertEq(validator.getPolicyEngine(), engine, "engine not stored");

        // It should store the handler.
        assertEq(validator.getHandler(), handler, "handler not stored");
    }

    modifier whenValidatingAnIssuanceAction() {
        _;
    }

    function test_WhenTheCallerIsNotTheHandler() external whenValidatingAnIssuanceAction {
        (ChainlinkAcePreIssuanceValidatorHarness validator,) = __deployInitializedValidator({_defaultAllow: true});
        address notHandler = makeAddr("notHandler");

        // It should revert with {ChainlinkAceIssuanceValidatorBase__OnlyHandler}.
        vm.expectRevert(
            ChainlinkAceIssuanceValidatorBase.ChainlinkAceIssuanceValidatorBase__OnlyHandler.selector,
            address(validator)
        );
        vm.prank(notHandler);
        validator.preIssuance({
            _caller: caller, _receiver: receiver, _onBehalf: onBehalf, _asset: asset, _amount: amount
        });
    }

    modifier whenTheCallerIsTheHandler() {
        _;
    }

    function test_WhenTheCallerIsTheHandler() external whenValidatingAnIssuanceAction whenTheCallerIsTheHandler {
        (ChainlinkAcePreIssuanceValidatorHarness validator, address engine) =
            __deployInitializedValidator({_defaultAllow: true});

        // It should call the policy engine with the issuance action selector.
        // It should call the policy engine with the caller as the sender.
        // It should call the policy engine with the abi-encoded caller, receiver, onBehalf, asset and amount as data.
        vm.expectCall(engine, abi.encodeCall(IPolicyEngine.run, (__expectedPayload(bytes("")))));

        vm.prank(handler);
        validator.preIssuance({
            _caller: caller, _receiver: receiver, _onBehalf: onBehalf, _asset: asset, _amount: amount
        });
    }

    function test_GivenThePolicyEngineRejectsTheRun()
        external
        whenValidatingAnIssuanceAction
        whenTheCallerIsTheHandler
    {
        // Default-reject engine with no policy attached rejects every run.
        (ChainlinkAcePreIssuanceValidatorHarness validator, address engine) =
            __deployInitializedValidator({_defaultAllow: false});

        // It should revert with {PolicyRunRejected}.
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolicyEngine.PolicyRunRejected.selector,
                address(0),
                "no policy allowed the action and default is reject",
                __expectedPayload(bytes(""))
            ),
            engine
        );
        vm.prank(handler);
        validator.preIssuance({
            _caller: caller, _receiver: receiver, _onBehalf: onBehalf, _asset: asset, _amount: amount
        });
    }

    function test_GivenThePolicyEngineAllowsTheRun() external whenValidatingAnIssuanceAction whenTheCallerIsTheHandler {
        (ChainlinkAcePreIssuanceValidatorHarness validator,) = __deployInitializedValidator({_defaultAllow: true});

        // It should not revert.
        vm.prank(handler);
        validator.preIssuance({
            _caller: caller, _receiver: receiver, _onBehalf: onBehalf, _asset: asset, _amount: amount
        });
    }

    function test_GivenNoContextIsStoredForTheCaller()
        external
        whenValidatingAnIssuanceAction
        whenTheCallerIsTheHandler
    {
        (ChainlinkAcePreIssuanceValidatorHarness validator, address engine) =
            __deployInitializedValidator({_defaultAllow: true});

        // It should call the policy engine with empty context.
        vm.expectCall(engine, abi.encodeCall(IPolicyEngine.run, (__expectedPayload(bytes("")))));

        vm.prank(handler);
        validator.preIssuance({
            _caller: caller, _receiver: receiver, _onBehalf: onBehalf, _asset: asset, _amount: amount
        });
    }

    modifier givenContextIsStoredForTheCaller() {
        _;
    }

    function test_GivenContextIsStoredForTheCaller()
        external
        whenValidatingAnIssuanceAction
        whenTheCallerIsTheHandler
        givenContextIsStoredForTheCaller
    {
        (ChainlinkAcePreIssuanceValidatorHarness validator, address engine) =
            __deployInitializedValidator({_defaultAllow: true});

        bytes memory context = bytes("context");
        vm.prank(caller);
        validator.setContext(context);

        // It should call the policy engine with the stored context.
        vm.expectCall(engine, abi.encodeCall(IPolicyEngine.run, (__expectedPayload(context))));

        vm.prank(handler);
        validator.preIssuance({
            _caller: caller, _receiver: receiver, _onBehalf: onBehalf, _asset: asset, _amount: amount
        });

        // It should leave the stored context for the caller after the run.
        assertEq(validator.getSenderContext(caller), context, "context should not be cleared");
    }

    function test_GivenContextIsAlsoStoredForAnotherSender()
        external
        whenValidatingAnIssuanceAction
        whenTheCallerIsTheHandler
        givenContextIsStoredForTheCaller
    {
        (ChainlinkAcePreIssuanceValidatorHarness validator, address engine) =
            __deployInitializedValidator({_defaultAllow: true});

        bytes memory callerContext = bytes("callerContext");
        bytes memory otherContext = bytes("otherContext");

        vm.prank(caller);
        validator.setContext(callerContext);

        vm.prank(otherSender);
        validator.setContext(otherContext);

        // It should call the policy engine with the context keyed on the caller, not another sender.
        vm.expectCall(engine, abi.encodeCall(IPolicyEngine.run, (__expectedPayload(callerContext))));

        vm.prank(handler);
        validator.preIssuance({
            _caller: caller, _receiver: receiver, _onBehalf: onBehalf, _asset: asset, _amount: amount
        });

        // The other sender's context must be untouched.
        assertEq(validator.getSenderContext(otherSender), otherContext, "other sender context affected");
    }
}
