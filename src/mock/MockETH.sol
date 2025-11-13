// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockETH
 * @dev Mock ETH token for testing purposes
 *
 * Features:
 * - ERC20 standard token
 * - Burnable: Users can burn their own tokens
 * - Mintable: Owner can mint new tokens
 * - 18 decimals (same as ETH)
 *
 * This is a test token that simulates ETH behavior for development and testing
 */
contract MockETH is ERC20, ERC20Burnable, Ownable {
    /**
     * @dev Constructor
     * @param initialSupply Initial supply to mint to deployer (in wei, 18 decimals)
     */
    constructor(uint256 initialSupply) ERC20("Mock Ethereum", "ETH") Ownable(msg.sender) {
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    /**
     * @dev Mint new tokens (owner only)
     * @param to Address to receive minted tokens
     * @param amount Amount of tokens to mint (in wei)
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Batch mint to multiple addresses (owner only)
     * @param recipients Array of addresses to receive tokens
     * @param amounts Array of amounts to mint (must match recipients length)
     */
    function batchMint(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyOwner
    {
        require(recipients.length == amounts.length, "MockETH: arrays length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /**
     * @dev Faucet function for easy testing
     * @param to Address to receive tokens
     * Mints 10 ETH to the specified address
     */
    function faucet(address to) external {
        _mint(to, 10 ether);
    }

    /**
     * @dev Public faucet for msg.sender
     * Mints 10 ETH to caller
     */
    function faucet() external {
        _mint(msg.sender, 10 ether);
    }
}
