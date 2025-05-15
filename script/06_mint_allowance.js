const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// Determine which env file to use based on NODE_ENV
const network = process.env.NODE_ENV || 'sepolia';
const envFile = network === 'mainnet' ? '.env_mainnet' : '.env';

// Load the appropriate env file
require('dotenv').config({ path: path.resolve(process.cwd(), envFile) });

// Contract configuration
const bondNFTAddress = process.env.BOND_NFT_PROXY_ADDRESS; // BondNFT
const contractABIPath = './script/ABI/BondNFT.json';

// Wallet and provider configuration
const privateKey = process.env.PRIVATE_KEY;
// Use the appropriate RPC URL based on the network
const rpcUrl = network === 'mainnet' ? process.env.MAINNET_RPC_URL : process.env.SEPOLIA_RPC_URL;

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
const [, , allowToAddress, tokenId, mintAmount] = process.argv;

// Validate arguments
if (!allowToAddress || !tokenId || !mintAmount) {
  console.error('Usage: node script/06_mint_allowance.js <allowToAddress> <tokenId> <mintAmount>');
  console.error('Example: node script/06_mint_allowance.js 0xC85906530Df2D4227f713CFCDD08085309A4f821 75955146522550863186049403197281544413786813629915328080343312216854220103147 1000');
  process.exit(1);
}

// Validate allowToAddress
if (!ethers.isAddress(allowToAddress)) {
  console.error('Error: allowToAddress must be a valid Ethereum address');
  process.exit(1);
}

// Validate mintAmount
const mintAmountInt = parseInt(mintAmount, 10);
if (isNaN(mintAmountInt) || mintAmountInt <= 0) {
  console.error('Error: mintAmount must be a positive integer');
  process.exit(1);
}

async function mintAllowance() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const bondNFT = new ethers.Contract(bondNFTAddress, contractABI, wallet);

    console.log(`Setting allowance of ${mintAmountInt} tokens for tokenId ${tokenId} to address ${allowToAddress}...`);

    const tx = await bondNFT.setAllowedMints(allowToAddress, tokenId, mintAmountInt);
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
    console.error('Full error:', error);
    process.exit(1);
  }
}

mintAllowance();
