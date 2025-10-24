// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title BoolToken
 * @notice Boolean Platform Token - ERC20 token with burn capability
 * @dev Migrated from managed_platform_token.move
 *
 * Features:
 * - Mintable (only owner)
 * - Burnable (users can burn their own tokens)
 * - ERC20Permit (gasless approvals)
 * - Max supply control
 */
contract BoolToken is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Max supply (optional, 0 = unlimited)
    uint256 public maxSupply;

    /// @notice Minting enabled flag
    bool public mintingEnabled;

    /// @notice System paused flag
    bool public paused;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event TokenMinted(address indexed to, uint256 amount, uint256 newSupply);
    event TokenBurned(address indexed from, uint256 amount, uint256 newSupply);
    event ConfigUpdated(bool mintingEnabled, bool paused);
    event MaxSupplyUpdated(uint256 newMaxSupply);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error Paused();
    error MintingNotEnabled();
    error MaxSupplyExceeded();
    error InvalidAmount();
    error InvalidMaxSupply();

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Initialize BoolToken
     * @param initialOwner Address of owner
     * @param _maxSupply Maximum supply (0 = unlimited)
     */
    constructor(
        address initialOwner,
        uint256 _maxSupply
    )
        ERC20("Boolean Platform Token", "BOOL")
        Ownable(initialOwner)
        ERC20Permit("Boolean Platform Token")
    {
        maxSupply = _maxSupply;
        mintingEnabled = true;
        paused = false;
    }

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    // ========================================================================
    // MINT FUNCTIONS
    // ========================================================================

    /**
     * @notice Mint tokens (only owner)
     * @param to Address to receive tokens
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyOwner whenNotPaused {
        if (!mintingEnabled) revert MintingNotEnabled();
        if (amount == 0) revert InvalidAmount();

        // Check max supply if set
        if (maxSupply > 0) {
            if (totalSupply() + amount > maxSupply) revert MaxSupplyExceeded();
        }

        _mint(to, amount);

        emit TokenMinted(to, amount, totalSupply());
    }

    // ========================================================================
    // BURN FUNCTIONS
    // ========================================================================

    /**
     * @notice Burn tokens from caller
     * @param amount Amount to burn
     * @dev Override from ERC20Burnable to add event
     */
    function burn(uint256 amount) public override whenNotPaused {
        super.burn(amount);
        emit TokenBurned(msg.sender, amount, totalSupply());
    }

    /**
     * @notice Burn tokens from another account (with approval)
     * @param account Address to burn from
     * @param amount Amount to burn
     * @dev Override from ERC20Burnable to add event
     */
    function burnFrom(
        address account,
        uint256 amount
    ) public override whenNotPaused {
        super.burnFrom(account, amount);
        emit TokenBurned(account, amount, totalSupply());
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update config
     * @param _mintingEnabled Enable/disable minting
     * @param _paused Pause/unpause system
     */
    function updateConfig(
        bool _mintingEnabled,
        bool _paused
    ) external onlyOwner {
        mintingEnabled = _mintingEnabled;
        paused = _paused;

        emit ConfigUpdated(_mintingEnabled, _paused);
    }

    /**
     * @notice Update max supply (can only increase)
     * @param newMaxSupply New max supply
     */
    function updateMaxSupply(uint256 newMaxSupply) external onlyOwner {
        if (maxSupply > 0 && newMaxSupply < maxSupply) {
            revert InvalidMaxSupply();
        }
        if (newMaxSupply < totalSupply()) {
            revert InvalidMaxSupply();
        }

        maxSupply = newMaxSupply;
        emit MaxSupplyUpdated(newMaxSupply);
    }

    /**
     * @notice Emergency pause
     */
    function emergencyPause() external onlyOwner {
        paused = true;
        emit ConfigUpdated(mintingEnabled, true);
    }

    /**
     * @notice Unpause
     */
    function unpause() external onlyOwner {
        paused = false;
        emit ConfigUpdated(mintingEnabled, false);
    }

    // ========================================================================
    // OVERRIDE FUNCTIONS
    // ========================================================================

    /**
     * @notice Override transfer to check pause
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override whenNotPaused {
        super._update(from, to, value);
    }
}
