const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

// Environment variables
const bondNFTAddress = process.env.BOND_NFT_PROXY_ADDRESS; // BondNFT
const contractABIPath = './script/ABI/BondNFT.json';
const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

// Validate environment variables
if (!bondNFTAddress || !privateKey || !rpcUrl) {
  console.error('Error: Missing required environment variables (BOND_NFT_PROXY_ADDRESS, PRIVATE_KEY, SEPOLIA_RPC_URL)');
  process.exit(1);
}

// Validate bondNFTAddress
if (!ethers.isAddress(bondNFTAddress)) {
  console.error('Error: BOND_NFT_PROXY_ADDRESS must be a valid Ethereum address');
  process.exit(1);
}

// Load contract ABI
const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

// Get command-line arguments
const [, , tokenId, mintAmount] = process.argv;

// Validate arguments
if (!tokenId || !mintAmount) {
  console.error('Usage: node script/07_mint_nft.js <tokenId> <mintAmount>');
  console.error('Example: node script/07_mint_nft.js 75955146522550863186049403197281544413786813629915328080343312216854220103147 10');
  process.exit(1);
}

// Parse mintAmount to integer
const mintAmountInt = parseInt(mintAmount, 10);
if (isNaN(mintAmountInt) || mintAmountInt <= 0) {
  console.error('Error: mintAmount must be a positive integer');
  process.exit(1);
}

async function mintNft() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const bondNFT = new ethers.Contract(bondNFTAddress, contractABI, wallet);

    console.log(`Minting ${mintAmountInt} tokens for tokenId ${tokenId}...`);
    // Mint to the msg.sender
    const tx = await bondNFT.mint(tokenId, mintAmountInt, ethers.toUtf8Bytes(""));
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

mintNft();
