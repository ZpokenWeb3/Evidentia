const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// Determine which env file to use based on NODE_ENV
const network = process.env.NODE_ENV || 'sepolia';
const envFile = network === 'mainnet' ? '.env_mainnet' : '.env';

// Load the appropriate env file
require('dotenv').config({ path: path.resolve(process.cwd(), envFile) });

const nftStakingAndBorrowingAddress = process.env.NFT_STAKING_PROXY_ADDRESS; // NftStakingAndBorrowing
const contractABIPath = './script/ABI/NFTStakingAndBorrowing.json';

const privateKey = process.env.PRIVATE_KEY;
// Use the appropriate RPC URL based on the network
const rpcUrl = network === 'mainnet' ? process.env.MAINNET_RPC_URL : process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function setStablesStaking() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const nftStakingAndBorrowing = new ethers.Contract(nftStakingAndBorrowingAddress, contractABI, wallet);

    const stablesStakingAddress = process.env.STABLES_STAKING_PROXY_ADDRESS;

    console.log('Setting stables staking contract...');
    const tx = await nftStakingAndBorrowing.setStablesStakingAddress(stablesStakingAddress);
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
  }
}

setStablesStaking();
