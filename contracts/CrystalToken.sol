// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract CrystalToken {
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

    string public name;
    string public symbol;
    TokenMetaData public metadata;

    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1000000000000000000000000000;

    address public immutable crystal;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(
        address _crystal,
        string memory _name,
        string memory _symbol,
        string memory _metadataCID,
        string memory _description,
        string memory _social1,
        string memory _social2,
        string memory _social3,
        string memory _social4
    ) {
        crystal = _crystal;
        name = _name;
        symbol = _symbol;
        metadata = TokenMetaData(_name, _symbol, _metadataCID, _description, _social1, _social2, _social3, _social4);
        balanceOf[_crystal] += totalSupply;
        emit Transfer(address(0), _crystal, totalSupply);
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function _approve(address owner, address spender, uint256 value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) private {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max && msg.sender != crystal) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'expired');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'invalid signature');
        _approve(owner, spender, value);
    }
}