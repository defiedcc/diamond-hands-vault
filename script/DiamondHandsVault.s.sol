// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { DiamondHandsVault } from "../src/DiamondHandsVault.sol";

contract DiamondHandsVaultScript is Script {
    function setUp() public { }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        uint256 allTimeHigh = vm.envUint("ALL_TIME_HIGH");
        uint256 exitFeeBps = vm.envUint("EXIT_FEE_BPS");

        address exitFeeRecipient = vm.envAddress("EXIT_FEE_RECIPIENT");
        address wsteth = vm.envAddress("WSTETH");
        address steth = vm.envAddress("STETH");
        address priceFeed = vm.envAddress("CHAINLINK_PRICE_FEED");

        vm.startBroadcast(deployerPrivateKey);

        new DiamondHandsVault(allTimeHigh, exitFeeBps, exitFeeRecipient, wsteth, steth, priceFeed);

        vm.stopBroadcast();
    }
}
