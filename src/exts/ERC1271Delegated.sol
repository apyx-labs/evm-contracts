// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EInvalidAddress} from "../errors/InvalidAddress.sol";

/**
 * @title ERC1271Delegated
 * @notice Abstract contract that implements ERC-1271 by delegating signature validation to a stored delegate
 * @dev Inheriting contracts set the delegate in the constructor. Uses OpenZeppelin's SignatureChecker
 *      so the delegate may be an EOA (ECDSA) or a contract (ERC-1271). See EIP-1271 and
 *      OpenZeppelin SignatureChecker documentation.
 */
abstract contract ERC1271Delegated is IERC1271, EInvalidAddress {
    /// @notice Address that is allowed to sign on behalf of this contract (e.g. Foundation multisig)
    address public signingDelegate;

    /// @notice ERC-1271 magic value returned when the signature is valid
    bytes4 private constant _ERC1271_MAGIC = IERC1271.isValidSignature.selector;

    /// @notice Value returned when the signature is invalid (per EIP-1271)
    bytes4 private constant _ERC1271_INVALID = 0xffffffff;

    /**
     * @notice Sets the signature delegate
     * @param _signingDelegate Address that may sign on behalf of this contract
     */
    constructor(address _signingDelegate) {
        if (_signingDelegate == address(0)) revert InvalidAddress("signingDelegate");
        signingDelegate = _signingDelegate;
    }

    /**
     * @notice Validates a signature by delegating to the stored delegate via SignatureChecker
     * @param hash Hash of the data that was signed
     * @param signature Signature bytes to validate
     * @return magicValue ERC-1271 magic value (0x1626ba7e) if valid, 0xffffffff if invalid
     */
    function isValidSignature(bytes32 hash, bytes calldata signature)
        public
        view
        virtual
        override
        returns (bytes4 magicValue)
    {
        if (signingDelegate == address(0)) revert InvalidAddress("signingDelegate");

        if (SignatureChecker.isValidSignatureNowCalldata(signingDelegate, hash, signature)) {
            return _ERC1271_MAGIC;
        }
        return _ERC1271_INVALID;
    }
}
