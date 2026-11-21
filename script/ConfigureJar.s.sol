// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {SaveJar} from "../src/SaveJar.sol";

/// @notice Step 3 (Ethereum Sepolia): point the jar at its reactive contract and
///         seed the fee reserve used to pay for callback delivery.
/// @dev Env: JAR_ADDRESS (step 1), RSC_ADDRESS (step 2).
///      Run: forge script script/ConfigureJar.s.sol --rpc-url sepolia --broadcast
contract ConfigureJar is Script {
    function run() external {
        uint256 pk = vm.envUint("BURNER_PRIVATE_KEY");
        SaveJar jar = SaveJar(payable(vm.envAddress("JAR_ADDRESS")));
        address rsc = vm.envAddress("RSC_ADDRESS");
        vm.startBroadcast(pk);
        jar.setReactiveContract(rsc);
        jar.fundFees{value: 0.01 ether}();
        vm.stopBroadcast();
        console.log("Jar configured with reactive contract:", rsc);
    }
}
