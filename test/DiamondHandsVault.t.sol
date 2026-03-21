// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

// ██████╗ ██╗ █████╗ ███╗   ███╗ ██████╗ ███╗   ██╗██████╗     ██╗  ██╗ █████╗ ███╗   ██╗██████╗ ███████╗
// ██╔══██╗██║██╔══██╗████╗ ████║██╔═══██╗████╗  ██║██╔══██╗    ██║  ██║██╔══██╗████╗  ██║██╔══██╗██╔════╝
// ██║  ██║██║███████║██╔████╔██║██║   ██║██╔██╗ ██║██║  ██║    ███████║███████║██╔██╗ ██║██║  ██║███████╗
// ██║  ██║██║██╔══██║██║╚██╔╝██║██║   ██║██║╚██╗██║██║  ██║    ██╔══██║██╔══██║██║╚██╗██║██║  ██║╚════██║
// ██████╔╝██║██║  ██║██║ ╚═╝ ██║╚██████╔╝██║ ╚████║██████╔╝    ██║  ██║██║  ██║██║ ╚████║██████╔╝███████║
// ╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝

import {Test, console} from "forge-std/Test.sol";
import {DiamondHandsVault} from "../src/DiamondHandsVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

/// @title DiamondHandsVault Test Suite
/// @notice Foundry tests for the DiamondHandsVault contract covering deployment,
///         deposits, withdrawals, ATH notification, and oracle price feed validation.
/// @dev Tests run against a mainnet fork at block 24703610 to interact with live
///      Lido (stETH/wstETH) and Chainlink ETH/USD price feed contracts.
contract DiamondHandsVaultTest is Test {
    DiamondHandsVault public dhVault;

    /// @dev ETH ATH target price in Chainlink 8-decimal format (~$4,953.73).
    uint256 ethAllTimeHigh = 495373000000;

    /// @dev Early exit fee: 1000 bps = 10% (the maximum allowed).
    uint256 earlyExitFee = 1000;

    /// @dev Address that receives early exit fees on pre-ATH withdrawals.
    address exitFeeRecipient = makeAddr("john");

    /// @dev Lido wstETH contract on Ethereum mainnet.
    address wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @dev Lido stETH contract on Ethereum mainnet.
    address stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    /// @dev Chainlink ETH/USD price feed on Ethereum mainnet.
    address priceFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    address depositor1 = makeAddr("depositor1");
    address depositor2 = makeAddr("depositor2");

    /// @notice Forks mainnet at a specific block and deploys the vault with default parameters.
    /// @dev Both depositors are funded with 100 ETH for test scenarios.
    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 24703610);
        dhVault = new DiamondHandsVault(ethAllTimeHigh, earlyExitFee, exitFeeRecipient, wstETH, stETH, priceFeed);

        vm.deal(depositor1, 100 ether);
        vm.deal(depositor2, 100 ether);
    }

    /// @notice Deployment reverts when chain ID is not Ethereum mainnet (1).
    function test_deploy_shouldRevertIfChainIdNotMainnet() public {
        // Simulate a non-mainnet chain
        vm.chainId(31337);

        vm.expectRevert(abi.encodeWithSelector(DiamondHandsVault.MainnetOnlyDeployment.selector));

        new DiamondHandsVault(ethAllTimeHigh, earlyExitFee, exitFeeRecipient, wstETH, stETH, priceFeed);
    }

    /// @notice Deployment reverts when the ATH target price is set to zero.
    function test_deploy_shouldRevertIfAllTimeHighIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(DiamondHandsVault.InvalidAmount.selector));

        new DiamondHandsVault(0, earlyExitFee, exitFeeRecipient, wstETH, stETH, priceFeed);
    }

    /// @notice Deployment reverts when the early exit fee exceeds the 10% (1000 bps) cap.
    function test_deploy_shouldRevertIfExitFeeTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(DiamondHandsVault.ExitFeeTooHigh.selector));

        // 1001 bps exceeds the maximum allowed 1000 bps
        new DiamondHandsVault(ethAllTimeHigh, 1001, exitFeeRecipient, wstETH, stETH, priceFeed);
    }

    /// @notice Deployment reverts when any required address parameter is the zero address.
    function test_deploy_shouldRevertIfAddressConfigIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(DiamondHandsVault.InvalidAddress.selector));

        new DiamondHandsVault(ethAllTimeHigh, earlyExitFee, address(0), address(0), address(0), address(0));
    }

    /// @notice Two depositors each deposit 1 ETH; verifies wstETH balances are credited
    ///         and the vault's total wstETH token balance equals the sum of user balances.
    function test_deposit_shouldSuccessfullyDeposit() public {
        // First depositor deposits 1 ETH
        vm.expectEmit();
        emit DiamondHandsVault.ETHDeposited(depositor1, 1 ether, 813127203918803466);

        vm.prank(depositor1);
        dhVault.deposit{value: 1 ether}();

        assertEq(dhVault.wstETHbalance(depositor1), 813127203918803466);

        // Second depositor deposits 1 ETH
        vm.expectEmit();
        emit DiamondHandsVault.ETHDeposited(depositor2, 1 ether, 813127203918803466);

        vm.prank(depositor2);
        dhVault.deposit{value: 1 ether}();

        assertEq(dhVault.wstETHbalance(depositor2), 813127203918803466);

        // Vault's wstETH token balance must equal the sum of all depositor balances
        assertEq(
            (dhVault.wstETHbalance(depositor1) + dhVault.wstETHbalance(depositor2)),
            IERC20(wstETH).balanceOf(address(dhVault))
        );
    }

    /// @notice Depositing via a raw ETH transfer (triggering `receive()`) should behave
    ///         identically to calling `deposit()` directly.
    function test_receive_shouldSuccessfullyDepositByDirectTransfer() public {
        vm.expectEmit();
        emit DiamondHandsVault.ETHDeposited(depositor1, 1 ether, 813127203918803466);

        vm.prank(depositor1);
        (bool ok,) = payable(address(dhVault)).call{value: 1 ether}("");
        require(ok, "ETH transfer failed");
    }

    /// @notice Depositing zero ETH should revert with `InvalidDepositAmount`.
    function test_deposit_shouldRevertIfMsgValueIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(DiamondHandsVault.InvalidDepositAmount.selector));

        vm.prank(depositor1);
        dhVault.deposit{value: 0 ether}();
    }

    /// @notice Depositing a dust amount (2 wei) should revert because wrapping yields 0 wstETH.
    function test_depoist_shouldRevertWithDustAmount() public {
        vm.expectRevert(abi.encodeWithSelector(DiamondHandsVault.InvalidDepositAmount.selector));

        vm.prank(depositor1);
        dhVault.deposit{value: 2 wei}();
    }

    /// @notice Deposits are blocked once the ATH has been reached.
    /// @dev First triggers ATH via a mocked price feed returning $5,000, then attempts a deposit.
    function test_deposit_shouldRevertIfAllTimeHighReached() public {
        // Mock the Chainlink price feed to return $5,000 (above ATH target)
        bytes memory returnData =
            abi.encode(uint80(1), int256(5000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(1));

        vm.mockCall(
            address(priceFeed), abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), returnData
        );

        // Trigger ATH notification
        vm.prank(depositor1);
        dhVault.notifyAllTimeHigh();

        // Subsequent deposits should revert
        vm.expectRevert(abi.encodeWithSelector(DiamondHandsVault.AllTimeHighReached.selector));

        vm.prank(depositor1);
        dhVault.deposit{value: 1 ether}();
    }

    /// @notice Withdrawing before the ATH deducts a 10% early exit fee and sends it to the fee recipient.
    /// @dev The user receives 90% of their wstETH; the fee recipient receives the remaining 10%.
    function test_withdraw_shouldSuccessfullyWithdrawAllTimeHighNotReached() public {
        vm.prank(depositor1);
        dhVault.deposit{value: 1 ether}();

        vm.expectEmit();
        emit DiamondHandsVault.ETHWithdrawn(depositor1, 731814483526923120, 81312720391880346);

        vm.prank(depositor1);
        dhVault.withdraw();

        // User receives balance minus 10% fee
        vm.assertEq(IERC20(wstETH).balanceOf(depositor1), 731814483526923120);
        // Fee recipient receives the 10% early exit fee
        vm.assertEq(IERC20(wstETH).balanceOf(exitFeeRecipient), 81312720391880346);
    }

    /// @notice Withdrawing after the ATH has been reached returns the full balance with zero fee.
    function test_withdraw_shouldSuccessfullyWithdrawAllTimeHighReached() public {
        vm.prank(depositor1);
        dhVault.deposit{value: 1 ether}();

        // Mock price feed to $5,000 and trigger ATH
        bytes memory returnData =
            abi.encode(uint80(1), int256(5000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(1));

        vm.mockCall(
            address(priceFeed), abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), returnData
        );

        vm.prank(depositor1);
        dhVault.notifyAllTimeHigh();

        vm.expectEmit();
        emit DiamondHandsVault.ETHWithdrawn(depositor1, 813127203918803466, 0);

        vm.prank(depositor1);
        dhVault.withdraw();

        // Full balance returned, no fee deducted
        vm.assertEq(IERC20(wstETH).balanceOf(depositor1), 813127203918803466);
        vm.assertEq(IERC20(wstETH).balanceOf(exitFeeRecipient), 0);
    }

    /// @notice A user with zero balance cannot withdraw.
    function test_withdraw_shouldRevertIfUserBalanceIsZero() public {
        // depositor1 deposits, but depositor2 does not
        vm.prank(depositor1);
        dhVault.deposit{value: 1 ether}();

        vm.expectRevert(abi.encodeWithSelector(DiamondHandsVault.InvalidWithdrawAmount.selector));

        // depositor2 has no balance and should be rejected
        vm.prank(depositor2);
        dhVault.withdraw();
    }

    /// @notice Calling `notifyAllTimeHigh` when the oracle price exceeds the target
    ///         sets the ATH flag and emits the event.
    function test_notifyAllTimeHigh_shouldSuccessfullyNotifyAllTimeHigh() public {
        // Mock Chainlink to return $5,000 (above the ~$4,953 target)
        bytes memory returnData =
            abi.encode(uint80(1), int256(5000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(1));

        vm.mockCall(
            address(priceFeed), abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), returnData
        );

        vm.expectEmit();
        emit DiamondHandsVault.ETHAllTimeHighReached(5000e8);

        vm.prank(depositor1);
        dhVault.notifyAllTimeHigh();
    }

    /// @notice Calling `notifyAllTimeHigh` when the price is below the target reverts.
    function test_notifyAllTimeHigh_shouldRevertIfAllTimeHighNotReached() public {
        // Current fork price (~$2,153) is below the ~$4,953 target
        vm.expectRevert(abi.encodeWithSelector(DiamondHandsVault.AllTimeHighNotReached.selector));

        vm.prank(depositor1);
        dhVault.notifyAllTimeHigh();
    }

    /// @notice Calling `notifyAllTimeHigh` a second time reverts because the flag is already set.
    function test_notifyAllTimeHigh_shouldRevertIfAllTimeHighReached() public {
        bytes memory returnData =
            abi.encode(uint80(1), int256(5000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(1));

        vm.mockCall(
            address(priceFeed), abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), returnData
        );

        // First call succeeds
        vm.expectEmit();
        emit DiamondHandsVault.ETHAllTimeHighReached(5000e8);

        vm.prank(depositor1);
        dhVault.notifyAllTimeHigh();

        // Second call reverts — ATH is already flagged
        vm.expectRevert(abi.encodeWithSelector(DiamondHandsVault.AllTimeHighReached.selector));

        vm.prank(depositor1);
        dhVault.notifyAllTimeHigh();
    }

    /// @notice Fetches the real ETH price from the forked Chainlink feed and verifies
    ///         the expected values at block 24703610.
    function test_getETHPrice_shouldSuccessfullyGetETHPrice() public {
        vm.prank(depositor1);
        (int256 price, uint256 updatedAt) = dhVault.getETHPrice();

        // ~$2,153.85 in 8-decimal format at the forked block
        vm.assertEq(price, 215385330310);
        vm.assertEq(updatedAt, 1774065719);
    }

    /// @notice `getETHPrice` reverts when the price data is older than 1 hour (stale).
    function test_getETHPrice_shouldRevertIfStalePrice() public {
        // updatedAt is 3601 seconds behind block.timestamp, exceeding the 1-hour threshold
        bytes memory returnData =
            abi.encode(uint80(1), int256(5000e8), uint256(block.timestamp), uint256(block.timestamp - 3601), uint80(1));

        vm.mockCall(
            address(priceFeed), abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), returnData
        );

        vm.expectRevert("Stale price");
        dhVault.getETHPrice();
    }

    /// @notice `getETHPrice` reverts when the oracle returns a zero (non-positive) price.
    function test_getETHPrice_shouldRevertIfInvalidPrice() public {
        bytes memory returnData =
            abi.encode(uint80(1), int256(0), uint256(block.timestamp), uint256(block.timestamp), uint80(1));

        vm.mockCall(
            address(priceFeed), abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), returnData
        );

        vm.expectRevert("Invalid price");
        dhVault.getETHPrice();
    }

    /// @notice `getETHPrice` reverts when `answeredInRound < roundId`, indicating an incomplete round.
    function test_getETHPrice_shouldRevertIfIncompleteRound() public {
        // roundId=6 but answeredInRound=5 → round not fully answered
        bytes memory returnData =
            abi.encode(uint80(6), int256(5000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(5));

        vm.mockCall(
            address(priceFeed), abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), returnData
        );

        vm.expectRevert("Incomplete round");
        dhVault.getETHPrice();
    }
}
