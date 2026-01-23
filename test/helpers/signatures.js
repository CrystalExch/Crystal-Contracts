const { ethers } = require("hardhat");

/**
 * Sign a permit message for ERC20 permit function
 * @param {ethers.Signer} wallet - Wallet to sign with
 * @param {string} tokenAddress - Token contract address
 * @param {string} tokenName - Token name for domain
 * @param {string} spender - Address to approve
 * @param {bigint} value - Amount to approve
 * @param {bigint} nonce - Current nonce
 * @param {bigint} deadline - Permit deadline timestamp
 * @param {bigint} chainId - Chain ID
 * @returns {Object} - Signature components {v, r, s}
 */
async function signPermit(wallet, tokenAddress, tokenName, spender, value, nonce, deadline, chainId) {
  const domain = {
    name: tokenName,
    version: "1",
    chainId: chainId,
    verifyingContract: tokenAddress,
  };

  const types = {
    Permit: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };

  const message = {
    owner: await wallet.getAddress(),
    spender: spender,
    value: value,
    nonce: nonce,
    deadline: deadline,
  };

  const signature = await wallet.signTypedData(domain, types, message);
  const { v, r, s } = ethers.Signature.from(signature);

  return { v, r, s };
}

/**
 * Get domain separator for a token
 * @param {string} name - Token name
 * @param {string} tokenAddress - Token contract address
 * @param {bigint} chainId - Chain ID
 * @returns {string} - Domain separator hash
 */
function getDomainSeparator(name, tokenAddress, chainId) {
  return ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["bytes32", "bytes32", "bytes32", "uint256", "address"],
      [
        ethers.keccak256(ethers.toUtf8Bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")),
        ethers.keccak256(ethers.toUtf8Bytes(name)),
        ethers.keccak256(ethers.toUtf8Bytes("1")),
        chainId,
        tokenAddress,
      ]
    )
  );
}

/**
 * Get permit typehash
 * @returns {string} - Permit typehash
 */
function getPermitTypehash() {
  return ethers.keccak256(
    ethers.toUtf8Bytes("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
  );
}

/**
 * Create an expired deadline (1 second ago from blockchain time)
 * @returns {bigint} - Expired timestamp
 */
async function getExpiredDeadline() {
  const block = await ethers.provider.getBlock("latest");
  return BigInt(block.timestamp - 1);
}

/**
 * Create a valid deadline (1 hour from now based on blockchain time)
 * @returns {bigint} - Valid future timestamp
 */
async function getValidDeadline() {
  const block = await ethers.provider.getBlock("latest");
  return BigInt(block.timestamp + 3600);
}

/**
 * Create an invalid signature (wrong signer)
 * @param {ethers.Signer} wrongWallet - Wrong wallet to sign with
 * @param {string} tokenAddress - Token contract address
 * @param {string} tokenName - Token name
 * @param {string} owner - Actual owner address
 * @param {string} spender - Spender address
 * @param {bigint} value - Amount
 * @param {bigint} nonce - Nonce
 * @param {bigint} deadline - Deadline
 * @param {bigint} chainId - Chain ID
 * @returns {Object} - Invalid signature components
 */
async function signPermitWithWrongSigner(wrongWallet, tokenAddress, tokenName, owner, spender, value, nonce, deadline, chainId) {
  const domain = {
    name: tokenName,
    version: "1",
    chainId: chainId,
    verifyingContract: tokenAddress,
  };

  const types = {
    Permit: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };

  const message = {
    owner: owner,
    spender: spender,
    value: value,
    nonce: nonce,
    deadline: deadline,
  };

  const signature = await wrongWallet.signTypedData(domain, types, message);
  const { v, r, s } = ethers.Signature.from(signature);

  return { v, r, s };
}

/**
 * Create a malformed signature
 * @returns {Object} - Malformed signature components
 */
function getMalformedSignature() {
  return {
    v: 27,
    r: ethers.zeroPadValue("0x1234", 32),
    s: ethers.zeroPadValue("0x5678", 32),
  };
}

module.exports = {
  signPermit,
  getDomainSeparator,
  getPermitTypehash,
  getExpiredDeadline,
  getValidDeadline,
  signPermitWithWrongSigner,
  getMalformedSignature,
};
