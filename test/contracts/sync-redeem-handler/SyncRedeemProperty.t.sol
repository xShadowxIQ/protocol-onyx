// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SyncRedeemHandler} from "src/components/issuance/redeem-handlers/SyncRedeemHandler.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";

import {SyncDepositHandlerHarness} from "test/harnesses/SyncDepositHandlerHarness.sol";
import {SyncRedeemHandlerHarness} from "test/harnesses/SyncRedeemHandlerHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

/// @dev Property test: per-action rounding must never favor the actor, across random cached prices.
/// Asset has 6 decimals, rate is 1:1 (1 asset = 1e12 units of 18-decimal value).
contract SyncRedeemPropertyTest is StdInvariant, TestHelpers {
    Shares shares;
    address admin = makeAddr("admin");
    ValuationHandlerHarness valuationHandler;
    SyncDepositHandlerHarness depositHandler;
    SyncRedeemHandlerHarness redeemHandler;
    address redeemAsset;

    address[3] actors;
    bool public violated;
    uint256 public depositsOk;
    uint256 public redeemsOk;
    string public lastViolation;

    uint256 constant ASSET_TO_VALUE = 1e12;

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

        vm.startPrank(admin);
        shares.addDepositHandler(address(depositHandler));
        shares.addRedeemHandler(address(redeemHandler));
        shares.setValuationHandler(address(valuationHandler));
        // Disable staleness so the property focuses on rounding, not timing.
        depositHandler.setMaxSharePriceStaleness(type(uint24).max);
        redeemHandler.setMaxSharePriceStaleness(type(uint24).max);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({
                asset: redeemAsset, rate: 1e18, expiry: uint40(type(uint40).max)
            })
        );
        vm.stopPrank();

        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});

        for (uint256 i; i < actors.length; i++) {
            actors[i] = makeAddr(string.concat("actor", vm.toString(i)));
            deal(redeemAsset, actors[i], 1e15, true);
            vm.prank(actors[i]);
            IERC20(redeemAsset).approve(address(depositHandler), type(uint256).max);
        }

        targetContract(address(this));
    }

    // ---- Fuzzed actions -----------------------------------------------------------------------------------------------

    function deposit(uint256 _actorSeed, uint256 _amount) external {
        address actor = actors[_actorSeed % actors.length];
        uint256 amount = bound(_amount, 1, 1e15);

        (uint256 price,) = valuationHandler.getSharePrice();
        uint256 supplyBefore = shares.totalSupply();
        uint256 balBefore = shares.balanceOf(actor);

        vm.prank(actor);
        try depositHandler.deposit({_assetAmount: amount}) returns (uint256 minted) {
            depositsOk++;
            // Property: minted shares never exceed the deposited value at the cached price, rounded down.
            // minted * price <= value * 1e18, where value = amount * 1e12
            if (minted * price > amount * ASSET_TO_VALUE * 1e18) {
                _flag("deposit minted more value than deposited");
            }
            if (shares.balanceOf(actor) - balBefore != minted || shares.totalSupply() - supplyBefore != minted) {
                _flag("deposit mint accounting mismatch");
            }
        } catch {}
    }

    function redeem(uint256 _actorSeed, uint256 _sharesAmount) external {
        address actor = actors[_actorSeed % actors.length];
        uint256 held = shares.balanceOf(actor);
        if (held == 0) return;
        uint256 sharesAmount = bound(_sharesAmount, 1, held);

        (uint256 price,) = valuationHandler.getSharePrice();

        vm.prank(actor);
        try redeemHandler.redeem({_sharesAmount: sharesAmount}) returns (uint256 assetsOut) {
            redeemsOk++;
            // Property: assets paid never exceed the value of shares burned at the cached price, rounded down.
            // assetsOut * 1e12 * 1e18 <= sharesAmount * price
            if (assetsOut * ASSET_TO_VALUE * 1e18 > sharesAmount * price) {
                _flag("redeem paid more value than burned shares were worth");
            }
        } catch {}
    }

    function moveSharePrice(uint256 _value) external {
        uint256 value = bound(_value, 0, 10e18); // 0 exercises the default-price fallback
        valuationHandler.harness_setLastShareValue({_shareValue: value, _timestamp: block.timestamp});
    }

    function warp(uint256 _seconds) external {
        vm.warp(block.timestamp + bound(_seconds, 0, 1 days));
    }

    // ---- Helpers ------------------------------------------------------------------------------------------------------

    function _flag(string memory _msg) internal {
        if (!violated) lastViolation = _msg;
        violated = true;
    }

    /// @dev Invariant: no single deposit or redemption ever rounds in the actor's favor.
    function invariant_NoRoundingFavorsActor() public view {
        require(!violated, lastViolation);
    }

    /// @dev Smoke test: confirms the fuzzed actions really execute, so the invariant above is not vacuous.
    function test_ActionsExecute() public {
        this.deposit(0, 1e9);
        this.moveSharePrice(1e18);
        this.redeem(0, type(uint256).max);
        assertGt(depositsOk, 0, "no deposit succeeded");
        assertGt(redeemsOk, 0, "no redemption succeeded");
    }
}
