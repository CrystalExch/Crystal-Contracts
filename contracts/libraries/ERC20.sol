// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract ERC20 {
    /// @notice Token name.
    string public name;

    /// @notice Token symbol.
    string public symbol;

    /// @notice ERC20 decimals.
    uint8 public constant decimals = 18;

    /// @notice ERC20 total supply.
    uint256 public totalSupply;

    /// @notice Account balances.
    mapping(address => uint256) public balanceOf;

    /// @notice Allowances mapping.
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice EIP-712 domain separator for permit signatures.
    bytes32 public DOMAIN_SEPARATOR;

    /// @notice EIP-2612 permit type hash.
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /// @notice Nonces tracked per owner for permit replay protection.
    mapping(address => uint256) public nonces;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @notice Initializes the ERC20 token with a `name` and `symbol`.
     *
     * @param _name Token name.
     * @param _symbol Token symbol.
     */
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"), keccak256(bytes(_name)), keccak256(bytes("1")), chainId, address(this)));
    }

    /**
     * @notice Internal helper to mint tokens to an address and increase total supply.
     *
     * @param to Recipient address.
     * @param value Amount to mint.
     */
    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    /**
     * @notice Internal helper to burn tokens from an address and decrease total supply.
     *
     * @param from Address to burn tokens from.
     * @param value Amount to burn.
     */
    function _burn(address from, uint256 value) internal {
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    /**
     * @notice Internal helper to set an allowance and emit an Approval event.
     *
     * @param owner Owner of the tokens.
     * @param spender Spender being approved.
     * @param value Allowance amount.
     */
    function _approve(address owner, address spender, uint256 value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /**
     * @notice Internal helper to move tokens between accounts and emit a Transfer event.
     *
     * @param from Sender address.
     * @param to Recipient address.
     * @param value Amount to transfer.
     */
    function _transfer(address from, address to, uint256 value) internal {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    /**
     * @notice Approves a spender to transfer the caller's tokens.
     *
     * @param spender Address allowed to spend tokens.
     * @param value Allowance amount.
     *
     * @return success True if the approval succeeded.
     */
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /**
     * @notice Transfers tokens from the caller to another address.
     *
     * @param to Recipient address.
     * @param value Amount to transfer.
     *
     * @return success True if the transfer succeeded.
     */
    function transfer(address to, uint256 value) external virtual returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @notice Transfers tokens from one address to another using allowance.
     *
     * @param from Address to debit.
     * @param to Recipient address.
     * @param value Amount to transfer.
     *
     * @return success True if the transfer succeeded.
     */
    function transferFrom(address from, address to, uint256 value) external virtual returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    /**
     * @notice Sets an allowance via EIP-2612 permit signature.
     *
     * @param owner Token owner signing the approval.
     * @param spender Spender being approved.
     * @param value Allowance amount.
     * @param deadline Expiration timestamp for the signature.
     * @param v Signature recovery byte.
     * @param r Signature r value.
     * @param s Signature s value.
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, "expired");
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))));
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "invalid signature");
        _approve(owner, spender, value);
    }
}