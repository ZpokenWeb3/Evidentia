const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

// Environment variables
const nftStakingAndBorrowingAddress = process.env.NFT_STAKING_PROXY_ADDRESS; // NftStakingAndBorrowing
const bondNFTAddress = process.env.BOND_NFT_PROXY_ADDRESS; // BondNFT
const contractABIPath = './script/ABI/NFTStakingAndBorrowing.json';
const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

// Validate environment variables
if (!nftStakingAndBorrowingAddress || !bondNFTAddress || !privateKey || !rpcUrl) {
  console.error('Error: Missing required environment variables (NFT_STAKING_PROXY_ADDRESS, BOND_NFT_PROXY_ADDRESS, PRIVATE_KEY, SEPOLIA_RPC_URL)');
  process.exit(1);
}

// Validate addresses
if (!ethers.isAddress(nftStakingAndBorrowingAddress)) {
  console.error('Error: NFT_STAKING_PROXY_ADDRESS must be a valid Ethereum address');
  process.exit(1);
}
if (!ethers.isAddress(bondNFTAddress)) {
  console.error('Error: BOND_NFT_PROXY_ADDRESS must be a valid Ethereum address');
  process.exit(1);
}

// Load contract ABI
const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

// Get command-line arguments
const [, , tokenId, amount] = process.argv;

// Validate arguments
if (!tokenId || !amount) {
  console.error('Usage: node script/10_unstake_nft.js <tokenId> <amount>');
  console.error('Example: node script/10_unstake_nft.js 75955146522550863186049403197281544413786813629915328080343312216854220103147 10');
  process.exit(1);
}

// Validate amount
const amountInt = parseInt(amount, 10);
if (isNaN(amountInt) || amountInt <= 0) {
  console.error('Error: amount must be a positive integer');
  process.exit(1);
}

async function unstakeNft() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const nftStakingAndBorrowing = new ethers.Contract(nftStakingAndBorrowingAddress, contractABI, wallet);

    console.log(`Unstaking ${amountInt} NFTs for tokenId ${tokenId} with BondNFT address ${bondNFTAddress}...`);

    const tx = await nftStakingAndBorrowing.unstakeNFT(bondNFTAddress, tokenId, amountInt);
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

unstakeNft();
