// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {AutoSaveReactive} from "../src/AutoSaveReactive.sol";

/// @notice Step 2 (Reactive Lasna): deploy the reactive contract.
/// @dev Env: JAR_ADDRESS (from step 1). The contract is deployed with 1 lREACT so it
///      can pay subscription / reactive-transaction fees from its own balance.
///      Run: forge script script/DeployReactive.s.sol --rpc-url lasna --broadcast
contract DeployReactive is Script {
    uint256 constant SEPOLIA = 11155111;

    function run() external {
        uint256 pk = vm.envUint("BURNER_PRIVATE_KEY");
        address jar = vm.envAddress("JAR_ADDRESS");
        vm.startBroadcast(pk);
        AutoSaveReactive rsc = new AutoSaveReactive{value: 1 ether}(
            SEPOLIA, // origin: Ethereum Sepolia
            SEPOLIA, // destination: Ethereum Sepolia
            jar,
            2000, // 20% savings cut
            0.01 ether, // sweep threshold
            0.05 ether // daily cap per user
        );
        vm.stopBroadcast();
        console.log("AutoSaveReactive deployed:", address(rsc));
    }
}
