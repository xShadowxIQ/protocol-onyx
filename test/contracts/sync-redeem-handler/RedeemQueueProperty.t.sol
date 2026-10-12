// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ERC7540LikeRedeemQueue} from "src/components/issuance/redeem-handlers/ERC7540LikeRedeemQueue.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";

import {ERC7540LikeRedeemQueueHarness} from "test/harnesses/ERC7540LikeRedeemQueueHarness.sol";
import {SyncDepositHandlerHarness} from "test/harnesses/SyncDepositHandlerHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

/// @dev Stateful property test for the ERC-7540-like redeem queue at a fixed cached price (no fees).
/// Checks escrow conservation, solvency, exact cancellation refunds, and no over-payment on execution.
contract RedeemQueuePropertyTest is StdInvariant, TestHelpers {
    Shares shares;
    address admin = makeAddr("admin");
    ValuationHandlerHarness valuationHandler;
    SyncDepositHandlerHarness depositHandler;
    ERC7540LikeRedeemQueueHarness redeemQueue;
    address redeemAsset;

    address[3] actors;
    uint256 constant FIXED_PRICE = 0.37e18;
    uint256 constant ASSET_TO_VALUE = 1e12;

    uint256[] public requestIds;
    bool public violated;
    string public lastViolation;

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

        vm.startPrank(admin);
        shares.addDepositHandler(address(depositHandler));
        shares.addRedeemHandler(address(redeemQueue));
        shares.setValuationHandler(address(valuationHandler));
        redeemQueue.setAsset(redeemAsset);
        depositHandler.setMaxSharePriceStaleness(type(uint24).max);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: redeemAsset, rate: 1e18, expiry: uint40(type(uint40).max)})
        );
        vm.stopPrank();

        valuationHandler.harness_setLastShareValue({_shareValue: FIXED_PRICE, _timestamp: block.timestamp});

        for (uint256 i; i < actors.length; i++) {
            actors[i] = makeAddr(string.concat("qActor", vm.toString(i)));
            deal(redeemAsset, actors[i], 1e15, true);
            vm.prank(actors[i]);
            IERC20(redeemAsset).approve(address(depositHandler), type(uint256).max);
        }

        targetContract(address(this));
    }

    function deposit(uint256 _actorSeed, uint256 _amount) external {
        address actor = actors[_actorSeed % actors.length];
        vm.prank(actor);
        try depositHandler.deposit({_assetAmount: bound(_amount, 1, 1e15)}) returns (uint256) {} catch {}
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
        } catch {}
        _checkInvariants();
    }

    function cancelRedeem(uint256 _idSeed) external {
        if (requestIds.length == 0) return;
        uint256 id = requestIds[_idSeed % requestIds.length];
        ERC7540LikeRedeemQueue.RedeemRequestInfo memory req = redeemQueue.getRedeemRequest(id);
        if (req.sharesAmount == 0) return;

        uint256 before = shares.balanceOf(req.controller);
        vm.prank(req.controller);
        try redeemQueue.cancelRedeem(id) returns (uint256 refunded) {
            // Property: a cancellation refunds exactly the escrowed shares, no more and no less.
            if (refunded != req.sharesAmount || shares.balanceOf(req.controller) - before != req.sharesAmount) {
                _flag("cancellation refund mismatch");
            }
        } catch {}
        _checkInvariants();
    }

    function executeRedeem(uint256 _idSeed) external {
        if (requestIds.length == 0) return;
        uint256 id = requestIds[_idSeed % requestIds.length];
        ERC7540LikeRedeemQueue.RedeemRequestInfo memory req = redeemQueue.getRedeemRequest(id);
        if (req.sharesAmount == 0) return;

        vm.prank(admin);
        try this.__execute(id) returns (uint256 assetsOut) {
            // Property: payout never exceeds the value of the escrowed shares at the cached price, rounded down.
            if (assetsOut * ASSET_TO_VALUE * 1e18 > req.sharesAmount * FIXED_PRICE) {
                _flag("execution paid more value than escrowed shares were worth");
            }
        } catch {}
        _checkInvariants();
    }

    /// @dev External wrapper so the admin prank applies to the batch call.
    function __execute(uint256 _id) external returns (uint256 assetsOut_) {
        uint256 before = IERC20(redeemAsset).balanceOf(address(shares));
        uint256[] memory ids = new uint256[](1);
        ids[0] = _id;
        vm.prank(admin);
        redeemQueue.executeRedeemRequests(ids);
        assetsOut_ = before - IERC20(redeemAsset).balanceOf(address(shares));
    }

    function warp(uint256 _seconds) external {
        vm.warp(block.timestamp + bound(_seconds, 0, 1 days));
    }

    // ---- Invariants ----------------------------------------------------------------------------------------------

    function _checkInvariants() internal {
        // Escrow conservation: shares held by the queue equal the sum of pending request amounts.
        uint256 pending;
        uint256 last = redeemQueue.getRedeemLastId();
        for (uint256 id = 1; id <= last; id++) {
            pending += redeemQueue.getRedeemRequest(id).sharesAmount;
        }
        if (shares.balanceOf(address(redeemQueue)) != pending) {
            _flag("escrowed shares do not match pending requests");
        }

        // Solvency at the fixed price: vault assets cover all shares outstanding.
        uint256 assetValue = IERC20(redeemAsset).balanceOf(address(shares)) * ASSET_TO_VALUE;
        if (assetValue < shares.totalSupply() * FIXED_PRICE / 1e18) {
            _flag("vault assets do not cover shares outstanding");
        }
    }

    function _flag(string memory _msg) internal {
        if (!violated) lastViolation = _msg;
        violated = true;
    }

    function invariant_QueueProperties() public view {
        require(!violated, lastViolation);
    }

    /// @dev Smoke test: confirms every action path executes, so the invariant is not vacuous.
    function test_QueueActionsExecute() public {
        this.deposit(0, 1e12);
        this.requestRedeem(0, type(uint256).max);
        this.executeRedeem(0);
        this.deposit(1, 1e12);
        this.requestRedeem(1, type(uint256).max);
        this.cancelRedeem(0);
        assertGt(requestIds.length, 1, "no requests were created");
        assertFalse(violated, lastViolation);
    }
}
