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
import {IPostIssuanceHook} from "src/interfaces/IPostIssuanceHook.sol";
import {Shares} from "src/shares/Shares.sol";

import {ChainlinkAcePostIssuanceValidatorHarness} from "test/harnesses/ChainlinkAcePostIssuanceValidatorHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ChainlinkAcePostIssuanceValidatorTest is TestHelpers {
    Shares shares;

    address handler = makeAddr("handler");
    address caller = makeAddr("caller");
    address receiver = makeAddr("receiver");
    address onBehalf = makeAddr("onBehalf");
    address asset = makeAddr("asset");
    address otherSender = makeAddr("otherSender");
    uint256 sharesAmount = 123;
    uint256 assetAmount = 456;

    function setUp() public {
        shares = createShares();
    }

    // Deploys a real policy engine, the validator harness, and initializes it.
    function __deployInitializedValidator(bool _defaultAllow)
        internal
        returns (ChainlinkAcePostIssuanceValidatorHarness validator_, address engine_)
    {
        engine_ = deployPolicyEngine(_defaultAllow);
        validator_ = new ChainlinkAcePostIssuanceValidatorHarness(address(shares));
        validator_.init(handler, engine_);
    }

    // Builds the exact payload the validator should forward to engine.run.
    function __expectedPayload(bytes memory _context) internal view returns (IPolicyEngine.Payload memory) {
        return IPolicyEngine.Payload({
            selector: IPostIssuanceHook.postIssuance.selector,
            sender: caller,
            data: abi.encode(caller, receiver, onBehalf, asset, sharesAmount, assetAmount),
            context: _context
        });
    }

    modifier whenInitializing() {
        _;
    }

    function test_WhenTheHandlerIsTheZeroAddress() external whenInitializing {
        ChainlinkAcePostIssuanceValidatorHarness validator =
            new ChainlinkAcePostIssuanceValidatorHarness(address(shares));
        address engine = makeAddr("engine");

        // It should revert with {ChainlinkAceIssuanceValidatorBase__Init__EmptyHandler}.
        vm.expectRevert(
            ChainlinkAceIssuanceValidatorBase.ChainlinkAceIssuanceValidatorBase__Init__EmptyHandler.selector,
            address(validator)
        );
        validator.init({_handler: address(0), _policyEngine: engine});
    }

    function test_WhenThePolicyEngineIsTheZeroAddress() external whenInitializing {
        ChainlinkAcePostIssuanceValidatorHarness validator =
            new ChainlinkAcePostIssuanceValidatorHarness(address(shares));

        // It should revert with {ChainlinkAcePolicyProtectedBase__Init__ZeroAddress}.
        vm.expectRevert(
            ChainlinkAcePolicyProtectedBase.ChainlinkAcePolicyProtectedBase__Init__ZeroAddress.selector,
            address(validator)
        );
        validator.init({_handler: handler, _policyEngine: address(0)});
    }

    function test_WhenBothTheHandlerAndThePolicyEngineAreNon_zeroAddresses() external whenInitializing {
        ChainlinkAcePostIssuanceValidatorHarness validator =
            new ChainlinkAcePostIssuanceValidatorHarness(address(shares));
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

    modifier whenValidatingAPostIssuance() {
        _;
    }

    function test_WhenTheCallerIsNotTheHandler() external whenValidatingAPostIssuance {
        (ChainlinkAcePostIssuanceValidatorHarness validator,) = __deployInitializedValidator({_defaultAllow: true});
        address notHandler = makeAddr("notHandler");

        // It should revert with {ChainlinkAceIssuanceValidatorBase__OnlyHandler}.
        vm.expectRevert(
            ChainlinkAceIssuanceValidatorBase.ChainlinkAceIssuanceValidatorBase__OnlyHandler.selector,
            address(validator)
        );
        vm.prank(notHandler);
        validator.postIssuance({
            _caller: caller,
            _receiver: receiver,
            _onBehalf: onBehalf,
            _asset: asset,
            _sharesAmount: sharesAmount,
            _assetAmount: assetAmount
        });
    }

    modifier whenTheCallerIsTheHandler() {
        _;
    }

    function test_WhenTheCallerIsTheHandler() external whenValidatingAPostIssuance whenTheCallerIsTheHandler {
        (ChainlinkAcePostIssuanceValidatorHarness validator, address engine) =
            __deployInitializedValidator({_defaultAllow: true});

        // It should call the policy engine with the post issuance selector.
        // It should call the policy engine with the caller as the sender.
        // It should call the policy engine with the abi-encoded caller, receiver, onBehalf, asset, sharesAmount and
        // assetAmount as data.
        vm.expectCall(engine, abi.encodeCall(IPolicyEngine.run, (__expectedPayload(bytes("")))));

        vm.prank(handler);
        validator.postIssuance({
            _caller: caller,
            _receiver: receiver,
            _onBehalf: onBehalf,
            _asset: asset,
            _sharesAmount: sharesAmount,
            _assetAmount: assetAmount
        });
    }

    function test_GivenThePolicyEngineRejectsTheRun() external whenValidatingAPostIssuance whenTheCallerIsTheHandler {
        // Default-reject engine with no policy attached rejects every run.
        (ChainlinkAcePostIssuanceValidatorHarness validator, address engine) =
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
        validator.postIssuance({
            _caller: caller,
            _receiver: receiver,
            _onBehalf: onBehalf,
            _asset: asset,
            _sharesAmount: sharesAmount,
            _assetAmount: assetAmount
        });
    }

    function test_GivenThePolicyEngineAllowsTheRun() external whenValidatingAPostIssuance whenTheCallerIsTheHandler {
        (ChainlinkAcePostIssuanceValidatorHarness validator,) = __deployInitializedValidator({_defaultAllow: true});

        // It should not revert.
        vm.prank(handler);
        validator.postIssuance({
            _caller: caller,
            _receiver: receiver,
            _onBehalf: onBehalf,
            _asset: asset,
            _sharesAmount: sharesAmount,
            _assetAmount: assetAmount
        });
    }

    function test_GivenNoContextIsStoredForTheCaller() external whenValidatingAPostIssuance whenTheCallerIsTheHandler {
        (ChainlinkAcePostIssuanceValidatorHarness validator, address engine) =
            __deployInitializedValidator({_defaultAllow: true});

        // It should call the policy engine with empty context.
        vm.expectCall(engine, abi.encodeCall(IPolicyEngine.run, (__expectedPayload(bytes("")))));

        vm.prank(handler);
        validator.postIssuance({
            _caller: caller,
            _receiver: receiver,
            _onBehalf: onBehalf,
            _asset: asset,
            _sharesAmount: sharesAmount,
            _assetAmount: assetAmount
        });
    }

    modifier givenContextIsStoredForTheCaller() {
        _;
    }

    function test_GivenContextIsStoredForTheCaller()
        external
        whenValidatingAPostIssuance
        whenTheCallerIsTheHandler
        givenContextIsStoredForTheCaller
    {
        (ChainlinkAcePostIssuanceValidatorHarness validator, address engine) =
            __deployInitializedValidator({_defaultAllow: true});

        bytes memory context = bytes("context");
        vm.prank(caller);
        validator.setContext(context);

        // It should call the policy engine with the stored context.
        vm.expectCall(engine, abi.encodeCall(IPolicyEngine.run, (__expectedPayload(context))));

        vm.prank(handler);
        validator.postIssuance({
            _caller: caller,
            _receiver: receiver,
            _onBehalf: onBehalf,
            _asset: asset,
            _sharesAmount: sharesAmount,
            _assetAmount: assetAmount
        });

        // It should leave the stored context for the caller after the run.
        assertEq(validator.getSenderContext(caller), context, "context should not be cleared");
    }

    function test_GivenContextIsAlsoStoredForAnotherSender()
        external
        whenValidatingAPostIssuance
        whenTheCallerIsTheHandler
        givenContextIsStoredForTheCaller
    {
        (ChainlinkAcePostIssuanceValidatorHarness validator, address engine) =
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
        validator.postIssuance({
            _caller: caller,
            _receiver: receiver,
            _onBehalf: onBehalf,
            _asset: asset,
            _sharesAmount: sharesAmount,
            _assetAmount: assetAmount
        });

        // The other sender's context must be untouched.
        assertEq(validator.getSenderContext(otherSender), otherContext, "other sender context affected");
    }
}
