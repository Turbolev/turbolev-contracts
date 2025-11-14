// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IBaseOracle
 * @notice Base interface for all oracle types
 * @dev Common interface that all oracles must implement
 */
interface IBaseOracle {
    /**
     * @notice Oracle type enum
     */
    enum OracleType {
        PUSH, // Push oracle: prices are pushed on-chain regularly
        PULL // Pull oracle: prices need to be updated before reading

    }

    /**
     * @notice Get oracle type
     * @return oracleType Type of oracle (PUSH or PULL)
     */
    function getOracleType() external view returns (OracleType oracleType);

    /**
     * @notice Check if oracle supports both push and pull modes
     * @return supported True if oracle supports both modes
     */
    function supportsHybridMode() external view returns (bool supported);

    /**
     * @notice Get oracle version
     * @return version Version string
     */
    function version() external pure returns (string memory);
}
