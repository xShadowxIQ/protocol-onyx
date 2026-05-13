// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";

import {BeaconFactory} from "src/factories/BeaconFactory.sol";
import {ComponentBeaconFactory} from "src/factories/ComponentBeaconFactory.sol";
import {FeeHandler} from "src/components/fees/FeeHandler.sol";
import {
    ContinuousFlatRateManagementFeeTracker
} from "src/components/fees/management-fee-trackers/ContinuousFlatRateManagementFeeTracker.sol";
import {
    ContinuousFlatRatePerformanceFeeTracker
} from "src/components/fees/performance-fee-trackers/ContinuousFlatRatePerformanceFeeTracker.sol";
import {ERC7540LikeDepositQueue} from "src/components/issuance/deposit-handlers/ERC7540LikeDepositQueue.sol";
import {SyncDepositHandler} from "src/components/issuance/deposit-handlers/SyncDepositHandler.sol";
import {ERC7540LikeRedeemQueue} from "src/components/issuance/redeem-handlers/ERC7540LikeRedeemQueue.sol";
import {SharesOwnedAddressList} from "src/components/lists/SharesOwnedAddressList.sol";
import {
    AddressListsSharesTransferValidator
} from "src/components/shares-transfer-validators/AddressListsSharesTransferValidator.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {AccountERC20Tracker} from "src/components/value/position-trackers/AccountERC20Tracker.sol";
import {LinearCreditDebtTracker} from "src/components/value/position-trackers/LinearCreditDebtTracker.sol";
import {Global} from "src/global/Global.sol";
import {SharesDeployer} from "src/infra/deployment/SharesDeployer.sol";
import {IAddressList} from "src/infra/lists/address-list/IAddressList.sol";
import {OwnableAddressList} from "src/infra/lists/address-list/OwnableAddressList.sol";
import {Shares} from "src/shares/Shares.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";

contract SharesDeployerTest is Test {
    SharesDeployer deployer;

    BeaconFactory sharesFactory;
    ComponentBeaconFactory feeHandlerFactory;
    ComponentBeaconFactory managementFeeTrackerFactory;
    ComponentBeaconFactory performanceFeeTrackerFactory;
    ComponentBeaconFactory valuationHandlerFactory;
    ComponentBeaconFactory accountERC20TrackerFactory;
    ComponentBeaconFactory linearCreditDebtTrackerFactory;
    ComponentBeaconFactory depositQueueFactory;
    ComponentBeaconFactory syncDepositHandlerFactory;
    ComponentBeaconFactory redeemQueueFactory;
    ComponentBeaconFactory sharesOwnedAddressListFactory;
    BeaconFactory ownableAddressListFactory;
    ComponentBeaconFactory addressListsSharesTransferValidatorFactory;

    address vaultOwner = makeAddr("vaultOwner");
    address feeRecipient = makeAddr("feeRecipient");
    address adminA = makeAddr("adminA");
    address adminB = makeAddr("adminB");
    address validator = makeAddr("validator");
    address depositorAllowlist = makeAddr("depositorAllowlist");
    MockERC20 usdc;
    MockERC20 weth;

    bytes32 constant VALUE_ASSET = bytes32("USD");
    string constant SHARES_NAME = "Onyx Shares";
    string constant SHARES_SYMBOL = "oSHR";

    function setUp() public {
        Global global = new Global();
        global.init({_owner: address(this)});

        sharesFactory = new BeaconFactory(address(global));
        feeHandlerFactory = new ComponentBeaconFactory(address(global));
        managementFeeTrackerFactory = new ComponentBeaconFactory(address(global));
        performanceFeeTrackerFactory = new ComponentBeaconFactory(address(global));
        valuationHandlerFactory = new ComponentBeaconFactory(address(global));
        accountERC20TrackerFactory = new ComponentBeaconFactory(address(global));
        linearCreditDebtTrackerFactory = new ComponentBeaconFactory(address(global));
        depositQueueFactory = new ComponentBeaconFactory(address(global));
        syncDepositHandlerFactory = new ComponentBeaconFactory(address(global));
        redeemQueueFactory = new ComponentBeaconFactory(address(global));
        sharesOwnedAddressListFactory = new ComponentBeaconFactory(address(global));
        ownableAddressListFactory = new BeaconFactory(address(global));
        addressListsSharesTransferValidatorFactory = new ComponentBeaconFactory(address(global));

        sharesFactory.setImplementation(address(new Shares()));
        feeHandlerFactory.setImplementation(address(new FeeHandler()));
        managementFeeTrackerFactory.setImplementation(address(new ContinuousFlatRateManagementFeeTracker()));
        performanceFeeTrackerFactory.setImplementation(address(new ContinuousFlatRatePerformanceFeeTracker()));
        valuationHandlerFactory.setImplementation(address(new ValuationHandler()));
        accountERC20TrackerFactory.setImplementation(address(new AccountERC20Tracker()));
        linearCreditDebtTrackerFactory.setImplementation(address(new LinearCreditDebtTracker()));
        depositQueueFactory.setImplementation(address(new ERC7540LikeDepositQueue()));
        syncDepositHandlerFactory.setImplementation(address(new SyncDepositHandler()));
        redeemQueueFactory.setImplementation(address(new ERC7540LikeRedeemQueue()));
        sharesOwnedAddressListFactory.setImplementation(address(new SharesOwnedAddressList()));
        ownableAddressListFactory.setImplementation(address(new OwnableAddressList()));
        addressListsSharesTransferValidatorFactory.setImplementation(address(new AddressListsSharesTransferValidator()));

        SharesDeployer.Factories memory factories = SharesDeployer.Factories({
            sharesFactory: address(sharesFactory),
            feeHandlerFactory: address(feeHandlerFactory),
            valuationHandlerFactory: address(valuationHandlerFactory),
            managementFeeTrackerFactory: address(managementFeeTrackerFactory),
            performanceFeeTrackerFactory: address(performanceFeeTrackerFactory),
            accountERC20TrackerFactory: address(accountERC20TrackerFactory),
            linearCreditDebtTrackerFactory: address(linearCreditDebtTrackerFactory),
            depositQueueFactory: address(depositQueueFactory),
            syncDepositHandlerFactory: address(syncDepositHandlerFactory),
            redeemQueueFactory: address(redeemQueueFactory),
            sharesOwnedAddressListFactory: address(sharesOwnedAddressListFactory),
            ownableAddressListFactory: address(ownableAddressListFactory),
            addressListsSharesTransferValidatorFactory: address(addressListsSharesTransferValidatorFactory)
        });
        deployer = new SharesDeployer(factories);

        usdc = new MockERC20(6);
        weth = new MockERC20(18);
    }

    //==================================================================================================================
    // Default config helpers
    //==================================================================================================================

    function __minimalConfig() internal view returns (SharesDeployer.DeployConfig memory cfg) {
        cfg.shares = SharesDeployer.SharesConfig({name: SHARES_NAME, symbol: SHARES_SYMBOL, valueAsset: VALUE_ASSET});
        cfg.initialOwner = address(deployer);
        cfg.nominatedOwner = vaultOwner;
    }

    function __fullConfig() internal view returns (SharesDeployer.DeployConfig memory cfg) {
        cfg = __minimalConfig();

        cfg.admins = new address[](2);
        cfg.admins[0] = adminA;
        cfg.admins[1] = adminB;

        cfg.transferValidator = SharesDeployer.TransferValidatorConfig({
            source: SharesDeployer.TransferValidatorSource.Existing,
            existing: validator,
            recipientList: __validatorListNone(),
            senderList: __validatorListNone()
        });

        ValuationHandler.AssetRateInput[] memory rates = new ValuationHandler.AssetRateInput[](2);
        rates[0] = ValuationHandler.AssetRateInput({
            asset: address(usdc), rate: uint128(1e18), expiry: uint40(block.timestamp + 365 days)
        });
        rates[1] = ValuationHandler.AssetRateInput({
            asset: address(weth), rate: uint128(3000e18), expiry: uint40(block.timestamp + 365 days)
        });
        cfg.components.valuationHandler = SharesDeployer.ValuationHandlerConfig({deploy: true, assetRates: rates});

        address[] memory trackerAssets = new address[](2);
        trackerAssets[0] = address(usdc);
        trackerAssets[1] = address(weth);
        cfg.components.accountERC20Tracker =
            SharesDeployer.AccountERC20TrackerConfig({deploy: true, assets: trackerAssets});

        cfg.components.linearCreditDebtTracker = SharesDeployer.LinearCreditDebtTrackerConfig({deploy: true});

        cfg.components.feeHandler = SharesDeployer.FeeHandlerConfig({
            deploy: true,
            feeAsset: address(usdc),
            entranceFeeBps: 50,
            entranceFeeRecipient: feeRecipient,
            exitFeeBps: 25,
            exitFeeRecipient: feeRecipient
        });
        cfg.components.managementFee =
            SharesDeployer.ManagementFeeConfig({deploy: true, feeBps: 100, recipient: feeRecipient});
        cfg.components.performanceFee = SharesDeployer.PerformanceFeeConfig({
            deploy: true, feeBps: 1000, hurdleRateBps: 500, recipient: feeRecipient
        });

        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        cfg.components.queueDepositHandlers[0] = SharesDeployer.QueueDepositHandlerConfig({
            asset: address(usdc),
            minRequestDuration: 3600,
            restriction: ERC7540LikeDepositQueue.DepositRestriction.None,
            externalListSource: SharesDeployer.ExternalListSource.None,
            externalListExisting: address(0),
            sharedAddressListIndex: 0,
            allowedDepositors: new address[](0)
        });

        cfg.components.syncDepositHandlers = new SharesDeployer.SyncDepositHandlerConfig[](1);
        cfg.components.syncDepositHandlers[0] = SharesDeployer.SyncDepositHandlerConfig({
            asset: address(usdc),
            maxSharePriceStaleness: 600,
            depositorAllowlistSource: SharesDeployer.ExternalListSource.Existing,
            depositorAllowlistExisting: depositorAllowlist,
            sharedAddressListIndex: 0
        });

        cfg.components.redeemHandlers = new SharesDeployer.RedeemHandlerConfig[](1);
        cfg.components.redeemHandlers[0] =
            SharesDeployer.RedeemHandlerConfig({asset: address(usdc), minRequestDuration: 7200});
    }

    //==================================================================================================================
    // Happy path: full config
    //==================================================================================================================

    function test_deploy_fullConfig_success() public {
        SharesDeployer.DeployConfig memory cfg = __fullConfig();

        vm.recordLogs();
        address sharesAddr = deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Shares shares = Shares(sharesAddr);

        assertEq(shares.name(), SHARES_NAME, "name");
        assertEq(shares.symbol(), SHARES_SYMBOL, "symbol");
        assertEq(shares.getValueAsset(), VALUE_ASSET, "valueAsset");

        assertTrue(shares.getFeeHandler() != address(0), "feeHandler unset");
        assertTrue(shares.getValuationHandler() != address(0), "valuationHandler unset");
        assertEq(shares.getSharesTransferValidator(), validator, "transferValidator");

        ValuationHandler vh = ValuationHandler(shares.getValuationHandler());
        address[] memory trackers = vh.getPositionTrackers();
        assertEq(trackers.length, 2, "tracker count");
        AccountERC20Tracker accountTracker = AccountERC20Tracker(trackers[0]);
        assertEq(accountTracker.getAssets().length, 2, "tracker assets");
        assertEq(vh.getAssetRateInfo(address(usdc)).rate, uint128(1e18), "usdc rate");
        assertEq(vh.getAssetRateInfo(address(weth)).rate, uint128(3000e18), "weth rate");

        FeeHandler fh = FeeHandler(shares.getFeeHandler());
        assertEq(fh.getFeeAsset(), address(usdc), "fee asset");
        assertEq(fh.getEntranceFeeBps(), 50, "entrance bps");
        assertEq(fh.getExitFeeBps(), 25, "exit bps");
        assertTrue(fh.getManagementFeeTracker() != address(0), "mft unset");
        assertTrue(fh.getPerformanceFeeTracker() != address(0), "pft unset");

        ContinuousFlatRatePerformanceFeeTracker pft =
            ContinuousFlatRatePerformanceFeeTracker(fh.getPerformanceFeeTracker());
        assertGt(pft.getHighWaterMark(), 0, "pft hwm");
        assertEq(pft.getHurdleRate(), int16(500), "pft hurdle");

        // Sync deposit handler wired correctly
        address[] memory syncs = __collectProxiesFromFactory(logs, address(syncDepositHandlerFactory));
        assertEq(syncs.length, 1, "sync handler count");
        SyncDepositHandler sync = SyncDepositHandler(syncs[0]);
        assertEq(sync.getAsset(), address(usdc), "sync asset");
        assertEq(sync.getDepositorAllowlist(), depositorAllowlist, "sync allowlist");
        assertEq(sync.getMaxSharePriceStaleness(), 600, "sync staleness");
        assertTrue(shares.isDepositHandler(syncs[0]), "sync handler not registered on Shares");

        assertTrue(shares.isAdmin(adminA), "adminA");
        assertTrue(shares.isAdmin(adminB), "adminB");
        assertEq(shares.pendingOwner(), vaultOwner, "pending owner");
        assertEq(shares.owner(), address(deployer), "deployer is still owner until acceptance");

        assertFalse(shares.isDepositHandler(address(deployer)), "deployer still deposit handler");
    }

    //==================================================================================================================
    // VaultDeployed event
    //==================================================================================================================

    function test_deploy_emitsVaultDeployedEvent_withCorrectDeployedStruct() public {
        // Start from fullConfig (touches almost every Deployed field), then add a shared address
        // list to exercise that field as well
        SharesDeployer.DeployConfig memory cfg = __fullConfig();
        address[] memory seed = new address[](1);
        seed[0] = makeAddr("vaultDeployedEventSeed");
        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.SharesOwned, ownableListOwner: address(0), seededAddresses: seed
        });

        vm.recordLogs();
        address sharesAddr = deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (SharesDeployer.Deployed memory d, address nominated) = __findVaultDeployedEvent(logs);

        assertEq(d.shares, sharesAddr, "event.shares");
        __assertVaultDeployed_singleFields(d, logs);
        __assertVaultDeployed_arrayFields(d, logs);

        assertEq(d.transferValidator, validator, "event.transferValidator (existing)");
        assertEq(d.transferValidatorRecipientList, address(0), "event.transferValidatorRecipientList");
        assertEq(d.transferValidatorSenderList, address(0), "event.transferValidatorSenderList");

        assertEq(nominated, cfg.nominatedOwner, "event.nominatedOwner");
    }

    function __findVaultDeployedEvent(Vm.Log[] memory _logs)
        internal
        view
        returns (SharesDeployer.Deployed memory d_, address nominated_)
    {
        for (uint256 i; i < _logs.length; i++) {
            if (_logs[i].emitter == address(deployer)) {
                (d_, nominated_) = abi.decode(_logs[i].data, (SharesDeployer.Deployed, address));
                return (d_, nominated_);
            }
        }
        revert("VaultDeployed not emitted by deployer");
    }

    function __assertVaultDeployed_singleFields(SharesDeployer.Deployed memory _d, Vm.Log[] memory _logs)
        internal
        view
    {
        assertEq(_d.feeHandler, __collectProxiesFromFactory(_logs, address(feeHandlerFactory))[0], "feeHandler");
        assertEq(
            _d.valuationHandler,
            __collectProxiesFromFactory(_logs, address(valuationHandlerFactory))[0],
            "valuationHandler"
        );
        assertEq(
            _d.managementFeeTracker,
            __collectProxiesFromFactory(_logs, address(managementFeeTrackerFactory))[0],
            "managementFeeTracker"
        );
        assertEq(
            _d.performanceFeeTracker,
            __collectProxiesFromFactory(_logs, address(performanceFeeTrackerFactory))[0],
            "performanceFeeTracker"
        );
        assertEq(
            _d.accountERC20Tracker,
            __collectProxiesFromFactory(_logs, address(accountERC20TrackerFactory))[0],
            "accountERC20Tracker"
        );
        assertEq(
            _d.linearCreditDebtTracker,
            __collectProxiesFromFactory(_logs, address(linearCreditDebtTrackerFactory))[0],
            "linearCreditDebtTracker"
        );
    }

    function __assertVaultDeployed_arrayFields(SharesDeployer.Deployed memory _d, Vm.Log[] memory _logs) internal view {
        address[] memory queues = __collectProxiesFromFactory(_logs, address(depositQueueFactory));
        assertEq(_d.queueDepositHandlers.length, queues.length, "queue count");
        assertEq(_d.queueDepositHandlers[0], queues[0], "queue addr");
        // fullConfig uses Restriction.None for the queue, so there's no external allowlist
        assertEq(_d.queueDepositHandlerAllowlists.length, 1, "queue allowlists len");
        assertEq(_d.queueDepositHandlerAllowlists[0], address(0), "queue allowlist is unset");

        address[] memory syncs = __collectProxiesFromFactory(_logs, address(syncDepositHandlerFactory));
        assertEq(_d.syncDepositHandlers.length, syncs.length, "sync count");
        assertEq(_d.syncDepositHandlers[0], syncs[0], "sync addr");
        assertEq(_d.syncDepositHandlerAllowlists.length, 1, "sync allowlists len");
        assertEq(_d.syncDepositHandlerAllowlists[0], depositorAllowlist, "sync allowlist (existing)");

        address[] memory redeems = __collectProxiesFromFactory(_logs, address(redeemQueueFactory));
        assertEq(_d.redeemHandlers.length, redeems.length, "redeem count");
        assertEq(_d.redeemHandlers[0], redeems[0], "redeem addr");

        address[] memory sharedLists = __collectProxiesFromFactory(_logs, address(sharesOwnedAddressListFactory));
        assertEq(_d.sharedAddressLists.length, sharedLists.length, "shared list count");
        assertEq(_d.sharedAddressLists[0], sharedLists[0], "shared list addr");
    }

    //==================================================================================================================
    // Minimal config
    //==================================================================================================================

    function test_deploy_minimalConfig_success() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();

        address sharesAddr = deployer.deploy(cfg);
        Shares shares = Shares(sharesAddr);

        assertEq(shares.getFeeHandler(), address(0));
        assertEq(shares.getValuationHandler(), address(0));
        assertEq(shares.getSharesTransferValidator(), address(0));
        assertEq(shares.pendingOwner(), vaultOwner);
        assertEq(shares.owner(), address(deployer));
    }

    //==================================================================================================================
    // Pre-mint
    //==================================================================================================================

    function test_deploy_preMint_distributesShares() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();

        ValuationHandler.AssetRateInput[] memory rates;
        cfg.components.valuationHandler = SharesDeployer.ValuationHandlerConfig({deploy: true, assetRates: rates});

        address user1 = makeAddr("preMintUser1");
        address user2 = makeAddr("preMintUser2");
        cfg.preMint = SharesDeployer.PreMintConfig({
            enabled: true,
            untrackedPositionsValue: int256(1000e18),
            recipients: new SharesDeployer.PreMintRecipient[](2)
        });
        cfg.preMint.recipients[0] = SharesDeployer.PreMintRecipient({to: user1, amount: 100e18});
        cfg.preMint.recipients[1] = SharesDeployer.PreMintRecipient({to: user2, amount: 50e18});

        Shares shares = Shares(deployer.deploy(cfg));

        assertEq(shares.balanceOf(user1), 100e18, "user1 balance");
        assertEq(shares.balanceOf(user2), 50e18, "user2 balance");
        assertEq(shares.balanceOf(address(deployer)), 0, "deployer holds none");
        assertEq(shares.totalSupply(), 150e18, "total supply");
        assertFalse(shares.isDepositHandler(address(deployer)), "deployer still deposit handler");

        // updateShareValue(untrackedPositionsValue) ran during pre-mint:
        //   netShareValue = SHARES_PRECISION * totalValue / totalShares
        //                 = 1e18 * 1000e18 / 150e18 = 6.666...e18
        (uint256 shareValue, uint256 shareValueTimestamp) = shares.shareValue();
        assertEq(shareValue, (1e18 * uint256(1000e18)) / 150e18, "share value");
        assertEq(shareValueTimestamp, block.timestamp, "share value timestamp");
    }

    //==================================================================================================================
    // Validation reverts
    //==================================================================================================================

    function test_deploy_revertsOn_zeroInitialOwner() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.initialOwner = address(0);

        vm.expectRevert(SharesDeployer.SharesDeployer__InitialOwnerCannotBeZero.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_zeroNominatedOwner() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.nominatedOwner = address(0);

        vm.expectRevert(SharesDeployer.SharesDeployer__NominatedOwnerCannotBeZero.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_managementFeeWithoutFeeHandler() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.managementFee =
            SharesDeployer.ManagementFeeConfig({deploy: true, feeBps: 100, recipient: feeRecipient});

        vm.expectRevert(SharesDeployer.SharesDeployer__ManagementFeeRequiresFeeHandler.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_performanceFeeWithoutFeeHandler() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.performanceFee = SharesDeployer.PerformanceFeeConfig({
            deploy: true, feeBps: 1000, hurdleRateBps: 0, recipient: feeRecipient
        });

        vm.expectRevert(SharesDeployer.SharesDeployer__PerformanceFeeRequiresFeeHandler.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_accountTrackerWithoutValuationHandler() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address[] memory assets = new address[](1);
        assets[0] = address(usdc);
        cfg.components.accountERC20Tracker = SharesDeployer.AccountERC20TrackerConfig({deploy: true, assets: assets});

        vm.expectRevert(SharesDeployer.SharesDeployer__AccountERC20TrackerRequiresValuationHandler.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_linearCreditDebtTrackerWithoutValuationHandler() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.linearCreditDebtTracker = SharesDeployer.LinearCreditDebtTrackerConfig({deploy: true});

        vm.expectRevert(SharesDeployer.SharesDeployer__LinearCreditDebtTrackerRequiresValuationHandler.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_preMintWithoutValuationHandler() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.preMint = SharesDeployer.PreMintConfig({
            enabled: true, untrackedPositionsValue: int256(0), recipients: new SharesDeployer.PreMintRecipient[](0)
        });

        vm.expectRevert(SharesDeployer.SharesDeployer__PreMintRequiresValuationHandler.selector);
        deployer.deploy(cfg);
    }

    //==================================================================================================================
    // Queue deposit handler restriction modes
    //==================================================================================================================

    function test_deploy_depositRestriction_none() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        cfg.components.queueDepositHandlers[0] =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.None);

        address[] memory deposits = __deployAndGetQueueDepositHandlers(cfg);
        ERC7540LikeDepositQueue q = ERC7540LikeDepositQueue(deposits[0]);
        assertEq(uint8(q.getDepositRestriction()), uint8(ERC7540LikeDepositQueue.DepositRestriction.None));
    }

    function test_deploy_depositRestriction_externalAllowlist_existing() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address external_ = makeAddr("preexistingList");
        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal);
        qc.externalListSource = SharesDeployer.ExternalListSource.Existing;
        qc.externalListExisting = external_;
        cfg.components.queueDepositHandlers[0] = qc;

        address[] memory deposits = __deployAndGetQueueDepositHandlers(cfg);
        ERC7540LikeDepositQueue q = ERC7540LikeDepositQueue(deposits[0]);
        assertEq(
            uint8(q.getDepositRestriction()),
            uint8(ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal)
        );
        assertEq(address(q.getDepositControllerExternalAllowlist()), external_, "external list addr");
    }

    function test_deploy_depositRestriction_internalAllowlist_seeded() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address[] memory seed = new address[](2);
        seed[0] = makeAddr("controllerA");
        seed[1] = makeAddr("controllerB");

        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal);
        qc.allowedDepositors = seed;
        cfg.components.queueDepositHandlers[0] = qc;

        address[] memory deposits = __deployAndGetQueueDepositHandlers(cfg);
        ERC7540LikeDepositQueue q = ERC7540LikeDepositQueue(deposits[0]);
        assertEq(
            uint8(q.getDepositRestriction()),
            uint8(ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal),
            "restriction"
        );
        assertTrue(q.isInDepositControllerInternalAllowlist(seed[0]), "seed A");
        assertTrue(q.isInDepositControllerInternalAllowlist(seed[1]), "seed B");
        assertFalse(q.isInDepositControllerInternalAllowlist(makeAddr("unrelated")), "unrelated stays out");
    }

    function test_deploy_depositRestriction_externalAllowlist_sharedSharesOwned_seeded() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address[] memory seed = new address[](1);
        seed[0] = makeAddr("controllerA");

        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.SharesOwned, ownableListOwner: address(0), seededAddresses: seed
        });

        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal);
        qc.externalListSource = SharesDeployer.ExternalListSource.SharedAddressList;
        qc.sharedAddressListIndex = 0;
        cfg.components.queueDepositHandlers[0] = qc;

        vm.recordLogs();
        deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory deposits = __collectProxiesFromFactory(logs, address(depositQueueFactory));
        address[] memory lists = __collectProxiesFromFactory(logs, address(sharesOwnedAddressListFactory));
        assertEq(lists.length, 1, "list deployed");

        ERC7540LikeDepositQueue q = ERC7540LikeDepositQueue(deposits[0]);
        assertEq(address(q.getDepositControllerExternalAllowlist()), lists[0], "queue points to shared list");
        assertTrue(IAddressList(lists[0]).isInList(seed[0]), "seeded");
    }

    function test_deploy_depositRestriction_externalAllowlist_sharedOwnable_seeded() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address listOwner = makeAddr("listOwner");
        address[] memory seed = new address[](1);
        seed[0] = makeAddr("controllerA");

        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.Ownable, ownableListOwner: listOwner, seededAddresses: seed
        });

        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal);
        qc.externalListSource = SharesDeployer.ExternalListSource.SharedAddressList;
        qc.sharedAddressListIndex = 0;
        cfg.components.queueDepositHandlers[0] = qc;

        vm.recordLogs();
        deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory deposits = __collectProxiesFromFactory(logs, address(depositQueueFactory));
        address[] memory lists = __collectBeaconProxies(logs, address(ownableAddressListFactory));
        assertEq(lists.length, 1, "list deployed");

        ERC7540LikeDepositQueue q = ERC7540LikeDepositQueue(deposits[0]);
        assertEq(address(q.getDepositControllerExternalAllowlist()), lists[0], "queue points to shared list");
        assertTrue(IAddressList(lists[0]).isInList(seed[0]), "seeded");
        assertEq(OwnableAddressList(lists[0]).owner(), listOwner, "ownership transferred");
    }

    //==================================================================================================================
    // Sync deposit handler allowlist
    //==================================================================================================================

    function test_deploy_syncDepositHandler_sharedSharesOwned_seeded() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address[] memory seed = new address[](2);
        seed[0] = makeAddr("depositorA");
        seed[1] = makeAddr("depositorB");

        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.SharesOwned, ownableListOwner: address(0), seededAddresses: seed
        });

        cfg.components.syncDepositHandlers = new SharesDeployer.SyncDepositHandlerConfig[](1);
        SharesDeployer.SyncDepositHandlerConfig memory sc = __syncCfg(address(usdc), 0);
        sc.depositorAllowlistSource = SharesDeployer.ExternalListSource.SharedAddressList;
        sc.sharedAddressListIndex = 0;
        cfg.components.syncDepositHandlers[0] = sc;

        vm.recordLogs();
        deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory syncs = __collectProxiesFromFactory(logs, address(syncDepositHandlerFactory));
        address[] memory lists = __collectProxiesFromFactory(logs, address(sharesOwnedAddressListFactory));
        assertEq(lists.length, 1, "list deployed");

        SyncDepositHandler sync = SyncDepositHandler(syncs[0]);
        assertEq(sync.getDepositorAllowlist(), lists[0], "sync points to shared list");
        assertTrue(IAddressList(lists[0]).isInList(seed[0]), "seed A");
        assertTrue(IAddressList(lists[0]).isInList(seed[1]), "seed B");
    }

    function test_deploy_syncDepositHandler_sharedOwnable_seeded() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address listOwner = makeAddr("listOwner");
        address[] memory seed = new address[](1);
        seed[0] = makeAddr("depositorA");

        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.Ownable, ownableListOwner: listOwner, seededAddresses: seed
        });

        cfg.components.syncDepositHandlers = new SharesDeployer.SyncDepositHandlerConfig[](1);
        SharesDeployer.SyncDepositHandlerConfig memory sc = __syncCfg(address(weth), 0);
        sc.depositorAllowlistSource = SharesDeployer.ExternalListSource.SharedAddressList;
        sc.sharedAddressListIndex = 0;
        cfg.components.syncDepositHandlers[0] = sc;

        vm.recordLogs();
        deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory syncs = __collectProxiesFromFactory(logs, address(syncDepositHandlerFactory));
        address[] memory lists = __collectBeaconProxies(logs, address(ownableAddressListFactory));
        assertEq(lists.length, 1, "list deployed");

        SyncDepositHandler sync = SyncDepositHandler(syncs[0]);
        assertEq(sync.getDepositorAllowlist(), lists[0], "sync points to shared list");
        assertTrue(IAddressList(lists[0]).isInList(seed[0]), "seeded");
        assertEq(OwnableAddressList(lists[0]).owner(), listOwner, "ownership transferred");
    }

    //==================================================================================================================
    // Allowlist config validation
    //==================================================================================================================

    function test_deploy_revertsOn_queueExternalSource_existingZeroAddress() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal);
        qc.externalListSource = SharesDeployer.ExternalListSource.Existing;
        cfg.components.queueDepositHandlers[0] = qc;

        vm.expectRevert(SharesDeployer.SharesDeployer__ExternalListExistingCannotBeZero.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_queueExternalRestriction_missingSource() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        cfg.components.queueDepositHandlers[0] =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal);

        vm.expectRevert(SharesDeployer.SharesDeployer__ExternalListSourceRequired.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_queueInternalRestriction_externalSourceSet() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal);
        qc.externalListSource = SharesDeployer.ExternalListSource.SharedAddressList;
        cfg.components.queueDepositHandlers[0] = qc;

        vm.expectRevert(SharesDeployer.SharesDeployer__ExternalListSourceNotAllowed.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_queueNoneRestriction_seedNotAllowed() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address[] memory seed = new address[](1);
        seed[0] = makeAddr("controllerA");
        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.None);
        qc.allowedDepositors = seed;
        cfg.components.queueDepositHandlers[0] = qc;

        vm.expectRevert(SharesDeployer.SharesDeployer__SeedNotAllowedWithoutAllowlist.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_queueNoneRestriction_externalSourceSet() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.None);
        qc.externalListSource = SharesDeployer.ExternalListSource.Existing;
        qc.externalListExisting = makeAddr("existing");
        cfg.components.queueDepositHandlers[0] = qc;

        vm.expectRevert(SharesDeployer.SharesDeployer__ExternalListSourceNotAllowed.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_queueExistingExternal_seedNotAllowed() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address[] memory seed = new address[](1);
        seed[0] = makeAddr("controllerA");
        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal);
        qc.externalListSource = SharesDeployer.ExternalListSource.Existing;
        qc.externalListExisting = makeAddr("existing");
        qc.allowedDepositors = seed;
        cfg.components.queueDepositHandlers[0] = qc;

        vm.expectRevert(SharesDeployer.SharesDeployer__SeedNotAllowedForExternalList.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_queueSharedExternal_seedNotAllowed() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();

        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.SharesOwned,
            ownableListOwner: address(0),
            seededAddresses: new address[](0)
        });

        address[] memory seed = new address[](1);
        seed[0] = makeAddr("controllerA");
        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal);
        qc.externalListSource = SharesDeployer.ExternalListSource.SharedAddressList;
        qc.sharedAddressListIndex = 0;
        qc.allowedDepositors = seed;
        cfg.components.queueDepositHandlers[0] = qc;

        vm.expectRevert(SharesDeployer.SharesDeployer__SeedNotAllowedForExternalList.selector);
        deployer.deploy(cfg);
    }

    //==================================================================================================================
    // Multiple handlers (queue + redeem)
    //==================================================================================================================

    function test_deploy_multipleDepositAndRedeemHandlers() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();

        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](2);
        cfg.components.queueDepositHandlers[0] =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.None);
        cfg.components.queueDepositHandlers[1] =
            __queueCfg(address(weth), 100, ERC7540LikeDepositQueue.DepositRestriction.None);

        cfg.components.redeemHandlers = new SharesDeployer.RedeemHandlerConfig[](2);
        cfg.components.redeemHandlers[0] =
            SharesDeployer.RedeemHandlerConfig({asset: address(usdc), minRequestDuration: 60});
        cfg.components.redeemHandlers[1] =
            SharesDeployer.RedeemHandlerConfig({asset: address(weth), minRequestDuration: 120});

        vm.recordLogs();
        Shares shares = Shares(deployer.deploy(cfg));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory deposits = __collectProxiesFromFactory(logs, address(depositQueueFactory));
        address[] memory redeems = __collectProxiesFromFactory(logs, address(redeemQueueFactory));

        assertEq(deposits.length, 2);
        assertEq(redeems.length, 2);

        assertEq(ERC7540LikeDepositQueue(deposits[0]).asset(), address(usdc), "deposit q0 asset");
        assertEq(ERC7540LikeDepositQueue(deposits[1]).asset(), address(weth), "deposit q1 asset");
        assertEq(ERC7540LikeDepositQueue(deposits[1]).getDepositMinRequestDuration(), 100, "deposit q1 duration");

        assertEq(ERC7540LikeRedeemQueue(redeems[0]).asset(), address(usdc), "redeem q0 asset");
        assertEq(ERC7540LikeRedeemQueue(redeems[1]).asset(), address(weth), "redeem q1 asset");
        assertEq(ERC7540LikeRedeemQueue(redeems[0]).getRedeemMinRequestDuration(), 60, "redeem q0 duration");
        assertEq(ERC7540LikeRedeemQueue(redeems[1]).getRedeemMinRequestDuration(), 120, "redeem q1 duration");

        assertTrue(shares.isDepositHandler(deposits[0]), "deposit handler 0 registered");
        assertTrue(shares.isDepositHandler(deposits[1]), "deposit handler 1 registered");
        assertTrue(shares.isRedeemHandler(redeems[0]), "redeem handler 0 registered");
        assertTrue(shares.isRedeemHandler(redeems[1]), "redeem handler 1 registered");
    }

    //==================================================================================================================
    // SyncDepositHandler
    //==================================================================================================================

    function test_deploy_syncDepositHandler_minimal() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.syncDepositHandlers = new SharesDeployer.SyncDepositHandlerConfig[](1);
        cfg.components.syncDepositHandlers[0] = __syncCfg(address(usdc), 0);

        vm.recordLogs();
        Shares shares = Shares(deployer.deploy(cfg));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory syncs = __collectProxiesFromFactory(logs, address(syncDepositHandlerFactory));
        assertEq(syncs.length, 1);
        SyncDepositHandler sync = SyncDepositHandler(syncs[0]);
        assertEq(sync.getAsset(), address(usdc), "asset");
        assertEq(sync.getDepositorAllowlist(), address(0), "allowlist default");
        assertEq(sync.getMaxSharePriceStaleness(), 0, "staleness default");
        assertTrue(shares.isDepositHandler(syncs[0]), "registered on Shares");
    }

    function test_deploy_syncDepositHandler_withOptions() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.syncDepositHandlers = new SharesDeployer.SyncDepositHandlerConfig[](1);
        SharesDeployer.SyncDepositHandlerConfig memory sc = __syncCfg(address(weth), 1234);
        sc.depositorAllowlistSource = SharesDeployer.ExternalListSource.Existing;
        sc.depositorAllowlistExisting = depositorAllowlist;
        cfg.components.syncDepositHandlers[0] = sc;

        vm.recordLogs();
        deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory syncs = __collectProxiesFromFactory(logs, address(syncDepositHandlerFactory));
        SyncDepositHandler sync = SyncDepositHandler(syncs[0]);
        assertEq(sync.getAsset(), address(weth), "asset");
        assertEq(sync.getDepositorAllowlist(), depositorAllowlist, "allowlist");
        assertEq(sync.getMaxSharePriceStaleness(), 1234, "staleness");
    }

    function test_deploy_multipleSyncDepositHandlers() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.components.syncDepositHandlers = new SharesDeployer.SyncDepositHandlerConfig[](2);
        cfg.components.syncDepositHandlers[0] = __syncCfg(address(usdc), 0);
        SharesDeployer.SyncDepositHandlerConfig memory sc1 = __syncCfg(address(weth), 600);
        sc1.depositorAllowlistSource = SharesDeployer.ExternalListSource.Existing;
        sc1.depositorAllowlistExisting = depositorAllowlist;
        cfg.components.syncDepositHandlers[1] = sc1;

        vm.recordLogs();
        Shares shares = Shares(deployer.deploy(cfg));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory syncs = __collectProxiesFromFactory(logs, address(syncDepositHandlerFactory));
        assertEq(syncs.length, 2);
        assertEq(SyncDepositHandler(syncs[0]).getAsset(), address(usdc), "sync0 asset");
        assertEq(SyncDepositHandler(syncs[1]).getAsset(), address(weth), "sync1 asset");
        assertEq(SyncDepositHandler(syncs[1]).getDepositorAllowlist(), depositorAllowlist, "sync1 allowlist");
        assertEq(SyncDepositHandler(syncs[1]).getMaxSharePriceStaleness(), 600, "sync1 staleness");
        assertTrue(shares.isDepositHandler(syncs[0]), "sync0 registered");
        assertTrue(shares.isDepositHandler(syncs[1]), "sync1 registered");
    }

    //==================================================================================================================
    // TransferValidator
    //==================================================================================================================

    function test_deploy_transferValidator_existing() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.transferValidator = SharesDeployer.TransferValidatorConfig({
            source: SharesDeployer.TransferValidatorSource.Existing,
            existing: validator,
            recipientList: __validatorListNone(),
            senderList: __validatorListNone()
        });

        Shares shares = Shares(deployer.deploy(cfg));
        assertEq(shares.getSharesTransferValidator(), validator);
    }

    function test_deploy_transferValidator_none() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        // Default cfg has source = None; verify validator stays unset.
        Shares shares = Shares(deployer.deploy(cfg));
        assertEq(shares.getSharesTransferValidator(), address(0));
    }

    function test_deploy_transferValidator_deployAddressLists_recipientAllow_sharedSharesOwned_seeded() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address[] memory seed = new address[](2);
        seed[0] = makeAddr("allowedRecipientA");
        seed[1] = makeAddr("allowedRecipientB");

        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.SharesOwned, ownableListOwner: address(0), seededAddresses: seed
        });

        cfg.transferValidator = SharesDeployer.TransferValidatorConfig({
            source: SharesDeployer.TransferValidatorSource.DeployAddressLists,
            existing: address(0),
            recipientList: SharesDeployer.AddressListsValidatorListConfig({
                listType: AddressListsSharesTransferValidator.ListType.Allow,
                externalListSource: SharesDeployer.ExternalListSource.SharedAddressList,
                externalListExisting: address(0),
                sharedAddressListIndex: 0
            }),
            senderList: __validatorListNone()
        });

        vm.recordLogs();
        Shares shares = Shares(deployer.deploy(cfg));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory validators =
            __collectProxiesFromFactory(logs, address(addressListsSharesTransferValidatorFactory));
        address[] memory lists = __collectProxiesFromFactory(logs, address(sharesOwnedAddressListFactory));
        assertEq(validators.length, 1, "validator deployed");
        assertEq(lists.length, 1, "recipient list deployed");

        AddressListsSharesTransferValidator deployedValidator = AddressListsSharesTransferValidator(validators[0]);
        assertEq(shares.getSharesTransferValidator(), validators[0], "wired on shares");
        assertEq(deployedValidator.getRecipientList(), lists[0], "recipient list addr");
        assertEq(
            uint8(deployedValidator.getRecipientListType()),
            uint8(AddressListsSharesTransferValidator.ListType.Allow),
            "recipient list type"
        );
        assertEq(deployedValidator.getSenderList(), address(0), "sender list addr");
        assertTrue(IAddressList(lists[0]).isInList(seed[0]), "seed A");
        assertTrue(IAddressList(lists[0]).isInList(seed[1]), "seed B");
    }

    function test_deploy_transferValidator_deployAddressLists_bothLists_existingAndSharedOwnable() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address recipientExisting = makeAddr("recipientListExisting");
        address senderListOwner = makeAddr("senderListOwner");
        address[] memory senderSeed = new address[](1);
        senderSeed[0] = makeAddr("blockedSender");

        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.Ownable,
            ownableListOwner: senderListOwner,
            seededAddresses: senderSeed
        });

        cfg.transferValidator = SharesDeployer.TransferValidatorConfig({
            source: SharesDeployer.TransferValidatorSource.DeployAddressLists,
            existing: address(0),
            recipientList: SharesDeployer.AddressListsValidatorListConfig({
                listType: AddressListsSharesTransferValidator.ListType.Allow,
                externalListSource: SharesDeployer.ExternalListSource.Existing,
                externalListExisting: recipientExisting,
                sharedAddressListIndex: 0
            }),
            senderList: SharesDeployer.AddressListsValidatorListConfig({
                listType: AddressListsSharesTransferValidator.ListType.Disallow,
                externalListSource: SharesDeployer.ExternalListSource.SharedAddressList,
                externalListExisting: address(0),
                sharedAddressListIndex: 0
            })
        });

        vm.recordLogs();
        deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory validators =
            __collectProxiesFromFactory(logs, address(addressListsSharesTransferValidatorFactory));
        address[] memory ownables = __collectBeaconProxies(logs, address(ownableAddressListFactory));
        assertEq(validators.length, 1, "validator deployed");
        assertEq(ownables.length, 1, "sender ownable list deployed");

        AddressListsSharesTransferValidator deployedValidator = AddressListsSharesTransferValidator(validators[0]);
        assertEq(deployedValidator.getRecipientList(), recipientExisting, "recipient = existing");
        assertEq(deployedValidator.getSenderList(), ownables[0], "sender = shared ownable");
        assertEq(
            uint8(deployedValidator.getSenderListType()),
            uint8(AddressListsSharesTransferValidator.ListType.Disallow),
            "sender type"
        );
        assertTrue(IAddressList(ownables[0]).isInList(senderSeed[0]), "sender seed");
        assertEq(OwnableAddressList(ownables[0]).owner(), senderListOwner, "sender list ownership");
    }

    function test_deploy_transferValidator_deployAddressLists_bothLists_sharedRecipientAndSender() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address ownableListOwner = makeAddr("senderListOwner");

        address[] memory recipSeed = new address[](2);
        recipSeed[0] = makeAddr("allowedRecipientA");
        recipSeed[1] = makeAddr("allowedRecipientB");
        address[] memory senderSeed = new address[](1);
        senderSeed[0] = makeAddr("blockedSender");

        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](2);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.SharesOwned,
            ownableListOwner: address(0),
            seededAddresses: recipSeed
        });
        cfg.sharedAddressLists[1] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.Ownable,
            ownableListOwner: ownableListOwner,
            seededAddresses: senderSeed
        });

        cfg.transferValidator = SharesDeployer.TransferValidatorConfig({
            source: SharesDeployer.TransferValidatorSource.DeployAddressLists,
            existing: address(0),
            recipientList: SharesDeployer.AddressListsValidatorListConfig({
                listType: AddressListsSharesTransferValidator.ListType.Allow,
                externalListSource: SharesDeployer.ExternalListSource.SharedAddressList,
                externalListExisting: address(0),
                sharedAddressListIndex: 0
            }),
            senderList: SharesDeployer.AddressListsValidatorListConfig({
                listType: AddressListsSharesTransferValidator.ListType.Disallow,
                externalListSource: SharesDeployer.ExternalListSource.SharedAddressList,
                externalListExisting: address(0),
                sharedAddressListIndex: 1
            })
        });

        vm.recordLogs();
        Shares shares = Shares(deployer.deploy(cfg));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory validators =
            __collectProxiesFromFactory(logs, address(addressListsSharesTransferValidatorFactory));
        address[] memory sharesOwnedLists = __collectProxiesFromFactory(logs, address(sharesOwnedAddressListFactory));
        address[] memory ownableLists = __collectBeaconProxies(logs, address(ownableAddressListFactory));
        assertEq(validators.length, 1, "validator deployed");
        assertEq(sharesOwnedLists.length, 1, "recipient list deployed");
        assertEq(ownableLists.length, 1, "sender list deployed");

        AddressListsSharesTransferValidator v = AddressListsSharesTransferValidator(validators[0]);
        assertEq(v.getRecipientList(), sharesOwnedLists[0], "recipient = SharesOwned shared list");
        assertEq(v.getSenderList(), ownableLists[0], "sender = Ownable shared list");
        assertEq(
            uint8(v.getRecipientListType()),
            uint8(AddressListsSharesTransferValidator.ListType.Allow),
            "recipient list type Allow"
        );
        assertEq(
            uint8(v.getSenderListType()),
            uint8(AddressListsSharesTransferValidator.ListType.Disallow),
            "sender list type Disallow"
        );
        assertTrue(IAddressList(sharesOwnedLists[0]).isInList(recipSeed[0]), "recipient seed A");
        assertTrue(IAddressList(sharesOwnedLists[0]).isInList(recipSeed[1]), "recipient seed B");
        assertTrue(IAddressList(ownableLists[0]).isInList(senderSeed[0]), "sender seed");
        assertEq(OwnableAddressList(ownableLists[0]).owner(), ownableListOwner, "sender list owner");
        assertEq(shares.getSharesTransferValidator(), validators[0], "wired on shares");
    }

    function test_deploy_revertsOn_transferValidator_existingZero() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.transferValidator = SharesDeployer.TransferValidatorConfig({
            source: SharesDeployer.TransferValidatorSource.Existing,
            existing: address(0),
            recipientList: __validatorListNone(),
            senderList: __validatorListNone()
        });

        vm.expectRevert(SharesDeployer.SharesDeployer__TransferValidatorExistingCannotBeZero.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_transferValidator_listTypeAllow_missingSource() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.transferValidator = SharesDeployer.TransferValidatorConfig({
            source: SharesDeployer.TransferValidatorSource.DeployAddressLists,
            existing: address(0),
            recipientList: SharesDeployer.AddressListsValidatorListConfig({
                listType: AddressListsSharesTransferValidator.ListType.Allow,
                externalListSource: SharesDeployer.ExternalListSource.None,
                externalListExisting: address(0),
                sharedAddressListIndex: 0
            }),
            senderList: __validatorListNone()
        });

        vm.expectRevert(SharesDeployer.SharesDeployer__ExternalListSourceRequired.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_transferValidator_listTypeNone_externalSourceSet() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.transferValidator = SharesDeployer.TransferValidatorConfig({
            source: SharesDeployer.TransferValidatorSource.DeployAddressLists,
            existing: address(0),
            recipientList: SharesDeployer.AddressListsValidatorListConfig({
                listType: AddressListsSharesTransferValidator.ListType.None,
                externalListSource: SharesDeployer.ExternalListSource.Existing,
                externalListExisting: makeAddr("existing"),
                sharedAddressListIndex: 0
            }),
            senderList: __validatorListNone()
        });

        vm.expectRevert(SharesDeployer.SharesDeployer__ExternalListSourceNotAllowed.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_sharedAddressList_reusedBySyncAndTransferValidator() public {
        address listOwner = makeAddr("sharedCatalogListOwner");
        address seeded = makeAddr("sharedCatalogSeeded");

        SharesDeployer.DeployConfig memory cfg = __minimalConfig();

        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        address[] memory seed = new address[](1);
        seed[0] = seeded;
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.Ownable, ownableListOwner: listOwner, seededAddresses: seed
        });

        cfg.components.syncDepositHandlers = new SharesDeployer.SyncDepositHandlerConfig[](1);
        cfg.components.syncDepositHandlers[0] = SharesDeployer.SyncDepositHandlerConfig({
            asset: address(usdc),
            maxSharePriceStaleness: 0,
            depositorAllowlistSource: SharesDeployer.ExternalListSource.SharedAddressList,
            depositorAllowlistExisting: address(0),
            sharedAddressListIndex: 0
        });

        cfg.transferValidator = SharesDeployer.TransferValidatorConfig({
            source: SharesDeployer.TransferValidatorSource.DeployAddressLists,
            existing: address(0),
            recipientList: SharesDeployer.AddressListsValidatorListConfig({
                listType: AddressListsSharesTransferValidator.ListType.Allow,
                externalListSource: SharesDeployer.ExternalListSource.SharedAddressList,
                externalListExisting: address(0),
                sharedAddressListIndex: 0
            }),
            senderList: __validatorListNone()
        });

        vm.recordLogs();
        address sharesAddr = deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Shares shares = Shares(sharesAddr);

        address[] memory syncs = __collectProxiesFromFactory(logs, address(syncDepositHandlerFactory));
        address[] memory validators =
            __collectProxiesFromFactory(logs, address(addressListsSharesTransferValidatorFactory));
        assertEq(syncs.length, 1, "sync count");
        assertEq(validators.length, 1, "validator count");

        SyncDepositHandler sync = SyncDepositHandler(syncs[0]);
        AddressListsSharesTransferValidator v = AddressListsSharesTransferValidator(validators[0]);

        address syncList = sync.getDepositorAllowlist();
        address recipientList = v.getRecipientList();
        assertEq(syncList, recipientList, "same shared list instance");
        assertTrue(IAddressList(syncList).isInList(seeded), "seed on shared list");
        assertEq(OwnableAddressList(syncList).owner(), listOwner, "final list owner");
        assertEq(shares.getSharesTransferValidator(), validators[0], "validator wired");
    }

    function test_deploy_revertsOn_sharedAddressListIndexOutOfBounds() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.SharesOwned,
            ownableListOwner: address(0),
            seededAddresses: new address[](0)
        });
        cfg.components.syncDepositHandlers = new SharesDeployer.SyncDepositHandlerConfig[](1);
        cfg.components.syncDepositHandlers[0] = SharesDeployer.SyncDepositHandlerConfig({
            asset: address(usdc),
            maxSharePriceStaleness: 0,
            depositorAllowlistSource: SharesDeployer.ExternalListSource.SharedAddressList,
            depositorAllowlistExisting: address(0),
            sharedAddressListIndex: 1
        });

        vm.expectRevert(SharesDeployer.SharesDeployer__SharedAddressListIndexOutOfBounds.selector);
        deployer.deploy(cfg);
    }

    function test_deploy_revertsOn_sharedAddressList_ownableOwnerZero() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address[] memory seed = new address[](1);
        seed[0] = makeAddr("wouldBeSeeded");

        // Seed is non-empty to ensure the test would fail loudly if seeding ran before validation.
        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](1);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.Ownable, ownableListOwner: address(0), seededAddresses: seed
        });

        vm.recordLogs();
        vm.expectRevert(SharesDeployer.SharesDeployer__OwnableAddressListOwnerCannotBeZero.selector);
        deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Validation runs before any factory call; no proxies should be deployed
        address[] memory sharesProxies = __collectBeaconProxies(logs, address(sharesFactory));
        address[] memory sharesOwnedLists = __collectProxiesFromFactory(logs, address(sharesOwnedAddressListFactory));
        address[] memory ownableLists = __collectBeaconProxies(logs, address(ownableAddressListFactory));
        assertEq(sharesProxies.length, 0, "no shares deployed before validation revert");
        assertEq(sharesOwnedLists.length, 0, "no SharesOwned lists deployed before validation revert");
        assertEq(ownableLists.length, 0, "no Ownable lists deployed before validation revert");
    }

    function test_deploy_sharedAddressList_orphan_deployedAndSeededWithoutConsumer() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address ownableListOwner = makeAddr("orphanOwnableOwner");
        address[] memory seed = new address[](1);
        seed[0] = makeAddr("orphanedSeed");

        // Two shared lists declared, but neither is referenced by any consumer
        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](2);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.SharesOwned, ownableListOwner: address(0), seededAddresses: seed
        });
        cfg.sharedAddressLists[1] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.Ownable,
            ownableListOwner: ownableListOwner,
            seededAddresses: seed
        });

        vm.recordLogs();
        deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory sharesOwnedLists = __collectProxiesFromFactory(logs, address(sharesOwnedAddressListFactory));
        address[] memory ownableLists = __collectBeaconProxies(logs, address(ownableAddressListFactory));
        assertEq(sharesOwnedLists.length, 1, "orphan SharesOwned list deployed");
        assertEq(ownableLists.length, 1, "orphan Ownable list deployed");

        assertTrue(IAddressList(sharesOwnedLists[0]).isInList(seed[0]), "orphan SharesOwned seeded");
        assertTrue(IAddressList(ownableLists[0]).isInList(seed[0]), "orphan Ownable seeded");
        assertEq(OwnableAddressList(ownableLists[0]).owner(), ownableListOwner, "orphan Ownable owner");
    }

    function test_deploy_sharedAddressList_multipleConsumersDifferentIndices() public {
        SharesDeployer.DeployConfig memory cfg = __minimalConfig();
        address ownableListOwner = makeAddr("ownableListOwner");
        address[] memory sharesOwnedSeed = new address[](1);
        sharesOwnedSeed[0] = makeAddr("queueDepositor");
        address[] memory ownableSeed = new address[](1);
        ownableSeed[0] = makeAddr("syncDepositor");

        cfg.sharedAddressLists = new SharesDeployer.SharedAddressListDefinition[](2);
        cfg.sharedAddressLists[0] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.SharesOwned,
            ownableListOwner: address(0),
            seededAddresses: sharesOwnedSeed
        });
        cfg.sharedAddressLists[1] = SharesDeployer.SharedAddressListDefinition({
            kind: SharesDeployer.SharedAddressListKind.Ownable,
            ownableListOwner: ownableListOwner,
            seededAddresses: ownableSeed
        });

        cfg.components.queueDepositHandlers = new SharesDeployer.QueueDepositHandlerConfig[](1);
        SharesDeployer.QueueDepositHandlerConfig memory qc =
            __queueCfg(address(usdc), 0, ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal);
        qc.externalListSource = SharesDeployer.ExternalListSource.SharedAddressList;
        qc.sharedAddressListIndex = 0;
        cfg.components.queueDepositHandlers[0] = qc;

        cfg.components.syncDepositHandlers = new SharesDeployer.SyncDepositHandlerConfig[](1);
        SharesDeployer.SyncDepositHandlerConfig memory sc = __syncCfg(address(usdc), 0);
        sc.depositorAllowlistSource = SharesDeployer.ExternalListSource.SharedAddressList;
        sc.sharedAddressListIndex = 1;
        cfg.components.syncDepositHandlers[0] = sc;

        vm.recordLogs();
        deployer.deploy(cfg);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory sharesOwnedLists = __collectProxiesFromFactory(logs, address(sharesOwnedAddressListFactory));
        address[] memory ownableLists = __collectBeaconProxies(logs, address(ownableAddressListFactory));
        address[] memory queues = __collectProxiesFromFactory(logs, address(depositQueueFactory));
        address[] memory syncs = __collectProxiesFromFactory(logs, address(syncDepositHandlerFactory));

        assertEq(sharesOwnedLists.length, 1, "SharesOwned list count");
        assertEq(ownableLists.length, 1, "Ownable list count");

        // Queue handler points at the SharesOwned list (index 0)
        assertEq(
            address(ERC7540LikeDepositQueue(queues[0]).getDepositControllerExternalAllowlist()),
            sharesOwnedLists[0],
            "queue allowlist"
        );
        assertTrue(IAddressList(sharesOwnedLists[0]).isInList(sharesOwnedSeed[0]), "SharesOwned seed");

        // Sync handler points at the Ownable list (index 1)
        assertEq(SyncDepositHandler(syncs[0]).getDepositorAllowlist(), ownableLists[0], "sync allowlist");
        assertTrue(IAddressList(ownableLists[0]).isInList(ownableSeed[0]), "Ownable seed");
        assertEq(OwnableAddressList(ownableLists[0]).owner(), ownableListOwner, "ownable list owner");
    }

    //==================================================================================================================
    // Helpers
    //==================================================================================================================

    function __queueCfg(address _asset, uint24 _minDuration, ERC7540LikeDepositQueue.DepositRestriction _restriction)
        internal
        pure
        returns (SharesDeployer.QueueDepositHandlerConfig memory cfg_)
    {
        cfg_ = SharesDeployer.QueueDepositHandlerConfig({
            asset: _asset,
            minRequestDuration: _minDuration,
            restriction: _restriction,
            externalListSource: SharesDeployer.ExternalListSource.None,
            externalListExisting: address(0),
            sharedAddressListIndex: 0,
            allowedDepositors: new address[](0)
        });
    }

    function __syncCfg(address _asset, uint24 _maxStaleness)
        internal
        pure
        returns (SharesDeployer.SyncDepositHandlerConfig memory cfg_)
    {
        cfg_ = SharesDeployer.SyncDepositHandlerConfig({
            asset: _asset,
            maxSharePriceStaleness: _maxStaleness,
            depositorAllowlistSource: SharesDeployer.ExternalListSource.None,
            depositorAllowlistExisting: address(0),
            sharedAddressListIndex: 0
        });
    }

    function __validatorListNone() internal pure returns (SharesDeployer.AddressListsValidatorListConfig memory) {
        return SharesDeployer.AddressListsValidatorListConfig({
            listType: AddressListsSharesTransferValidator.ListType.None,
            externalListSource: SharesDeployer.ExternalListSource.None,
            externalListExisting: address(0),
            sharedAddressListIndex: 0
        });
    }

    /// @dev Records logs around a deploy call, returns queue-deposit-handler addresses captured from the
    /// `ProxyDeployed` events emitted by the deposit-queue factory during that call.
    function __deployAndGetQueueDepositHandlers(SharesDeployer.DeployConfig memory _cfg)
        internal
        returns (address[] memory deposits_)
    {
        vm.recordLogs();
        deployer.deploy(_cfg);
        return __collectProxiesFromFactory(vm.getRecordedLogs(), address(depositQueueFactory));
    }

    /// @dev `ComponentBeaconFactory.ProxyDeployed(address proxy, address shares)` — both unindexed,
    /// so `proxy` is the first 32 bytes of `data`.
    function __collectProxiesFromFactory(Vm.Log[] memory _logs, address _factory)
        internal
        pure
        returns (address[] memory proxies_)
    {
        bytes32 sig = keccak256("ProxyDeployed(address,address)");

        uint256 count;
        for (uint256 i; i < _logs.length; i++) {
            if (_logs[i].emitter == _factory && _logs[i].topics.length > 0 && _logs[i].topics[0] == sig) {
                count++;
            }
        }

        proxies_ = new address[](count);
        uint256 j;
        for (uint256 i; i < _logs.length; i++) {
            if (_logs[i].emitter == _factory && _logs[i].topics.length > 0 && _logs[i].topics[0] == sig) {
                (address proxy,) = abi.decode(_logs[i].data, (address, address));
                proxies_[j++] = proxy;
            }
        }
    }

    /// @dev `BeaconFactory.ProxyDeployed(address proxy)` — single unindexed arg.
    function __collectBeaconProxies(Vm.Log[] memory _logs, address _factory)
        internal
        pure
        returns (address[] memory proxies_)
    {
        bytes32 sig = keccak256("ProxyDeployed(address)");

        uint256 count;
        for (uint256 i; i < _logs.length; i++) {
            if (_logs[i].emitter == _factory && _logs[i].topics.length > 0 && _logs[i].topics[0] == sig) {
                count++;
            }
        }

        proxies_ = new address[](count);
        uint256 j;
        for (uint256 i; i < _logs.length; i++) {
            if (_logs[i].emitter == _factory && _logs[i].topics.length > 0 && _logs[i].topics[0] == sig) {
                address proxy = abi.decode(_logs[i].data, (address));
                proxies_[j++] = proxy;
            }
        }
    }
}
