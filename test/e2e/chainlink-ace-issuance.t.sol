// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Policy} from "@chainlink/policy-management/core/Policy.sol";
import {VolumePolicy} from "@chainlink/policy-management/policies/VolumePolicy.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

import {
    ChainlinkAcePostIssuanceValidator
} from "src/components/issuance-validators/ChainlinkAcePostIssuanceValidator.sol";
import {PostIssuanceExtractor} from "src/components/issuance-validators/PostIssuanceExtractor.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {IPostIssuanceHook} from "src/interfaces/IPostIssuanceHook.sol";
import {Shares} from "src/shares/Shares.sol";

import {SyncDepositHandlerHarness} from "test/harnesses/SyncDepositHandlerHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

/// @dev Proves the full issuance flow: handler -> ChainlinkAcePostIssuanceValidator -> engine -> extractor + policy.
contract ChainlinkAceIssuanceE2ETest is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");
    address depositor = makeAddr("depositor");

    ValuationHandlerHarness valuationHandler;
    SyncDepositHandlerHarness depositHandler;
    ChainlinkAcePostIssuanceValidator validator;
    PostIssuanceExtractor extractor;
    VolumePolicy volumePolicy;
    address engine;

    address depositAsset;
    uint8 constant ASSET_DECIMALS = 6;

    // VolumePolicy operates on the raw asset amount (6 decimals here).
    uint256 constant MAX_AMOUNT = 200e6;

    address policyOwner = makeAddr("volumePolicyOwner");
    // Matches the `initialOwner` set by `deployPolicyEngine`.
    address engineOwner = makeAddr("policyEngineOwner");

    function setUp() public {
        vm.warp(100);

        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        // Deposit asset + handler wiring (mirrors SyncDepositHandler test setUp).
        depositAsset = address(new MockERC20(ASSET_DECIMALS));

        depositHandler = new SyncDepositHandlerHarness(address(shares));
        depositHandler.init(depositAsset);
        vm.prank(admin);
        shares.addDepositHandler(address(depositHandler));

        valuationHandler = new ValuationHandlerHarness(address(shares));
        vm.prank(admin);
        shares.setValuationHandler(address(valuationHandler));

        deal(depositAsset, depositor, 1000e6, true);
        vm.prank(depositor);
        IERC20(depositAsset).approve(address(depositHandler), type(uint256).max);

        // Share price + asset rate so deposits mint non-zero shares.
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: depositAsset, rate: 5e18, expiry: uint40(type(uint40).max)})
        );

        // VolumePolicy.run returns `Continue` on pass, so the engine must default-allow; a
        // rejection still comes from VolumePolicy reverting for an out-of-range amount.
        engine = deployPolicyEngine({_defaultAllow: true});

        // Engine must exist before the validator: `init` attaches to it.
        validator = ChainlinkAcePostIssuanceValidator(
            deployChainlinkAcePostIssuanceValidator(address(shares), address(depositHandler), engine)
        );

        vm.prank(admin);
        depositHandler.setPostIssuanceHook(address(validator));

        extractor = new PostIssuanceExtractor();

        address impl = address(new VolumePolicy());
        bytes memory initData =
            abi.encodeCall(Policy.initialize, (engine, policyOwner, abi.encode(uint256(0), MAX_AMOUNT)));
        volumePolicy = VolumePolicy(address(new ERC1967Proxy(impl, initData)));

        bytes32[] memory params = new bytes32[](1);
        params[0] = extractor.PARAM_ASSET_AMOUNT();

        vm.startPrank(engineOwner);
        IPolicyEngine(engine).setExtractor(IPostIssuanceHook.postIssuance.selector, address(extractor));
        IPolicyEngine(engine)
            .addPolicy(address(validator), IPostIssuanceHook.postIssuance.selector, address(volumePolicy), params);
        vm.stopPrank();
    }

    function test_deposit_succeeds_whenAmountWithinLimit() public {
        uint256 depositAmount = 100e6; // <= MAX_AMOUNT

        vm.prank(depositor);
        uint256 sharesReceived = depositHandler.deposit({_assetAmount: depositAmount});

        assertGt(sharesReceived, 0, "no shares minted");
        assertEq(shares.balanceOf(depositor), sharesReceived, "incorrect shares balance");
    }

    function test_deposit_reverts_whenAmountExceedsLimit() public {
        uint256 depositAmount = 300e6; // > MAX_AMOUNT

        // Reverts via the engine's PolicyRunRejected wrapper, proving the extractor's `amount`
        // parameter is what VolumePolicy rejects on (the success case differs only in `amount`).
        vm.expectPartialRevert(IPolicyEngine.PolicyRunRejected.selector);
        vm.prank(depositor);
        depositHandler.deposit({_assetAmount: depositAmount});
    }
}
