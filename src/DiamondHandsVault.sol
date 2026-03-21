// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

// forgefmt: disable-start
// ██████╗ ██╗ █████╗ ███╗   ███╗ ██████╗ ███╗   ██╗██████╗     ██╗  ██╗ █████╗ ███╗   ██╗██████╗ ███████╗
// ██╔══██╗██║██╔══██╗████╗ ████║██╔═══██╗████╗  ██║██╔══██╗    ██║  ██║██╔══██╗████╗  ██║██╔══██╗██╔════╝
// ██║  ██║██║███████║██╔████╔██║██║   ██║██╔██╗ ██║██║  ██║    ███████║███████║██╔██╗ ██║██║  ██║███████╗
// ██║  ██║██║██╔══██║██║╚██╔╝██║██║   ██║██║╚██╗██║██║  ██║    ██╔══██║██╔══██║██║╚██╗██║██║  ██║╚════██║
// ██████╔╝██║██║  ██║██║ ╚═╝ ██║╚██████╔╝██║ ╚████║██████╔╝    ██║  ██║██║  ██║██║ ╚████║██████╔╝███████║
// ╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝
// forgefmt: disable-end

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { AggregatorV3Interface } from "./interfaces/AggregatorV3Interface.sol";
import { IWstETH } from "./interfaces/IWstETH.sol";
import { IStETH } from "./interfaces/IStETH.sol";

/// @title DiamondHandsVault
/// @author Defied.cc
/// @notice A vault that locks ETH (as wstETH) until the ETH price reaches a specified all-time high.
/// @dev Deposited ETH is staked via Lido (stETH) and wrapped into wstETH to earn staking rewards.
///      Withdrawals before the all-time high is reached incur an early exit fee.
contract DiamondHandsVault {
    using SafeERC20 for IERC20;

    /// @notice Lido wrapped stETH contract address.
    address public immutable wstETH;

    /// @notice Lido stETH contract address.
    address public immutable stETH;

    /// @notice Chainlink ETH/USD price feed address.
    address public immutable priceFeed;

    /// @notice The ETH price target that must be reached to unlock fee-free withdrawals.
    uint256 public immutable allTimeHigh;

    /// @notice The early exit fee in basis points (1 bps = 0.01%).
    uint256 public immutable earlyExitFeeBps;

    /// @notice The address that receives early exit fees.
    address public immutable exitFeeRecipient;

    /// @notice Whether the ETH price all-time high target has been reached.
    bool public allTimeHighReached;

    /// @notice The total amount of wstETH deposited in the vault.
    uint256 public wstETHdeposited;

    /// @notice The wstETH balance of each depositor.
    mapping(address => uint256) public wstETHbalance;

    /// @notice Emitted when ETH is deposited and wrapped into wstETH.
    /// @param ethAmount The amount of ETH deposited.
    /// @param wstETHAmount The amount of wstETH received after wrapping.
    event ETHDeposited(address depositor, uint256 ethAmount, uint256 wstETHAmount);

    /// @notice Emitted when a user withdraws their wstETH balance.
    /// @param wstETHAmountToReceive The amount of wstETH transferred to the user (after any fee deduction).
    /// @param exitFeeAmount The early exit fee deducted (zero if the all-time high has been reached).
    event ETHWithdrawn(address depositor, uint256 wstETHAmountToReceive, uint256 exitFeeAmount);

    /// @notice Emitted when the ETH price all-time high target is reached.
    /// @param newAllTimeHigh The ETH price that met or exceeded the target.
    event ETHAllTimeHighReached(uint256 newAllTimeHigh);

    /// @notice Thrown when the deposit amount does not match `msg.value`.
    error InvalidDepositAmount();

    /// @notice Thrown when a user attempts to withdraw with a zero balance.
    error InvalidWithdrawAmount();

    /// @notice Thrown when a deposit is attempted after the all-time high has been reached.
    error AllTimeHighReached();

    /// @notice Thrown when `notifyAllTimeHigh` is called but the price has not reached the target.
    error AllTimeHighNotReached();

    /// @notice Thrown when the contract is deployed on a chain other than Ethereum mainnet.
    error MainnetOnlyDeployment();

    /// @notice Thrown when the early exit fee exceeds the maximum of 10% (1000 bps).
    error ExitFeeTooHigh();

    /// @notice Thrown when a zero address is provided for a required address parameter.
    error InvalidAddress();

    /// @notice Thrown when a zero amount is provided for a required value parameter.
    error InvalidAmount();

    /// @notice Initializes the vault with the target price, exit fee, and fee recipient.
    /// @param _allTimeHigh The ETH price target (in Chainlink 8-decimal format) to unlock fee-free withdrawals.
    /// @param _earlyExitFeeBps The early exit fee in basis points.
    /// @param _exitFeeRecipient The address that receives early exit fees.
    /// @param _wstETH The Lido wrapped stETH contract address.
    /// @param _stETH The Lido stETH contract address.
    /// @param _priceFeed The Chainlink ETH/USD price feed address.
    constructor(
        uint256 _allTimeHigh,
        uint256 _earlyExitFeeBps,
        address _exitFeeRecipient,
        address _wstETH,
        address _stETH,
        address _priceFeed
    ) {
        if (block.chainid != 1) revert MainnetOnlyDeployment();
        if (_allTimeHigh == 0) revert InvalidAmount();
        if (_earlyExitFeeBps > 1000) revert ExitFeeTooHigh();
        if (
            _exitFeeRecipient == address(0) || _wstETH == address(0) || _stETH == address(0) || _priceFeed == address(0)
        ) revert InvalidAddress();

        allTimeHigh = _allTimeHigh;
        earlyExitFeeBps = _earlyExitFeeBps;
        exitFeeRecipient = _exitFeeRecipient;
        wstETH = _wstETH;
        stETH = _stETH;
        priceFeed = _priceFeed;
    }

    /// @notice Allows the contract to receive ETH and automatically deposits it.
    receive() external payable {
        deposit();
    }

    /// @notice Withdraws the caller's entire wstETH balance from the vault.
    /// @dev If the all-time high has not been reached, an early exit fee is deducted and sent to `exitFeeRecipient`.
    ///      If the all-time high has been reached, the full balance is returned with no fee.
    function withdraw() external {
        uint256 userWstETHBalance = wstETHbalance[msg.sender];
        if (userWstETHBalance == 0) revert InvalidWithdrawAmount();
        uint256 userAmountToReceive;
        uint256 earlyExitFeeAmount;

        wstETHbalance[msg.sender] = 0;
        wstETHdeposited -= userWstETHBalance;

        if (allTimeHighReached) {
            userAmountToReceive = userWstETHBalance;
        } else {
            earlyExitFeeAmount = (earlyExitFeeBps * userWstETHBalance) / 10_000;
            userAmountToReceive = userWstETHBalance - earlyExitFeeAmount;
        }

        if (earlyExitFeeAmount > 0) {
            IERC20(wstETH).safeTransfer(exitFeeRecipient, earlyExitFeeAmount);
        }
        if (userAmountToReceive > 0) {
            IERC20(wstETH).safeTransfer(msg.sender, userAmountToReceive);
        }

        emit ETHWithdrawn(msg.sender, userAmountToReceive, earlyExitFeeAmount);
    }

    /// @notice Checks the current ETH price and, if it meets or exceeds the target, unlocks fee-free withdrawals.
    /// @dev Can be called by anyone. Reverts if the all-time high has already been reached.
    ///      Once triggered, deposits are permanently disabled and withdrawals become fee-free.
    /// @return newAllTimeHigh The current ETH price that met or exceeded the target.
    function notifyAllTimeHigh() external returns (uint256 newAllTimeHigh) {
        if (allTimeHighReached) revert AllTimeHighReached();

        (int256 currentPrice,) = getETHPrice();

        if (uint256(currentPrice) < allTimeHigh) revert AllTimeHighNotReached();

        newAllTimeHigh = uint256(currentPrice);

        allTimeHighReached = true;

        emit ETHAllTimeHighReached(newAllTimeHigh);
    }

    /// @notice Deposits ETH into the vault by staking it via Lido and wrapping into wstETH.
    /// @dev The `amount` parameter must equal `msg.value`. Deposits are blocked once the all-time high is reached.
    ///      ETH is submitted to Lido for stETH shares, converted to the underlying stETH amount, then wrapped into
    /// wstETH.
    function deposit() public payable {
        if (msg.value == 0) revert InvalidDepositAmount();
        if (allTimeHighReached) revert AllTimeHighReached();

        uint256 shares = IStETH(stETH).submit{ value: msg.value }(address(this));
        uint256 stETHAmount = IStETH(stETH).getPooledEthByShares(shares);

        IERC20(stETH).approve(wstETH, stETHAmount);

        uint256 wstETHAmount = IWstETH(wstETH).wrap(stETHAmount);

        if (wstETHAmount == 0) revert InvalidDepositAmount();

        wstETHbalance[msg.sender] += wstETHAmount;

        wstETHdeposited += wstETHAmount;

        emit ETHDeposited(msg.sender, msg.value, wstETHAmount);
    }

    /// @notice Fetches the latest ETH/USD price from the Chainlink oracle.
    /// @dev Reverts if the price is stale (>1 hour), non-positive, or from an incomplete round.
    /// @return price The latest ETH/USD price (8 decimals).
    /// @return updatedAt The timestamp of the latest price update.
    function getETHPrice() public view returns (int256 price, uint256 updatedAt) {
        (uint80 roundId, int256 answer,, uint256 _updatedAt, uint80 answeredInRound) =
            AggregatorV3Interface(priceFeed).latestRoundData();

        require(block.timestamp - _updatedAt <= 1 hours, "Stale price");

        require(answer > 0, "Invalid price");
        require(answeredInRound >= roundId, "Incomplete round");

        return (answer, _updatedAt);
    }
}
