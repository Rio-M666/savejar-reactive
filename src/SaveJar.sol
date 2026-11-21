// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title SaveJar — a savings jar that a reactive contract tops up automatically.
/// @notice Deposits land in a per-user *spendable* bucket and emit `Deposit`.
///         A reactive contract on Reactive Lasna watches those events and, when the
///         user's savings rule says so, calls back into `applySave` to move part of
///         the balance into a time-locked *saved* bucket. The user never signs the
///         save transaction — that is the whole point of the automation.
contract SaveJar {
    /// @notice Emitted on every deposit. This is the event the reactive contract subscribes to.
    /// @dev `amount` travels in the log data; `user` is topic 1.
    event Deposit(address indexed user, uint256 amount);

    /// @notice Emitted when a callback moves funds from spendable into locked savings.
    event SaveApplied(address indexed user, uint256 amount, uint256 newSavedTotal, uint256 unlockTime);

    /// @notice Emitted when the reactive contract address is set (one-time).
    event ReactiveContractSet(address indexed reactiveContract);

    /// @notice Emitted on withdrawals.
    event Withdrawn(address indexed user, uint256 amount, bool fromSaved);

    error NotOwner();
    error ReactiveAlreadySet();
    error NotCallbackProxy();
    error NotReactiveContract();
    error ZeroAmount();
    error InsufficientBalance();
    error StillLocked(uint256 unlockTime);
    error TransferFailed();

    /// @notice The Reactive callback proxy on this chain (Ethereum Sepolia:
    ///         0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4). Only it may deliver callbacks.
    address public immutable callbackProxy;

    /// @notice How long saved funds stay locked after the most recent save.
    uint256 public immutable lockDuration;

    /// @notice Deployer / admin. Can set the reactive contract address exactly once.
    address public owner;

    /// @notice The reactive contract on Lasna allowed to trigger saves.
    /// @dev Callbacks authenticate by comparing the network-injected first payload
    ///      argument (the RVM ID) against this address.
    address public reactiveContract;

    /// @notice Funds the user can withdraw at any time.
    mapping(address => uint256) public spendable;

    /// @notice Funds locked by the savings rule until `unlockTime`.
    mapping(address => uint256) public saved;

    /// @notice Timestamp after which `saved` can be withdrawn (refreshed on every save).
    mapping(address => uint256) public unlockTime;

    /// @notice Native balance reserved for paying callback-proxy fees via `pay()`.
    /// @dev Kept as separate accounting so user funds are never spent on fees.
    uint256 public feeReserve;

    constructor(address callbackProxy_, uint256 lockDuration_) {
        callbackProxy = callbackProxy_;
        lockDuration = lockDuration_;
        owner = msg.sender;
    }

    // ------------------------------------------------------------------
    // Deposits (origin side)
    // ------------------------------------------------------------------

    /// @notice Deposit native token into your spendable bucket.
    function deposit() external payable {
        _deposit();
    }

    /// @notice Plain transfers are deposits too — "just send it to the jar".
    receive() external payable {
        _deposit();
    }

    function _deposit() internal {
        if (msg.value == 0) revert ZeroAmount();
        spendable[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    // ------------------------------------------------------------------
    // Callback (destination side)
    // ------------------------------------------------------------------

    /// @notice Move `amount` of `user`'s balance from spendable into locked savings.
    /// @dev Called by the Reactive Network through the callback proxy. The network
    ///      overwrites the first payload argument with the reactive contract's
    ///      address, so `rvmId` must equal `reactiveContract`, and `msg.sender`
    ///      must be the callback proxy. If the requested amount exceeds the
    ///      spendable balance (e.g. the user withdrew in the meantime), the save
    ///      is clamped to what is actually there instead of reverting.
    function applySave(address rvmId, address user, uint256 amount) external {
        if (msg.sender != callbackProxy) revert NotCallbackProxy();
        if (rvmId != reactiveContract) revert NotReactiveContract();

        uint256 available = spendable[user];
        uint256 amt = amount > available ? available : amount;
        if (amt == 0) revert ZeroAmount();

        spendable[user] = available - amt;
        saved[user] += amt;
        unlockTime[user] = block.timestamp + lockDuration;

        emit SaveApplied(user, amt, saved[user], unlockTime[user]);
    }

    // ------------------------------------------------------------------
    // Withdrawals
    // ------------------------------------------------------------------

    /// @notice Withdraw from the spendable bucket at any time.
    function withdrawSpendable(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (spendable[msg.sender] < amount) revert InsufficientBalance();
        spendable[msg.sender] -= amount;
        _send(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, false);
    }

    /// @notice Withdraw from the saved bucket once the lock has expired.
    function withdrawSaved(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp < unlockTime[msg.sender]) revert StillLocked(unlockTime[msg.sender]);
        if (saved[msg.sender] < amount) revert InsufficientBalance();
        saved[msg.sender] -= amount;
        _send(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, true);
    }

    function _send(address to, uint256 amount) internal {
        (bool ok,) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    // ------------------------------------------------------------------
    // Admin & fee plumbing
    // ------------------------------------------------------------------

    /// @notice Point this jar at its reactive contract. One-time, owner only:
    ///         the reactive contract is deployed after the jar (it needs the
    ///         jar's address in its own constructor).
    function setReactiveContract(address reactiveContract_) external {
        if (msg.sender != owner) revert NotOwner();
        if (reactiveContract != address(0)) revert ReactiveAlreadySet();
        reactiveContract = reactiveContract_;
        emit ReactiveContractSet(reactiveContract_);
    }

    /// @notice Top up the reserve used to pay callback-proxy fees.
    function fundFees() external payable {
        feeReserve += msg.value;
    }

    /// @notice Called by the callback proxy when payment for delivered callbacks is due.
    /// @dev Follows the Reactive `IPayer` pattern; pays only out of `feeReserve`.
    function pay(uint256 amount) external {
        if (msg.sender != callbackProxy) revert NotCallbackProxy();
        if (amount == 0) return;
        if (feeReserve < amount) revert InsufficientBalance();
        feeReserve -= amount;
        _send(msg.sender, amount);
    }
}
