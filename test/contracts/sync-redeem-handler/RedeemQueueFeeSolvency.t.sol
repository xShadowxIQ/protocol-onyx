// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ERC7540LikeRedeemQueue} from "src/components/issuance/redeem-handlers/ERC7540LikeRedeemQueue.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";

import {ERC7540LikeRedeemQueueHarness} from "test/harnesses/ERC7540LikeRedeemQueueHarness.sol";
import {FeeHandlerHarness} from "test/harnesses/FeeHandlerHarness.sol";
import {SyncDepositHandlerHarness} from "test/harnesses/SyncDepositHandlerHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

/// @dev Queue redemptions with an exit fee (and entrance fee) enabled at a non-round fixed price.
/// Solvency must hold including fees owed, and queue execution must never pay out more than the net,
/// post-fee value of the escrowed shares.
contract RedeemQueueFeeSolvencyTest is StdInvariant, TestHelpers {
    Shares shares;
    address admin = makeAddr("admin");
    ValuationHandlerHarness valuationHandler;
    SyncDepositHandlerHarness depositHandler;
    ERC7540LikeRedeemQueueHarness redeemQueue;
    FeeHandlerHarness feeHandler;
    address redeemAsset;

    address[3] actors;
    address feeRecipient = makeAddr("feeRecipient");
    uint256 constant FIXED_PRICE = 0.37e18;
    uint256 constant ASSET_TO_VALUE = 1e12;

    uint256[] public requestIds;
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
        redeemQueue = new ERC7540LikeRedeemQueueHarness(address(shares));
        valuationHandler = new ValuationHandlerHarness(address(shares));
        feeHandler = new FeeHandlerHarness(address(shares));

        vm.startPrank(admin);
        shares.addDepositHandler(address(depositHandler));
        shares.addRedeemHandler(address(redeemQueue));
        shares.setValuationHandler(address(valuationHandler));
        shares.setFeeHandler(address(feeHandler));
        feeHandler.setEntranceFee({_feeBps: 137, _recipient: feeRecipient});
        feeHandler.setExitFee({_feeBps: 251, _recipient: feeRecipient});
        redeemQueue.setAsset(redeemAsset);
        depositHandler.setMaxSharePriceStaleness(type(uint24).max);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: redeemAsset, rate: 1e18, expiry: uint40(type(uint40).max)})
        );
        vm.stopPrank();

        valuationHandler.harness_setLastShareValue({_shareValue: FIXED_PRICE, _timestamp: block.timestamp});

        for (uint256 i; i < actors.length; i++) {
            actors[i] = makeAddr(string.concat("qfActor", vm.toString(i)));
            deal(redeemAsset, actors[i], 1e15, true);
            vm.prank(actors[i]);
            IERC20(redeemAsset).approve(address(depositHandler), type(uint256).max);
        }

        targetContract(address(this));
    }

    function deposit(uint256 _actorSeed, uint256 _amount) external {
        address actor = actors[_actorSeed % actors.length];
        vm.prank(actor);
        try depositHandler.deposit({_assetAmount: bound(_amount, 1, 1e15)}) returns (uint256) {
            ops++;
        } catch {}
        _checkInvariants();
    }

    function requestRedeem(uint256 _actorSeed, uint256 _sharesAmount) external {
        address actor = actors[_actorSeed % actors.length];
        uint256 held = shares.balanceOf(actor);
        if (held == 0) return;
        vm.prank(actor);
        try redeemQueue.requestRedeem({_shares: bound(_sharesAmount, 1, held), _controller: actor, _owner: actor}) returns (
            uint256 id
        ) {
            requestIds.push(id);
            ops++;
        } catch {}
        _checkInvariants();
    }

    function cancelRedeem(uint256 _idSeed) external {
        if (requestIds.length == 0) return;
        uint256 id = requestIds[_idSeed % requestIds.length];
        ERC7540LikeRedeemQueue.RedeemRequestInfo memory req = redeemQueue.getRedeemRequest(id);
        if (req.sharesAmount == 0) return;

        vm.prank(req.controller);
        try redeemQueue.cancelRedeem(id) returns (uint256 refunded) {
            if (refunded != req.sharesAmount) _flag("cancellation refund mismatch");
            ops++;
        } catch {}
        _checkInvariants();
    }

    function executeRedeem(uint256 _idSeed) external {
        if (requestIds.length == 0) return;
        uint256 id = requestIds[_idSeed % requestIds.length];
        ERC7540LikeRedeemQueue.RedeemRequestInfo memory req = redeemQueue.getRedeemRequest(id);
        if (req.sharesAmount == 0) return;

        uint256 owedBefore = feeHandler.getTotalValueOwed();
        uint256 before = IERC20(redeemAsset).balanceOf(req.controller);
        try this.__execute(id) {
            uint256 paid = IERC20(redeemAsset).balanceOf(req.controller) - before;
            uint256 feeValue = feeHandler.getTotalValueOwed() - owedBefore;

            // Property: payout never exceeds the net (post-fee) value of the escrowed shares at the cached price.
            // Fee booked as value owed must not exceed the value of the gross shares.
            if (paid * ASSET_TO_VALUE * 1e18 > req.sharesAmount * FIXED_PRICE) {
                _flag("queue execution paid more than the escrowed shares were worth");
            }
            if (feeValue > req.sharesAmount * FIXED_PRICE / 1e18) {
                _flag("exit fee booked exceeds value of gross shares");
            }
            ops++;
        } catch {}
        _checkInvariants();
    }

    /// @dev External wrapper so the admin prank applies to the batch call.
    function __execute(uint256 _id) external {
        uint256[] memory ids = new uint256[](1);
        ids[0] = _id;
        vm.prank(admin);
        redeemQueue.executeRedeemRequests(ids);
    }

    function warp(uint256 _seconds) external {
        vm.warp(block.timestamp + bound(_seconds, 0, 1 days));
    }

    function _checkInvariants() internal {
        // Escrow conservation.
        uint256 pending;
        uint256 last = redeemQueue.getRedeemLastId();
        for (uint256 id = 1; id <= last; id++) {
            pending += redeemQueue.getRedeemRequest(id).sharesAmount;
        }
        if (shares.balanceOf(address(redeemQueue)) != pending) {
            _flag("escrowed shares do not match pending requests");
        }

        // Solvency including fees owed: vault assets must cover shares outstanding plus value owed to recipients.
        uint256 assetValue = IERC20(redeemAsset).balanceOf(address(shares)) * ASSET_TO_VALUE;
        uint256 supplyValue = shares.totalSupply() * FIXED_PRICE / 1e18;
        if (assetValue < supplyValue + feeHandler.getTotalValueOwed()) {
            _flag("vault assets do not cover shares plus fees owed");
        }
    }

    function _flag(string memory _msg) internal {
        if (!violated) lastViolation = _msg;
        violated = true;
    }

    function invariant_RedeemQueueFeeSolvency() public view {
        require(!violated, lastViolation);
    }

    /// @dev Smoke test: confirms the fee-bearing queue paths execute, so the invariant is not vacuous.
    function test_RedeemQueueFeeActionsExecute() public {
        this.deposit(0, 1e12);
        this.requestRedeem(0, type(uint256).max);
        this.executeRedeem(0);
        assertFalse(violated, lastViolation);
        assertGt(feeHandler.getTotalValueOwed(), 0, "no exit fee was booked");
        assertGt(ops, 2, "queue actions did not execute");
    }
}
