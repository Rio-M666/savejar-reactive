// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractReactive} from "reactive-lib-omni/base/AbstractReactive.sol";
import {ISystemContract} from "reactive-lib-omni/interfaces/ISystemContract.sol";
import {IReactive} from "reactive-lib-omni/interfaces/IReactive.sol";

/// @title AutoSaveReactive — the reactive brain of SaveJar.
/// @notice Deployed on Reactive Lasna. Subscribes to `Deposit` events emitted by a
///         SaveJar contract on the origin chain and enforces the user's savings rule:
///
///           cut        = deposit × saveBps / 10_000
///           accumulate = small cuts pile up in `pendingCut` (no callback yet)
///           sweep      = once pendingCut ≥ sweepThreshold, request ONE callback
///                        moving the accumulated amount into locked savings
///           cap        = a user can be swept at most `dailyCap` per day
///
///         The contract holds per-user state and decides *whether* and *how much*
///         to save — it is not a dumb event relay. All decisions happen inside
///         `react()`, executed by the Reactive Network; nobody runs a bot.
contract AutoSaveReactive is AbstractReactive {
    /// @notice topic0 of SaveJar's `Deposit(address,uint256)` event.
    uint256 public constant DEPOSIT_TOPIC = uint256(keccak256("Deposit(address,uint256)"));

    /// @notice Callback gas limit. Reactive ignores requests below 100_000 gas.
    /// @dev Sized generously on purpose: before invoking the recipient, the
    ///      destination callback proxy withholds `_extraGas` (150_000 on Sepolia)
    ///      for its own accounting plus `_maxChargeGas` (50_000) for payment
    ///      settlement, and only the remainder reaches the callback method.
    ///      A 300_000 request left only ~57k for `applySave`, which ran out of
    ///      gas on the first live delivery (see deployments.md). The fee is
    ///      charged on gas actually used, so a high limit costs nothing extra.
    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;

    uint256 public immutable originChainId;
    uint256 public immutable destinationChainId;

    /// @notice The SaveJar contract: event source on the origin chain and callback
    ///         recipient on the destination chain (same address — it lives on one chain).
    address public immutable jar;

    /// @notice Savings cut in basis points (2_000 = 20%).
    uint256 public immutable saveBps;

    /// @notice Minimum accumulated cut before a sweep callback is requested.
    uint256 public immutable sweepThreshold;

    /// @notice Maximum total swept per user per day.
    uint256 public immutable dailyCap;

    /// @notice Cut accrued but not yet swept, per user.
    mapping(address => uint256) public pendingCut;

    /// @notice Amount already swept today, per user.
    mapping(address => uint256) public sweptToday;

    /// @notice Day index (unix days) of the last accounting reset, per user.
    mapping(address => uint256) public lastDay;

    /// @notice Lifetime amount this contract has moved into savings, per user.
    mapping(address => uint256) public totalSaved;

    /// @notice Total number of sweep callbacks requested.
    uint256 public savesExecuted;

    event SweepRequested(address indexed user, uint256 amount);
    event CutAccrued(address indexed user, uint256 cut, uint256 pendingTotal);

    /// @param originChainId_      Chain the SaveJar lives on (event source).
    /// @param destinationChainId_ Chain callbacks are delivered to (same chain here).
    /// @param jar_                SaveJar address.
    /// @param saveBps_            Savings cut in basis points.
    /// @param sweepThreshold_     Minimum accumulated cut per sweep, in wei.
    /// @param dailyCap_           Maximum swept per user per day, in wei.
    constructor(
        uint256 originChainId_,
        uint256 destinationChainId_,
        address jar_,
        uint256 saveBps_,
        uint256 sweepThreshold_,
        uint256 dailyCap_
    ) payable {
        originChainId = originChainId_;
        destinationChainId = destinationChainId_;
        jar = jar_;
        saveBps = saveBps_;
        sweepThreshold = sweepThreshold_;
        dailyCap = dailyCap_;

        SYSTEM.subscribe(originChainId, jar, DEPOSIT_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    /// @notice Entry point called by the Reactive Network for every matching log.
    /// @dev Guarded by `onlySystem` (msg.sender must be the system contract).
    ///      Foreign logs are ignored defensively even though the subscription
    ///      already filters by chain, contract and topic0.
    function react(IReactive.LogRecord calldata log) external onlySystem {
        if (log.chainId != originChainId) return;
        if (log.contractAddress != jar) return;
        if (log.topic0 != DEPOSIT_TOPIC) return;

        address user = address(uint160(log.topic1));
        uint256 amount = abi.decode(log.data, (uint256));

        uint256 cut = (amount * saveBps) / 10_000;
        if (cut == 0) return;

        // Daily-cap accounting. Note: block.timestamp here is Lasna's clock,
        // which is fine for a per-day savings cap.
        uint256 today = block.timestamp / 1 days;
        if (lastDay[user] != today) {
            lastDay[user] = today;
            sweptToday[user] = 0;
        }
        uint256 alreadySwept = sweptToday[user];
        if (alreadySwept >= dailyCap) return;
        uint256 room = dailyCap - alreadySwept;
        if (cut > room) cut = room; // excess stays spendable by design

        pendingCut[user] += cut;
        emit CutAccrued(user, cut, pendingCut[user]);

        if (pendingCut[user] < sweepThreshold) return; // keep accumulating dust

        uint256 sweep = pendingCut[user];
        pendingCut[user] = 0;
        sweptToday[user] = alreadySwept + sweep;
        totalSaved[user] += sweep;
        savesExecuted++;

        // First payload argument MUST be address(0): the network overwrites it
        // with this contract's address so the destination can authenticate us.
        bytes memory payload = abi.encodeWithSignature("applySave(address,address,uint256)", address(0), user, sweep);

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId, recipient: jar, gasLimit: CALLBACK_GAS_LIMIT, payload: payload
            })
        );

        emit SweepRequested(user, sweep);
    }
}
