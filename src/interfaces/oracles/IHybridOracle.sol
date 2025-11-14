// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./IPushOracle.sol";
import "./IPullOracle.sol";

/**
 * @title IHybridOracle
 * @notice Interface for oracles supporting both Push and Pull modes
 * @dev Combines both IPushOracle and IPullOracle interfaces
 * @dev Examples: Pyth Network (can work as both push and pull)
 */
interface IHybridOracle is IPushOracle, IPullOracle {
    /**
     * @notice Get current operating mode
     * @return mode Current oracle mode (PUSH or PULL)
     */
    function getCurrentMode() external view returns (OracleType mode);

    /**
     * @notice Check if feed supports pull mode
     * @param feed Oracle feed address
     * @return supported True if pull mode is supported for this feed
     */
    function supportsPullMode(address feed) external view returns (bool supported);

    // Override functions to resolve ambiguity from multiple inheritance

    /**
     * @notice Get latest price from oracle
     * @dev Inherited from both IPushOracle and IPullOracle - must be overridden
     */
    function getPrice(address feed)
        external
        view
        override(IPushOracle, IPullOracle)
        returns (int256 price, uint256 updatedAt);

    /**
     * @notice Check if price is stale
     * @dev Inherited from both IPushOracle and IPullOracle - must be overridden
     */
    function isPriceStale(address feed, uint256 maxAge)
        external
        view
        override(IPushOracle, IPullOracle)
        returns (bool isStale);
}
