// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DiamondHandsVault} from "../src/DiamondHandsVault.sol";

contract CounterScript is Script {
    DiamondHandsVault public dhVault;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        vm.stopBroadcast();
    }
}
