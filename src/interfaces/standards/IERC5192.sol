// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IERC5192
 * @notice Minimal Soulbound NFT interface (EIP-5192).
 * @dev See https://eips.ethereum.org/EIPS/eip-5192
 */
interface IERC5192 {
    /// @notice Thrown by implementations that disallow approval and transfer operations.
    error Soulbound();

    /// @notice Emitted when the locking status of `tokenId` becomes locked.
    event Locked(uint256 indexed tokenId);

    /// @notice Emitted when the locking status of `tokenId` becomes unlocked.
    event Unlocked(uint256 indexed tokenId);

    /// @notice Returns the locking status of an existing tokenId.
    /// @param tokenId The token to query.
    /// @return Whether the token is locked.
    function locked(uint256 tokenId) external view returns (bool);
}
