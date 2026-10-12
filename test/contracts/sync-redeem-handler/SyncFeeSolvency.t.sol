// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";

import {FeeHandlerHarness} from "test/harnesses/FeeHandlerHarness.sol";
import {SyncDepositHandlerHarness} from "test/harnesses/SyncDepositHandlerHarness.sol";
import {SyncRedeemHandlerHarness} from "test/harnesses/SyncRedeemHandlerHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

/// @dev Solvency property with entrance and exit fees enabled and a fixed, non-round cached price.
/// At a fixed price: vault asset value (1 asset unit = 1e12 value) must always cover shares outstanding at the
/// cached price plus fees owed to recipients. Every rounding step in the protocol floors in the vault's favor,
/// so any violation would be a real accounting bug.
contract SyncFeeSolvencyTest is StdInvariant, TestHelpers {
    Shares shares;
    address admin = makeAddr("admin");
    ValuationHandlerHarness valuationHandler;
    SyncDepositHandlerHarness depositHandler;
    SyncRedeemHandlerHarness redeemHandler;
    FeeHandlerHarness feeHandler;
    address redeemAsset;

    address[3] actors;
    address feeRecipient = makeAddr("feeRecipient");
    uint256 constant FIXED_PRICE = 0.37e18; // non-round, so floors actually bite
    uint256 constant ASSET_TO_VALUE = 1e12;

    bool public violated;
    string public lastViolation;
    uint256 public ops;

    function setUp() public {
        vm.warp(100);
        shares = createShares();
        address owner = shares.owner();
        vm.prank(owner);
        shares.addAdmin(admin);

        redeemAsset = address(new MockERC20(6));

        depositHandler = new SyncDepositHandlerHarness(address(shares));
        depositHandler.init(redeemAsset);
        redeemHandler = new SyncRedeemHandlerHarness(address(shares));
        redeemHandler.init(redeemAsset);
        valuationHandler = new ValuationHandlerHarness(address(shares));
        feeHandler = new FeeHandlerHarness(address(shares));

        vm.startPrank(admin);
        shares.addDepositHandler(address(depositHandler));
        shares.addRedeemHandler(address(redeemHandler));
        shares.setValuationHandler(address(valuationHandler));
        shares.setFeeHandler(address(feeHandler));
        feeHandler.setEntranceFee({_feeBps: 137, _recipient: feeRecipient});
        feeHandler.setExitFee({_feeBps: 251, _recipient: feeRecipient});
        depositHandler.setMaxSharePriceStaleness(type(uint24).max);
        redeemHandler.setMaxSharePriceStaleness(type(uint24).max);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: redeemAsset, rate: 1e18, expiry: uint40(type(uint40).max)})
        );
        vm.stopPrank();

        valuationHandler.harness_setLastShareValue({_shareValue: FIXED_PRICE, _timestamp: block.timestamp});

        for (uint256 i; i < actors.length; i++) {
            actors[i] = makeAddr(string.concat("feeActor", vm.toString(i)));
            deal(redeemAsset, actors[i], 1e15, true);
            vm.prank(actors[i]);
            IERC20(redeemAsset).approve(address(depositHandler), type(uint256).max);
        }

        targetContract(address(this));
    }

    function deposit(uint256 _actorSeed, uint256 _amount) external {
        address actor = actors[_actorSeed % actors.length];
        uint256 amount = bound(_amount, 1, 1e15);
        vm.prank(actor);
        try depositHandler.deposit({_assetAmount: amount}) returns (uint256) {
            ops++;
        } catch {}
        _checkSolvency();
    }

    function redeem(uint256 _actorSeed, uint256 _sharesAmount) external {
        address actor = actors[_actorSeed % actors.length];
        uint256 held = shares.balanceOf(actor);
        if (held == 0) return;
        vm.prank(actor);
        try redeemHandler.redeem({_sharesAmount: bound(_sharesAmount, 1, held)}) returns (uint256) {
            ops++;
        } catch {}
        _checkSolvency();
    }

    function _checkSolvency() internal {
        uint256 assetValue = IERC20(redeemAsset).balanceOf(address(shares)) * ASSET_TO_VALUE;
        uint256 supplyValue = shares.totalSupply() * FIXED_PRICE / 1e18;
        uint256 owed = feeHandler.getTotalValueOwed();
        if (assetValue < supplyValue + owed) {
            if (!violated) lastViolation = "vault asset value does not cover shares plus fees owed";
            violated = true;
        }
    }

    function invariant_FeeSolvency() public view {
        require(!violated, lastViolation);
    }

    /// @dev Smoke test: the fuzzed actions really execute, so the invariant is not vacuous.
    function test_FeeActionsExecute() public {
        this.deposit(0, 1e9);
        this.redeem(0, type(uint256).max);
        assertGt(ops, 1, "fee-path actions did not execute");
        assertGt(feeHandler.getTotalValueOwed(), 0, "no fees were booked");
    }
}
