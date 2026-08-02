// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "../libraries/ERC20.sol";

/**
 * @title CrystalToken
 * @author Crystal Labs
 *
 * @notice
 * Fixed-supply ERC20 with EIP-2612 permit support created through Crystal's launchpad.
 *
 * @dev
 * - The entire supply is minted upon creation to the launchpad.
 * - An automatic infinite approval is granted to the core protocol for ease of use.
 */
contract CrystalToken is ERC20 {
    /// @notice Metadata describing the token and its external references.
    struct TokenMetaData {
        string name;
        string symbol;
        string metadataCID;
        string description;
        string social1;
        string social2;
        string social3;
        string social4;
    }

    /// @notice Off-chain metadata used for UI and discovery.
    TokenMetaData public metadata;

    /// @notice Crystal core contract that receives the initial supply.
    address public immutable crystal;

    /**
     * @notice Deploys the Crystal token and mints the full supply to the Crystal core.
     *
     * @param _crystal Address of the Crystal core contract.
     * @param _name Token name.
     * @param _symbol Token symbol.
     * @param _metadataCID Off-chain metadata CID.
     * @param _description Token description.
     * @param _social1 Primary social link.
     * @param _social2 Secondary social link.
     * @param _social3 Tertiary social link.
     * @param _social4 Quaternary social link.
     */
    constructor(address _crystal, string memory _name, string memory _symbol, string memory _metadataCID, string memory _description, string memory _social1, string memory _social2, string memory _social3, string memory _social4) ERC20(_name, _symbol) {
        crystal = _crystal;
        metadata = TokenMetaData(_name, _symbol, _metadataCID, _description, _social1, _social2, _social3, _social4);
        _mint(_crystal, 1000000000000000000000000000);
    }

    /**
     * @notice Transfers tokens from one address to another using allowance.
     *
     * @dev The Crystal core can bypass allowance checks for protocol-driven flows.
     *
     * @param from Address to debit.
     * @param to Recipient address.
     * @param value Amount to transfer.
     *
     * @return success True if the transfer succeeded.
     */
    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max && msg.sender != crystal) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }
}