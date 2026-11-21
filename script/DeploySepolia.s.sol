// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {SaveJar} from "../src/SaveJar.sol";

/// @notice Step 1 (Ethereum Sepolia): deploy the SaveJar.
/// @dev Run: forge script script/DeploySepolia.s.sol --rpc-url sepolia --broadcast
///      Requires SEPOLIA_RPC_URL and a funded BURNER_PRIVATE_KEY (see deploy-all.sh,
///      which wraps all steps; this script exists for step-by-step manual runs).
contract DeploySepolia is Script {
    /// @notice Reactive callback proxy on Ethereum Sepolia (docs: Origins & Destinations).
    address constant CALLBACK_PROXY_SEPOLIA = 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4;

    function run() external {
        uint256 pk = vm.envUint("BURNER_PRIVATE_KEY");
        vm.startBroadcast(pk);
        SaveJar jar = new SaveJar(CALLBACK_PROXY_SEPOLIA, 7 days);
        vm.stopBroadcast();
        console.log("SaveJar deployed:", address(jar));
    }
}
