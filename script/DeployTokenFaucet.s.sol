// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenFaucet.sol";
import "../src/MockETH.sol";
import "./DeployHelper.s.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployTokenFaucet
 * @dev Script để deploy TokenFaucet contract với proxy pattern
 *
 * Cách sử dụng:
 * 1. Deploy implementation và proxy:
 *    forge script script/DeployTokenFaucet.s.sol:DeployTokenFaucet --rpc-url <RPC_URL> --broadcast
 *
 * 2. Verify contract:
 *    forge verify-contract <PROXY_ADDRESS> ERC1967Proxy --chain <CHAIN_ID>
 *    forge verify-contract <IMPLEMENTATION_ADDRESS> TokenFaucet --chain <CHAIN_ID>
 */

/**
 * @title DeployMockETH
 * @dev Deploy MockETH token with initial supply
 *
 * Usage:
 * forge script script/InteractFaucet.s.sol:DeployMockETH --rpc-url <RPC_URL> --broadcast
 */
contract DeployMockETH is DeployHelper {
    function run() external {
        // 1 million mETH initial supply
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000 ether));

        vm.startBroadcast(deployer);

        MockETH mockETH = new MockETH(initialSupply);

        console.log("\n=== MockETH Deployed ===");
        console.log("Address:", address(mockETH));
        console.log("Name:", mockETH.name());
        console.log("Symbol:", mockETH.symbol());
        console.log("Decimals:", mockETH.decimals());
        console.log("Total Supply:", mockETH.totalSupply());
        console.log("Owner:", mockETH.owner());
        console.log("======================\n");

        vm.stopBroadcast();
    }
}

/**
 * @title DeployFaucetWithMockETH
 * @dev Deploy both MockETH and TokenFaucet together
 *
 * Usage:
 * forge script script/InteractFaucet.s.sol:DeployFaucetWithMockETH --rpc-url <RPC_URL> --broadcast
 */
contract DeployFaucetWithMockETH is DeployHelper {
    function run() external {
        // 1 million mETH initial supply
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000 ether));
        // 100 mETH per claim
        uint256 claimAmount = vm.envOr("CLAIM_AMOUNT", uint256(100 ether));
        // 10,000 mETH to deposit into faucet
        uint256 depositAmount = vm.envOr("DEPOSIT_AMOUNT", uint256(10_000 ether));

        vm.startBroadcast(deployer);

        // 1. Deploy MockETH
        console.log("\n=== Deploying MockETH ===");
        MockETH mockETH = new MockETH(initialSupply);
        console.log("MockETH deployed at:", address(mockETH));

        // 2. Deploy TokenFaucet Implementation
        console.log("\n=== Deploying TokenFaucet ===");
        TokenFaucet implementation = new TokenFaucet();
        console.log("Implementation deployed at:", address(implementation));

        // 3. Deploy Proxy
        bytes memory initData =
            abi.encodeWithSelector(TokenFaucet.initialize.selector, address(mockETH), claimAmount);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy deployed at:", address(proxy));

        TokenFaucet faucet = TokenFaucet(address(proxy));

        console.log("Balance of deployer:", mockETH.balanceOf(deployer));

        // // 4. Approve and deposit tokens to faucet
        // console.log("\n=== Depositing to Faucet ===");
        // mockETH.approve(address(faucet), type(uint256).max);
        // faucet.deposit(depositAmount);
        // console.log("Deposited", depositAmount, "mETH to faucet");

        // // 5. Display summary
        // console.log("\n=== Deployment Summary ===");
        // console.log("MockETH Address:", address(mockETH));
        // console.log("Faucet Proxy:", address(faucet));
        // console.log("Faucet Implementation:", address(implementation));
        // console.log("Claim Amount:", claimAmount);
        // console.log("Faucet Balance:", faucet.getFaucetBalance());
        // console.log("Remaining Claims:", faucet.getRemainingClaims());
        // console.log("========================\n");

        vm.stopBroadcast();
    }
}

contract DeployTokenFaucet is DeployHelper {
    function run() external {
        // Đọc token address từ environment (hoặc hardcode nếu biết trước)
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");

        // Số lượng token mỗi lần claim (mặc định 100 tokens với 18 decimals)
        uint256 claimAmount = vm.envOr("CLAIM_AMOUNT", uint256(100 * 10 ** 18));

        vm.startBroadcast(deployer);

        // 1. Deploy implementation contract
        TokenFaucet implementation = new TokenFaucet();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Encode initialize data
        bytes memory initData =
            abi.encodeWithSelector(TokenFaucet.initialize.selector, tokenAddress, claimAmount);

        // 3. Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy deployed at:", address(proxy));

        // 4. Get faucet instance
        TokenFaucet faucet = TokenFaucet(address(proxy));

        console.log("\n=== Deployment Summary ===");
        console.log("Token Address:", address(faucet.token()));
        console.log("Claim Amount:", faucet.claimAmount());
        console.log("Owner:", faucet.owner());
        console.log("========================\n");

        vm.stopBroadcast();
    }
}

/**
 * @title UpgradeTokenFaucet
 * @dev Script để upgrade TokenFaucet contract
 *
 * Cách sử dụng:
 * forge script script/DeployTokenFaucet.s.sol:UpgradeTokenFaucet --rpc-url <RPC_URL> --broadcast
 */
contract UpgradeTokenFaucet is DeployHelper {
    function run() external {
        address proxyAddress = vm.envAddress("CUSTOM_TOKEN_FAUCET_ADDRESS");

        vm.startBroadcast(deployer);

        // Deploy new implementation
        TokenFaucet newImplementation = new TokenFaucet();
        console.log("New Implementation deployed at:", address(newImplementation));

        // Upgrade proxy to new implementation
        TokenFaucet faucet = TokenFaucet(proxyAddress);

        // Note: Cần có quyền owner để upgrade
        // faucet.upgradeTo(address(newImplementation));

        console.log("Proxy at:", proxyAddress);
        console.log("Upgraded to new implementation:", address(newImplementation));

        vm.stopBroadcast();
    }
}

/**
 * @title InteractTokenFaucet
 * @dev Script để tương tác với TokenFaucet đã deploy
 */
contract InteractTokenFaucet is Script {
    function run() external {
        uint256 userPrivateKey = vm.envUint("PRIVATE_KEY");
        address faucetAddress = vm.envAddress("FAUCET_ADDRESS");

        TokenFaucet faucet = TokenFaucet(faucetAddress);

        vm.startBroadcast(userPrivateKey);

        // Claim tokens
        console.log("Claiming tokens from faucet...");
        faucet.claim();
        console.log("Tokens claimed successfully!");

        vm.stopBroadcast();
    }
}

/**
 * @title DepositToFaucet
 * @dev Script để owner deposit token vào faucet
 */
contract DepositToFaucet is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address faucetAddress = vm.envAddress("FAUCET_ADDRESS");
        uint256 depositAmount = vm.envUint("DEPOSIT_AMOUNT");

        TokenFaucet faucet = TokenFaucet(faucetAddress);

        vm.startBroadcast(ownerPrivateKey);

        // Approve token
        IERC20 token = faucet.token();
        console.log("Approving tokens...");
        token.approve(faucetAddress, depositAmount);

        // Deposit
        console.log("Depositing", depositAmount, "tokens to faucet...");
        faucet.deposit(depositAmount);
        console.log("Deposit successful!");

        // Check faucet info
        (
            uint256 balance,
            uint256 claimAmount,
            uint256 totalClaimers,
            uint256 totalClaimed,
            uint256 remainingClaims,
            bool isPaused
        ) = faucet.getFaucetInfo();

        console.log("\n=== Faucet Info ===");
        console.log("Balance:", balance);
        console.log("Claim Amount:", claimAmount);
        console.log("Total Claimers:", totalClaimers);
        console.log("Total Claimed:", totalClaimed);
        console.log("Remaining Claims:", remainingClaims);
        console.log("Is Paused:", isPaused);
        console.log("===================\n");

        vm.stopBroadcast();
    }
}

/**
 * @title UpdateClaimAmount
 * @dev Script để update claim amount
 */
contract UpdateClaimAmount is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address faucetAddress = vm.envAddress("FAUCET_ADDRESS");
        uint256 newClaimAmount = vm.envUint("NEW_CLAIM_AMOUNT");

        TokenFaucet faucet = TokenFaucet(faucetAddress);

        vm.startBroadcast(ownerPrivateKey);

        console.log("Current claim amount:", faucet.claimAmount());
        console.log("Updating claim amount to:", newClaimAmount);

        faucet.setClaimAmount(newClaimAmount);

        console.log("Claim amount updated successfully!");
        console.log("New claim amount:", faucet.claimAmount());

        vm.stopBroadcast();
    }
}

/**
 * @title GetFaucetInfo
 * @dev Script để xem thông tin faucet
 */
contract GetFaucetInfo is Script {
    function run() external view {
        address faucetAddress = vm.envAddress("FAUCET_ADDRESS");
        TokenFaucet faucet = TokenFaucet(faucetAddress);

        console.log("\n=== Token Faucet Info ===");
        console.log("Faucet Address:", faucetAddress);
        console.log("Token Address:", address(faucet.token()));
        console.log("Owner:", faucet.owner());

        (
            uint256 balance,
            uint256 claimAmount,
            uint256 totalClaimers,
            uint256 totalClaimed,
            uint256 remainingClaims,
            bool isPaused
        ) = faucet.getFaucetInfo();

        console.log("\n=== Statistics ===");
        console.log("Faucet Balance:", balance);
        console.log("Claim Amount:", claimAmount);
        console.log("Total Claimers:", totalClaimers);
        console.log("Total Claimed:", totalClaimed);
        console.log("Remaining Claims:", remainingClaims);
        console.log("Is Paused:", isPaused);
        console.log("==================\n");
    }
}
