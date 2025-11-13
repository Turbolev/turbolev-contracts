// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../DeployHelper.s.sol";
import "../../src/mock/TokenFaucet.sol";
import "../../src/mock/MockETH.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title MockETHFaucet
 * @dev Use MockETH's built-in faucet function to get test tokens
 *
 * Usage:
 * export MOCK_ETH_ADDRESS=0x...
 * forge script script/interact/InteractFaucet.s.sol:MockETHFaucet --rpc-url <RPC_URL> --broadcast
 */
contract MockETHFaucet is DeployHelper {
    function run() external {
        uint256 userPrivateKey = vm.envUint("PRIVATE_KEY");
        address mockETHAddress = vm.envAddress("MOCK_ETH_ADDRESS");

        MockETH mockETH = MockETH(mockETHAddress);

        vm.startBroadcast(userPrivateKey);

        address user = vm.addr(userPrivateKey);
        uint256 balanceBefore = mockETH.balanceOf(user);

        console.log("\n=== Getting mETH from Built-in Faucet ===");
        console.log("User:", user);
        console.log("Balance Before:", balanceBefore);

        mockETH.faucet();

        uint256 balanceAfter = mockETH.balanceOf(user);
        console.log("Balance After:", balanceAfter);
        console.log("Received:", balanceAfter - balanceBefore);
        console.log("======================================\n");

        vm.stopBroadcast();
    }
}

/**
 * @title MintMockETH
 * @dev Owner mints MockETH to specified address
 *
 * Usage:
 * export MOCK_ETH_ADDRESS=0x...
 * export RECIPIENT=0x...
 * export MINT_AMOUNT=1000000000000000000000 # 1000 mETH
 * forge script script/InteractFaucet.s.sol:MintMockETH --rpc-url <RPC_URL> --broadcast
 */
contract MintMockETH is DeployHelper {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address mockETHAddress = vm.envAddress("MOCK_ETH_ADDRESS");
        address recipient = vm.envAddress("RECIPIENT");
        uint256 amount = vm.envUint("MINT_AMOUNT");

        MockETH mockETH = MockETH(mockETHAddress);

        vm.startBroadcast(ownerPrivateKey);

        console.log("\n=== Minting MockETH ===");
        console.log("Recipient:", recipient);
        console.log("Amount:", amount);

        mockETH.mint(recipient, amount);

        console.log("Minted successfully!");
        console.log("New Balance:", mockETH.balanceOf(recipient));
        console.log("=====================\n");

        vm.stopBroadcast();
    }
}

/**
 * @title BurnMockETH
 * @dev Burn MockETH tokens
 *
 * Usage:
 * export MOCK_ETH_ADDRESS=0x...
 * export BURN_AMOUNT=100000000000000000000 # 100 mETH
 * forge script script/InteractFaucet.s.sol:BurnMockETH --rpc-url <RPC_URL> --broadcast
 */
contract BurnMockETH is DeployHelper {
    function run() external {
        uint256 userPrivateKey = vm.envUint("PRIVATE_KEY");
        address mockETHAddress = vm.envAddress("MOCK_ETH_ADDRESS");
        uint256 burnAmount = vm.envUint("BURN_AMOUNT");

        MockETH mockETH = MockETH(mockETHAddress);

        vm.startBroadcast(userPrivateKey);

        address user = vm.addr(userPrivateKey);
        uint256 balanceBefore = mockETH.balanceOf(user);

        console.log("\n=== Burning MockETH ===");
        console.log("User:", user);
        console.log("Balance Before:", balanceBefore);
        console.log("Burning:", burnAmount);

        mockETH.burn(burnAmount);

        uint256 balanceAfter = mockETH.balanceOf(user);
        console.log("Balance After:", balanceAfter);
        console.log("Burned:", balanceBefore - balanceAfter);
        console.log("=====================\n");

        vm.stopBroadcast();
    }
}

/**
 * @title ClaimFromFaucet
 * @dev User claims tokens from TokenFaucet
 *
 * Usage:
 * export FAUCET_ADDRESS=0x...
 * forge script script/InteractFaucet.s.sol:ClaimFromFaucet --rpc-url <RPC_URL> --broadcast
 */
contract ClaimFromFaucet is DeployHelper {
    function run() external {
        address faucetAddress = vm.envAddress("FAUCET_ADDRESS");

        TokenFaucet faucet = TokenFaucet(faucetAddress);
        IERC20 token = faucet.token();

        vm.startBroadcast(deployer);

        console.log("\n=== Claiming from Faucet ===");
        console.log("User:", deployer);
        console.log("Faucet:", faucetAddress);

        // Check if can claim
        (bool canClaim, string memory reason) = faucet.canUserClaim(deployer);
        if (!canClaim) {
            console.log("Cannot claim:", reason);
            vm.stopBroadcast();
            return;
        }

        uint256 balanceBefore = token.balanceOf(deployer);
        console.log("Balance Before:", balanceBefore);

        faucet.claim();

        uint256 balanceAfter = token.balanceOf(deployer);
        console.log("Balance After:", balanceAfter);
        console.log("Claimed:", balanceAfter - balanceBefore);
        console.log("==========================\n");

        vm.stopBroadcast();
    }
}

/**
 * @title DepositToTokenFaucet
 * @dev Owner deposits tokens into TokenFaucet
 *
 * Usage:
 * export FAUCET_ADDRESS=0x...
 * export DEPOSIT_AMOUNT=10000000000000000000000 # 10,000 tokens
 * forge script script/InteractFaucet.s.sol:DepositToTokenFaucet --rpc-url <RPC_URL> --broadcast
 */
contract DepositToTokenFaucet is DeployHelper {
    function run() external {
        address faucetAddress = vm.envAddress("FAUCET_ADDRESS");
        uint256 depositAmount = vm.envUint("DEPOSIT_AMOUNT");

        TokenFaucet faucet = TokenFaucet(faucetAddress);
        IERC20 token = faucet.token();

        // Get sender from broadcast (msg.sender in broadcast context)
        address sender = msg.sender;

        console.log("\n=== Depositing to Faucet ===");
        console.log("Faucet Address:", faucetAddress);
        console.log("Token Address:", address(token));
        console.log("Faucet Owner:", faucet.owner());
        console.log("Sender:", sender);
        console.log("Deposit Amount:", depositAmount);

        // Check balances before
        uint256 senderBalance = token.balanceOf(sender);
        console.log("\n=== Before Deposit ===");
        console.log("Sender Token Balance:", senderBalance);

        require(senderBalance >= depositAmount, "Insufficient token balance");
        require(faucet.owner() == sender, "Sender is not faucet owner");

        vm.startBroadcast();

        // Approve
        console.log("\nApproving", depositAmount, "tokens...");
        token.approve(faucetAddress, depositAmount);
        console.log("Approved successfully");

        // Check allowance
        uint256 allowance = token.allowance(sender, faucetAddress);
        console.log("Allowance:", allowance);

        // Deposit
        console.log("\nDepositing to faucet...");
        faucet.deposit(depositAmount);
        console.log("Deposited successfully!");

        // Check balances after
        console.log("\n=== After Deposit ===");
        console.log("Sender Token Balance:", token.balanceOf(sender));
        // Show info
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
 * @title GetFaucetInfo
 * @dev View faucet information
 *
 * Usage:
 * export FAUCET_ADDRESS=0x...
 * forge script script/InteractFaucet.s.sol:GetFaucetInfo --rpc-url <RPC_URL>
 */
contract GetFaucetInfo is DeployHelper {
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

/**
 * @title CheckUserClaimStatus
 * @dev Check if a user can claim from faucet
 *
 * Usage:
 * export FAUCET_ADDRESS=0x...
 * export USER_ADDRESS=0x...
 * forge script script/InteractFaucet.s.sol:CheckUserClaimStatus --rpc-url <RPC_URL>
 */
contract CheckUserClaimStatus is DeployHelper {
    function run() external view {
        address faucetAddress = vm.envAddress("FAUCET_ADDRESS");
        address userAddress = vm.envAddress("USER_ADDRESS");

        TokenFaucet faucet = TokenFaucet(faucetAddress);

        console.log("\n=== User Claim Status ===");
        console.log("User:", userAddress);
        console.log("Faucet:", faucetAddress);

        bool hasClaimed = faucet.hasUserClaimed(userAddress);
        console.log("Has Claimed:", hasClaimed);

        (bool canClaim, string memory reason) = faucet.canUserClaim(userAddress);
        console.log("Can Claim:", canClaim);
        if (!canClaim) {
            console.log("Reason:", reason);
        }
        console.log("========================\n");
    }
}

/**
 * @title UpdateFaucetClaimAmount
 * @dev Owner updates claim amount
 *
 * Usage:
 * export FAUCET_ADDRESS=0x...
 * export NEW_CLAIM_AMOUNT=200000000000000000000 # 200 tokens
 * forge script script/InteractFaucet.s.sol:UpdateFaucetClaimAmount --rpc-url <RPC_URL> --broadcast
 */
contract UpdateFaucetClaimAmount is DeployHelper {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address faucetAddress = vm.envAddress("FAUCET_ADDRESS");
        uint256 newClaimAmount = vm.envUint("NEW_CLAIM_AMOUNT");

        TokenFaucet faucet = TokenFaucet(faucetAddress);

        vm.startBroadcast(ownerPrivateKey);

        console.log("\n=== Updating Claim Amount ===");
        console.log("Current Claim Amount:", faucet.claimAmount());
        console.log("New Claim Amount:", newClaimAmount);

        faucet.setClaimAmount(newClaimAmount);

        console.log("Updated successfully!");
        console.log("Claim Amount:", faucet.claimAmount());
        console.log("============================\n");

        vm.stopBroadcast();
    }
}

/**
 * @title PauseFaucet
 * @dev Owner pauses the faucet
 *
 * Usage:
 * export FAUCET_ADDRESS=0x...
 * forge script script/InteractFaucet.s.sol:PauseFaucet --rpc-url <RPC_URL> --broadcast
 */
contract PauseFaucet is DeployHelper {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address faucetAddress = vm.envAddress("FAUCET_ADDRESS");

        TokenFaucet faucet = TokenFaucet(faucetAddress);

        vm.startBroadcast(ownerPrivateKey);

        console.log("\n=== Pausing Faucet ===");
        faucet.pause();
        console.log("Faucet paused!");
        console.log("Is Paused:", faucet.paused());
        console.log("====================\n");

        vm.stopBroadcast();
    }
}

/**
 * @title UnpauseFaucet
 * @dev Owner unpauses the faucet
 *
 * Usage:
 * export FAUCET_ADDRESS=0x...
 * forge script script/InteractFaucet.s.sol:UnpauseFaucet --rpc-url <RPC_URL> --broadcast
 */
contract UnpauseFaucet is DeployHelper {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address faucetAddress = vm.envAddress("FAUCET_ADDRESS");

        TokenFaucet faucet = TokenFaucet(faucetAddress);

        vm.startBroadcast(ownerPrivateKey);

        console.log("\n=== Unpausing Faucet ===");
        faucet.unpause();
        console.log("Faucet unpaused!");
        console.log("Is Paused:", faucet.paused());
        console.log("======================\n");

        vm.stopBroadcast();
    }
}

/**
 * @title GetMockETHInfo
 * @dev View MockETH token information
 *
 * Usage:
 * export MOCK_ETH_ADDRESS=0x...
 * forge script script/InteractFaucet.s.sol:GetMockETHInfo --rpc-url <RPC_URL>
 */
contract GetMockETHInfo is DeployHelper {
    function run() external view {
        address mockETHAddress = vm.envAddress("MOCK_ETH_ADDRESS");
        MockETH mockETH = MockETH(mockETHAddress);

        console.log("\n=== MockETH Info ===");
        console.log("Address:", mockETHAddress);
        console.log("Name:", mockETH.name());
        console.log("Symbol:", mockETH.symbol());
        console.log("Decimals:", mockETH.decimals());
        console.log("Total Supply:", mockETH.totalSupply());
        console.log("Owner:", mockETH.owner());
        console.log("===================\n");
    }
}
