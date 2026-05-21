// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
import {
    AddressListsSharesTransferValidator
} from "src/components/shares-transfer-validators/AddressListsSharesTransferValidator.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {AccountERC20Tracker} from "src/components/value/position-trackers/AccountERC20Tracker.sol";
import {AddressListBase} from "src/infra/lists/address-list/AddressListBase.sol";
import {OwnableAddressList} from "src/infra/lists/address-list/OwnableAddressList.sol";
import {Shares} from "src/shares/Shares.sol";

/// @title SharesDeployer Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Single-transaction deployment of a fully-configured Onyx vault (Shares + components)
/// @dev Stateless after construction; safe to call permissionlessly.
/// `Shares` is initialized with this contract as owner while components are wired. After wiring,
/// `transferOwnership(config.nominatedOwner)` runs (Ownable2Step pending). The nominee must call `Shares.acceptOwnership()` to complete the handover.
contract SharesDeployer {
    using SafeERC20 for IERC20;

    //==================================================================================================================
    // Types
    //==================================================================================================================

    struct Factories {
        address sharesFactory;
        address feeHandlerFactory;
        address valuationHandlerFactory;
        address managementFeeTrackerFactory;
        address performanceFeeTrackerFactory;
        address accountERC20TrackerFactory;
        address linearCreditDebtTrackerFactory;
        address depositQueueFactory;
        address syncDepositHandlerFactory;
        address redeemQueueFactory;
        address sharesOwnedAddressListFactory;
        address ownableAddressListFactory;
        address addressListsSharesTransferValidatorFactory;
    }

    /// @dev How the shares transfer validator should be sourced.
    /// `None`: no transfer validator.
    /// `Existing`: use the address provided in the config.
    /// `DeployAddressLists`: deploy a fresh `AddressListsSharesTransferValidator` and configure its lists.
    enum TransferValidatorSource {
        None,
        Existing,
        DeployAddressLists
    }

    /// @dev How an external address list should be sourced when restriction/source so requires.
    /// `None`: no external list.
    /// `Existing`: use the address provided in the config.
    /// `SharedAddressList`: use a list from `DeployConfig.sharedAddressLists` at `sharedAddressListIndex`.
    enum ExternalListSource {
        None,
        Existing,
        SharedAddressList
    }

    /// @dev Kind of list deployed for a catalog entry in `DeployConfig.sharedAddressLists`.
    enum SharedAddressListKind {
        SharesOwned,
        Ownable
    }

    /// @dev One list to deploy once; referenced by consumers via `ExternalListSource.SharedAddressList`.
    struct SharedAddressListDefinition {
        SharedAddressListKind kind;
        /// @dev Required when `kind == Ownable`; ignored for `SharesOwned`.
        address ownableListOwner;
        address[] seededAddresses;
    }

    struct SharesConfig {
        string name;
        string symbol;
        bytes32 valueAsset;
    }

    struct FeeHandlerConfig {
        bool deploy;
        address feeAsset;
        uint16 entranceFeeBps;
        address entranceFeeRecipient;
        uint16 exitFeeBps;
        address exitFeeRecipient;
    }

    struct ManagementFeeConfig {
        bool deploy;
        uint16 feeBps;
        address recipient;
    }

    struct PerformanceFeeConfig {
        bool deploy;
        uint16 feeBps;
        int16 hurdleRateBps;
        address recipient;
    }

    struct ValuationHandlerConfig {
        bool deploy;
        ValuationHandler.AssetRateInput[] assetRates;
    }

    struct AccountERC20TrackerConfig {
        bool deploy;
        address[] assets;
    }

    struct LinearCreditDebtTrackerConfig {
        bool deploy;
    }

    struct QueueDepositHandlerConfig {
        address asset;
        uint24 minRequestDuration;
        ERC7540LikeDepositQueue.DepositRestriction restriction;
        ExternalListSource externalListSource;
        address externalListExisting;
        /// @dev Used when `externalListSource == SharedAddressList`; must be `< sharedAddressLists.length`.
        uint256 sharedAddressListIndex;
        /// @dev Seed addresses for `ControllerAllowlistInternal`; must be empty for other restrictions.
        address[] allowedDepositors;
    }

    struct SyncDepositHandlerConfig {
        address asset;
        uint24 maxSharePriceStaleness;
        ExternalListSource depositorAllowlistSource;
        address depositorAllowlistExisting;
        /// @dev Used when `depositorAllowlistSource == SharedAddressList`.
        uint256 sharedAddressListIndex;
    }

    struct RedeemHandlerConfig {
        address asset;
        uint24 minRequestDuration;
    }

    struct AddressListsValidatorListConfig {
        AddressListsSharesTransferValidator.ListType listType;
        ExternalListSource externalListSource;
        address externalListExisting;
        /// @dev Used when `externalListSource == SharedAddressList`.
        uint256 sharedAddressListIndex;
    }

    struct TransferValidatorConfig {
        TransferValidatorSource source;
        address existing;
        AddressListsValidatorListConfig recipientList;
        AddressListsValidatorListConfig senderList;
    }

    struct PreMintRecipient {
        address to;
        uint256 amount;
    }

    struct PreMintConfig {
        bool enabled;
        int256 untrackedPositionsValue;
        PreMintRecipient[] recipients;
    }

    struct ComponentsConfig {
        FeeHandlerConfig feeHandler;
        ManagementFeeConfig managementFee;
        PerformanceFeeConfig performanceFee;
        ValuationHandlerConfig valuationHandler;
        AccountERC20TrackerConfig accountERC20Tracker;
        LinearCreditDebtTrackerConfig linearCreditDebtTracker;
        QueueDepositHandlerConfig[] queueDepositHandlers;
        SyncDepositHandlerConfig[] syncDepositHandlers;
        RedeemHandlerConfig[] redeemHandlers;
    }

    struct DeployConfig {
        SharesConfig shares;
        /// @dev Pending owner after deploy (`transferOwnership`; nominee calls `acceptOwnership()`)
        address nominatedOwner;
        address[] admins;
        TransferValidatorConfig transferValidator;
        ComponentsConfig components;
        PreMintConfig preMint;
        /// @dev Lists deployed once before handlers; consumers use `ExternalListSource.SharedAddressList` + index.
        SharedAddressListDefinition[] sharedAddressLists;
    }

    struct Deployed {
        address shares;
        address feeHandler;
        address valuationHandler;
        address managementFeeTracker;
        address performanceFeeTracker;
        address accountERC20Tracker;
        address linearCreditDebtTracker;
        address[] queueDepositHandlers;
        address[] queueDepositHandlerAllowlists;
        address[] syncDepositHandlers;
        address[] syncDepositHandlerAllowlists;
        address[] redeemHandlers;
        address transferValidator;
        address transferValidatorRecipientList;
        address transferValidatorSenderList;
        /// @dev Addresses of `sharedAddressLists` entries in deployment order.
        address[] sharedAddressLists;
    }

    //==================================================================================================================
    // Immutables
    //==================================================================================================================

    address public immutable SHARES_FACTORY;
    address public immutable FEE_HANDLER_FACTORY;
    address public immutable VALUATION_HANDLER_FACTORY;
    address public immutable MANAGEMENT_FEE_TRACKER_FACTORY;
    address public immutable PERFORMANCE_FEE_TRACKER_FACTORY;
    address public immutable ACCOUNT_ERC20_TRACKER_FACTORY;
    address public immutable LINEAR_CREDIT_DEBT_TRACKER_FACTORY;
    address public immutable DEPOSIT_QUEUE_FACTORY;
    address public immutable SYNC_DEPOSIT_HANDLER_FACTORY;
    address public immutable REDEEM_QUEUE_FACTORY;
    address public immutable SHARES_OWNED_ADDRESS_LIST_FACTORY;
    address public immutable OWNABLE_ADDRESS_LIST_FACTORY;
    address public immutable ADDRESS_LISTS_SHARES_TRANSFER_VALIDATOR_FACTORY;

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event VaultDeployed(Deployed deployed, address nominatedOwner);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error SharesDeployer__NominatedOwnerCannotBeZero();
    error SharesDeployer__NominatedOwnerCannotBeDeployer();
    error SharesDeployer__ManagementFeeRequiresFeeHandler();
    error SharesDeployer__PerformanceFeeRequiresFeeHandler();
    error SharesDeployer__AccountERC20TrackerRequiresValuationHandler();
    error SharesDeployer__LinearCreditDebtTrackerRequiresValuationHandler();
    error SharesDeployer__PreMintRequiresValuationHandler();
    error SharesDeployer__ExternalListSourceRequired();
    error SharesDeployer__ExternalListSourceNotAllowed();
    error SharesDeployer__ExternalListExistingCannotBeZero();
    error SharesDeployer__OwnableAddressListOwnerCannotBeZero();
    error SharesDeployer__SeedNotAllowedForExternalList();
    error SharesDeployer__SeedNotAllowedWithoutAllowlist();
    error SharesDeployer__TransferValidatorExistingCannotBeZero();
    error SharesDeployer__SharedAddressListIndexOutOfBounds();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor(Factories memory _factories) {
        SHARES_FACTORY = _factories.sharesFactory;
        FEE_HANDLER_FACTORY = _factories.feeHandlerFactory;
        VALUATION_HANDLER_FACTORY = _factories.valuationHandlerFactory;
        MANAGEMENT_FEE_TRACKER_FACTORY = _factories.managementFeeTrackerFactory;
        PERFORMANCE_FEE_TRACKER_FACTORY = _factories.performanceFeeTrackerFactory;
        ACCOUNT_ERC20_TRACKER_FACTORY = _factories.accountERC20TrackerFactory;
        LINEAR_CREDIT_DEBT_TRACKER_FACTORY = _factories.linearCreditDebtTrackerFactory;
        DEPOSIT_QUEUE_FACTORY = _factories.depositQueueFactory;
        SYNC_DEPOSIT_HANDLER_FACTORY = _factories.syncDepositHandlerFactory;
        REDEEM_QUEUE_FACTORY = _factories.redeemQueueFactory;
        SHARES_OWNED_ADDRESS_LIST_FACTORY = _factories.sharesOwnedAddressListFactory;
        OWNABLE_ADDRESS_LIST_FACTORY = _factories.ownableAddressListFactory;
        ADDRESS_LISTS_SHARES_TRANSFER_VALIDATOR_FACTORY = _factories.addressListsSharesTransferValidatorFactory;
    }

    //==================================================================================================================
    // Deploy
    //==================================================================================================================

    /// @notice Deploys and wires a complete Onyx vault in a single transaction
    /// @param _cfg The full vault configuration
    /// @return shares_ The address of the deployed Shares proxy
    /// @dev `Shares` owner during deploy is this contract. Pending owner is `_cfg.nominatedOwner` (Ownable2Step);
    /// the nominee must call `acceptOwnership()` to complete the handover.
    function deploy(DeployConfig calldata _cfg) external returns (address shares_) {
        __validate(_cfg);

        Deployed memory d;

        d.shares = BeaconFactory(SHARES_FACTORY)
            .deployProxy(
                abi.encodeCall(
                    Shares.init, (address(this), _cfg.shares.name, _cfg.shares.symbol, _cfg.shares.valueAsset)
                )
            );

        d.sharedAddressLists = __deploySharedAddressLists(d, _cfg);

        __deployValuationStack(d, _cfg);
        __preMint(d, _cfg);
        __deployFeeStack(d, _cfg);
        __deployQueueDepositHandlers(d, _cfg);
        __deploySyncDepositHandlers(d, _cfg);
        __deployRedeemHandlers(d, _cfg);

        Shares shares = Shares(d.shares);

        __deployTransferValidator(d, _cfg);
        if (d.transferValidator != address(0)) {
            shares.setSharesTransferValidator(d.transferValidator);
        }

        for (uint256 i; i < _cfg.admins.length; i++) {
            shares.addAdmin(_cfg.admins[i]);
        }

        shares.transferOwnership(_cfg.nominatedOwner);

        emit VaultDeployed({deployed: d, nominatedOwner: _cfg.nominatedOwner});

        return d.shares;
    }

    //==================================================================================================================
    // Internal: validation
    //==================================================================================================================

    function __validate(DeployConfig calldata _cfg) internal view {
        require(_cfg.nominatedOwner != address(0), SharesDeployer__NominatedOwnerCannotBeZero());
        require(_cfg.nominatedOwner != address(this), SharesDeployer__NominatedOwnerCannotBeDeployer());
        require(
            !_cfg.components.managementFee.deploy || _cfg.components.feeHandler.deploy,
            SharesDeployer__ManagementFeeRequiresFeeHandler()
        );
        require(
            !_cfg.components.performanceFee.deploy || _cfg.components.feeHandler.deploy,
            SharesDeployer__PerformanceFeeRequiresFeeHandler()
        );
        require(
            !_cfg.components.accountERC20Tracker.deploy || _cfg.components.valuationHandler.deploy,
            SharesDeployer__AccountERC20TrackerRequiresValuationHandler()
        );
        require(
            !_cfg.components.linearCreditDebtTracker.deploy || _cfg.components.valuationHandler.deploy,
            SharesDeployer__LinearCreditDebtTrackerRequiresValuationHandler()
        );
        require(
            !_cfg.preMint.enabled || _cfg.components.valuationHandler.deploy,
            SharesDeployer__PreMintRequiresValuationHandler()
        );

        __validateSharedAddressListDefinitions(_cfg.sharedAddressLists);

        uint256 sharedListCount = _cfg.sharedAddressLists.length;

        QueueDepositHandlerConfig[] calldata queueDepositHandlers = _cfg.components.queueDepositHandlers;
        for (uint256 i; i < queueDepositHandlers.length; i++) {
            __validateQueueDepositHandler(queueDepositHandlers[i], sharedListCount);
        }

        SyncDepositHandlerConfig[] calldata syncDepositHandlers = _cfg.components.syncDepositHandlers;
        for (uint256 i; i < syncDepositHandlers.length; i++) {
            __validateSyncDepositHandler(syncDepositHandlers[i], sharedListCount);
        }

        __validateTransferValidator(_cfg.transferValidator, sharedListCount);
    }

    function __validateSharedAddressListDefinitions(SharedAddressListDefinition[] calldata _defs) internal pure {
        for (uint256 i; i < _defs.length; i++) {
            SharedAddressListDefinition calldata def = _defs[i];
            if (def.kind == SharedAddressListKind.Ownable) {
                require(def.ownableListOwner != address(0), SharesDeployer__OwnableAddressListOwnerCannotBeZero());
            }
        }
    }

    function __validateTransferValidator(TransferValidatorConfig calldata _c, uint256 _sharedListCount) internal pure {
        if (_c.source == TransferValidatorSource.Existing) {
            require(_c.existing != address(0), SharesDeployer__TransferValidatorExistingCannotBeZero());
        } else if (_c.source == TransferValidatorSource.DeployAddressLists) {
            __validateValidatorListConfig(_c.recipientList, _sharedListCount);
            __validateValidatorListConfig(_c.senderList, _sharedListCount);
        }
    }

    function __validateValidatorListConfig(AddressListsValidatorListConfig calldata _c, uint256 _sharedListCount)
        internal
        pure
    {
        if (_c.listType == AddressListsSharesTransferValidator.ListType.None) {
            require(_c.externalListSource == ExternalListSource.None, SharesDeployer__ExternalListSourceNotAllowed());
        } else {
            __validateExternalListConfig({
                _source: _c.externalListSource,
                _existing: _c.externalListExisting,
                _sharedIndex: _c.sharedAddressListIndex,
                _sharedDefinitionsLength: _sharedListCount
            });
        }
    }

    function __validateQueueDepositHandler(QueueDepositHandlerConfig calldata _c, uint256 _sharedListCount)
        internal
        pure
    {
        if (_c.restriction == ERC7540LikeDepositQueue.DepositRestriction.None) {
            require(_c.externalListSource == ExternalListSource.None, SharesDeployer__ExternalListSourceNotAllowed());
            require(_c.allowedDepositors.length == 0, SharesDeployer__SeedNotAllowedWithoutAllowlist());
        } else if (_c.restriction == ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal) {
            require(_c.externalListSource == ExternalListSource.None, SharesDeployer__ExternalListSourceNotAllowed());
        } else {
            // ControllerAllowlistExternal
            __validateExternalListConfig({
                _source: _c.externalListSource,
                _existing: _c.externalListExisting,
                _sharedIndex: _c.sharedAddressListIndex,
                _sharedDefinitionsLength: _sharedListCount
            });
            require(_c.allowedDepositors.length == 0, SharesDeployer__SeedNotAllowedForExternalList());
        }
    }

    function __validateSyncDepositHandler(SyncDepositHandlerConfig calldata _c, uint256 _sharedListCount)
        internal
        pure
    {
        if (_c.depositorAllowlistSource != ExternalListSource.None) {
            __validateExternalListConfig({
                _source: _c.depositorAllowlistSource,
                _existing: _c.depositorAllowlistExisting,
                _sharedIndex: _c.sharedAddressListIndex,
                _sharedDefinitionsLength: _sharedListCount
            });
        }
    }

    function __validateExternalListConfig(
        ExternalListSource _source,
        address _existing,
        uint256 _sharedIndex,
        uint256 _sharedDefinitionsLength
    ) internal pure {
        require(_source != ExternalListSource.None, SharesDeployer__ExternalListSourceRequired());

        if (_source == ExternalListSource.Existing) {
            require(_existing != address(0), SharesDeployer__ExternalListExistingCannotBeZero());
        } else {
            // SharedAddressList
            require(_sharedIndex < _sharedDefinitionsLength, SharesDeployer__SharedAddressListIndexOutOfBounds());
        }
    }

    function __deploySharedAddressLists(Deployed memory _d, DeployConfig calldata _cfg)
        internal
        returns (address[] memory lists_)
    {
        SharedAddressListDefinition[] calldata defs = _cfg.sharedAddressLists;
        lists_ = new address[](defs.length);
        for (uint256 i; i < defs.length; i++) {
            SharedAddressListDefinition calldata def = defs[i];
            if (def.kind == SharedAddressListKind.SharesOwned) {
                lists_[i] = ComponentBeaconFactory(SHARES_OWNED_ADDRESS_LIST_FACTORY).deployProxy(_d.shares, "");
                if (def.seededAddresses.length > 0) {
                    AddressListBase(lists_[i]).addToList(def.seededAddresses);
                }
            } else {
                lists_[i] = BeaconFactory(OWNABLE_ADDRESS_LIST_FACTORY)
                    .deployProxy(abi.encodeCall(OwnableAddressList.init, (address(this))));
                if (def.seededAddresses.length > 0) {
                    AddressListBase(lists_[i]).addToList(def.seededAddresses);
                }
                OwnableAddressList(lists_[i]).transferOwnership(def.ownableListOwner);
            }
        }
        return lists_;
    }

    //==================================================================================================================
    // Internal: valuation stack
    //==================================================================================================================

    function __deployValuationStack(Deployed memory _d, DeployConfig calldata _cfg) internal {
        if (!_cfg.components.valuationHandler.deploy) return;

        ValuationHandler vh =
            ValuationHandler(ComponentBeaconFactory(VALUATION_HANDLER_FACTORY).deployProxy(_d.shares, ""));
        _d.valuationHandler = address(vh);

        if (_cfg.components.accountERC20Tracker.deploy) {
            AccountERC20Tracker tracker = AccountERC20Tracker(
                ComponentBeaconFactory(ACCOUNT_ERC20_TRACKER_FACTORY)
                    .deployProxy(_d.shares, abi.encodeCall(AccountERC20Tracker.init, (_d.shares)))
            );
            address[] calldata assets = _cfg.components.accountERC20Tracker.assets;
            for (uint256 i; i < assets.length; i++) {
                tracker.addAsset(assets[i]);
            }
            vh.addPositionTracker(address(tracker));
            _d.accountERC20Tracker = address(tracker);
        }

        if (_cfg.components.linearCreditDebtTracker.deploy) {
            address lcdt = ComponentBeaconFactory(LINEAR_CREDIT_DEBT_TRACKER_FACTORY).deployProxy(_d.shares, "");
            vh.addPositionTracker(lcdt);
            _d.linearCreditDebtTracker = lcdt;
        }

        ValuationHandler.AssetRateInput[] calldata assetRates = _cfg.components.valuationHandler.assetRates;
        for (uint256 i; i < assetRates.length; i++) {
            vh.setAssetRate(assetRates[i]);
        }

        Shares(_d.shares).setValuationHandler(address(vh));
    }

    //==================================================================================================================
    // Internal: pre-mint
    //==================================================================================================================

    function __preMint(Deployed memory _d, DeployConfig calldata _cfg) internal {
        if (!_cfg.preMint.enabled) return;

        Shares shares = Shares(_d.shares);
        shares.addDepositHandler(address(this));

        PreMintRecipient[] calldata recipients = _cfg.preMint.recipients;
        uint256 total = 0;
        for (uint256 i; i < recipients.length; i++) {
            total += recipients[i].amount;
        }
        shares.mintFor(address(this), total);

        ValuationHandler(_d.valuationHandler).updateShareValue(_cfg.preMint.untrackedPositionsValue);

        for (uint256 i; i < recipients.length; i++) {
            IERC20(address(shares)).safeTransfer(recipients[i].to, recipients[i].amount);
        }

        shares.removeDepositHandler(address(this));
    }

    //==================================================================================================================
    // Internal: fee stack
    //==================================================================================================================

    function __deployFeeStack(Deployed memory _d, DeployConfig calldata _cfg) internal {
        if (!_cfg.components.feeHandler.deploy) return;

        FeeHandler fh = FeeHandler(ComponentBeaconFactory(FEE_HANDLER_FACTORY).deployProxy(_d.shares, ""));
        _d.feeHandler = address(fh);

        FeeHandlerConfig calldata fhCfg = _cfg.components.feeHandler;
        if (fhCfg.feeAsset != address(0)) fh.setFeeAsset(fhCfg.feeAsset);
        if (fhCfg.entranceFeeBps != 0) {
            fh.setEntranceFee(fhCfg.entranceFeeBps, fhCfg.entranceFeeRecipient);
        }
        if (fhCfg.exitFeeBps != 0) {
            fh.setExitFee(fhCfg.exitFeeBps, fhCfg.exitFeeRecipient);
        }

        if (_cfg.components.managementFee.deploy) {
            ContinuousFlatRateManagementFeeTracker mft = ContinuousFlatRateManagementFeeTracker(
                ComponentBeaconFactory(MANAGEMENT_FEE_TRACKER_FACTORY).deployProxy(_d.shares, "")
            );
            mft.setRate(_cfg.components.managementFee.feeBps);
            mft.resetLastSettled();
            fh.setManagementFee(address(mft), _cfg.components.managementFee.recipient);
            _d.managementFeeTracker = address(mft);
        }

        ContinuousFlatRatePerformanceFeeTracker pft;
        if (_cfg.components.performanceFee.deploy) {
            pft = ContinuousFlatRatePerformanceFeeTracker(
                ComponentBeaconFactory(PERFORMANCE_FEE_TRACKER_FACTORY).deployProxy(_d.shares, "")
            );
            pft.setRate(_cfg.components.performanceFee.feeBps);
            if (_cfg.components.performanceFee.hurdleRateBps != 0) {
                pft.setHurdleRate(_cfg.components.performanceFee.hurdleRateBps);
            }
            fh.setPerformanceFee(address(pft), _cfg.components.performanceFee.recipient);
            _d.performanceFeeTracker = address(pft);
        }

        Shares(_d.shares).setFeeHandler(address(fh));

        // Must run after Shares→FeeHandler link is in place; resetHighWaterMark reads share price
        if (address(pft) != address(0)) pft.resetHighWaterMark();
    }

    //==================================================================================================================
    // Internal: queue deposit handlers
    //==================================================================================================================

    function __deployQueueDepositHandlers(Deployed memory _d, DeployConfig calldata _cfg) internal {
        QueueDepositHandlerConfig[] calldata cfgs = _cfg.components.queueDepositHandlers;
        address[] memory deployed = new address[](cfgs.length);
        address[] memory allowlists = new address[](cfgs.length);
        Shares shares = Shares(_d.shares);
        address[] memory sharedCatalog = _d.sharedAddressLists;

        for (uint256 i; i < cfgs.length; i++) {
            QueueDepositHandlerConfig calldata c = cfgs[i];
            ERC7540LikeDepositQueue q =
                ERC7540LikeDepositQueue(ComponentBeaconFactory(DEPOSIT_QUEUE_FACTORY).deployProxy(_d.shares, ""));
            q.setAsset(c.asset);
            q.setDepositMinRequestDuration(c.minRequestDuration);

            if (c.restriction == ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal) {
                q.setDepositRestriction(c.restriction);
                for (uint256 j; j < c.allowedDepositors.length; j++) {
                    q.addDepositControllerToInternalAllowlist(c.allowedDepositors[j]);
                }
            } else if (c.restriction == ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal) {
                address list = __resolveExternalAllowlist({
                    _source: c.externalListSource,
                    _existing: c.externalListExisting,
                    _sharedCatalog: sharedCatalog,
                    _sharedIndex: c.sharedAddressListIndex
                });
                q.setDepositControllerExternalAllowlist(list);
                q.setDepositRestriction(c.restriction);
                allowlists[i] = list;
            }

            shares.addDepositHandler(address(q));
            deployed[i] = address(q);
        }

        _d.queueDepositHandlers = deployed;
        _d.queueDepositHandlerAllowlists = allowlists;
    }

    //==================================================================================================================
    // Internal: sync deposit handlers
    //==================================================================================================================

    function __deploySyncDepositHandlers(Deployed memory _d, DeployConfig calldata _cfg) internal {
        SyncDepositHandlerConfig[] calldata cfgs = _cfg.components.syncDepositHandlers;
        address[] memory deployed = new address[](cfgs.length);
        address[] memory allowlists = new address[](cfgs.length);
        Shares shares = Shares(_d.shares);
        address[] memory sharedCatalog = _d.sharedAddressLists;

        for (uint256 i; i < cfgs.length; i++) {
            SyncDepositHandlerConfig calldata c = cfgs[i];
            SyncDepositHandler h = SyncDepositHandler(
                ComponentBeaconFactory(SYNC_DEPOSIT_HANDLER_FACTORY)
                    .deployProxy(_d.shares, abi.encodeCall(SyncDepositHandler.init, (c.asset)))
            );

            if (c.depositorAllowlistSource != ExternalListSource.None) {
                address list = __resolveExternalAllowlist({
                    _source: c.depositorAllowlistSource,
                    _existing: c.depositorAllowlistExisting,
                    _sharedCatalog: sharedCatalog,
                    _sharedIndex: c.sharedAddressListIndex
                });
                h.setDepositorAllowlist(list);
                allowlists[i] = list;
            }
            if (c.maxSharePriceStaleness != 0) {
                h.setMaxSharePriceStaleness(c.maxSharePriceStaleness);
            }

            shares.addDepositHandler(address(h));
            deployed[i] = address(h);
        }

        _d.syncDepositHandlers = deployed;
        _d.syncDepositHandlerAllowlists = allowlists;
    }

    //==================================================================================================================
    // Internal: external allowlist resolution
    //==================================================================================================================

    /// @dev Resolves an `IAddressList` address based on the given source. For `Existing` returns
    /// the provided address as-is. For `SharedAddressList` returns `_sharedCatalog[_sharedIndex]`.
    /// Caller must have already validated the inputs via `__validateExternalListConfig`.
    function __resolveExternalAllowlist(
        ExternalListSource _source,
        address _existing,
        address[] memory _sharedCatalog,
        uint256 _sharedIndex
    ) internal pure returns (address) {
        if (_source == ExternalListSource.SharedAddressList) {
            return _sharedCatalog[_sharedIndex];
        }
        // ExternalListSource.Existing (None is handled by callers)
        return _existing;
    }

    //==================================================================================================================
    // Internal: transfer validator
    //==================================================================================================================

    function __deployTransferValidator(Deployed memory _d, DeployConfig calldata _cfg) internal {
        TransferValidatorConfig calldata vc = _cfg.transferValidator;

        if (vc.source == TransferValidatorSource.None) {
            return;
        }

        if (vc.source == TransferValidatorSource.Existing) {
            _d.transferValidator = vc.existing;
            return;
        }

        // DeployAddressLists
        AddressListsSharesTransferValidator validator = AddressListsSharesTransferValidator(
            ComponentBeaconFactory(ADDRESS_LISTS_SHARES_TRANSFER_VALIDATOR_FACTORY).deployProxy(_d.shares, "")
        );
        _d.transferValidator = address(validator);

        address[] memory sharedCatalog = _d.sharedAddressLists;
        _d.transferValidatorRecipientList = __applyValidatorListConfig({
            _validator: validator, _isRecipient: true, _c: vc.recipientList, _sharedCatalog: sharedCatalog
        });
        _d.transferValidatorSenderList = __applyValidatorListConfig({
            _validator: validator, _isRecipient: false, _c: vc.senderList, _sharedCatalog: sharedCatalog
        });
    }

    function __applyValidatorListConfig(
        AddressListsSharesTransferValidator _validator,
        bool _isRecipient,
        AddressListsValidatorListConfig calldata _c,
        address[] memory _sharedCatalog
    ) internal returns (address list_) {
        if (_c.listType == AddressListsSharesTransferValidator.ListType.None) {
            return address(0);
        }

        list_ = __resolveExternalAllowlist({
            _source: _c.externalListSource,
            _existing: _c.externalListExisting,
            _sharedCatalog: _sharedCatalog,
            _sharedIndex: _c.sharedAddressListIndex
        });

        if (_isRecipient) {
            _validator.setRecipientList(list_, _c.listType);
        } else {
            _validator.setSenderList(list_, _c.listType);
        }
    }

    //==================================================================================================================
    // Internal: redeem handlers
    //==================================================================================================================

    function __deployRedeemHandlers(Deployed memory _d, DeployConfig calldata _cfg) internal {
        RedeemHandlerConfig[] calldata cfgs = _cfg.components.redeemHandlers;
        address[] memory deployed = new address[](cfgs.length);
        Shares shares = Shares(_d.shares);

        for (uint256 i; i < cfgs.length; i++) {
            RedeemHandlerConfig calldata c = cfgs[i];
            ERC7540LikeRedeemQueue q =
                ERC7540LikeRedeemQueue(ComponentBeaconFactory(REDEEM_QUEUE_FACTORY).deployProxy(_d.shares, ""));
            q.setAsset(c.asset);
            q.setRedeemMinRequestDuration(c.minRequestDuration);
            shares.addRedeemHandler(address(q));
            deployed[i] = address(q);
        }

        _d.redeemHandlers = deployed;
    }
}
