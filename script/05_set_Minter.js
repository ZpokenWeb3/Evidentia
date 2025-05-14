const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// Determine which env file to use based on NODE_ENV
const network = process.env.NODE_ENV || 'sepolia';
const envFile = network === 'mainnet' ? '.env_mainnet' : '.env';

// Load the appropriate env file
require('dotenv').config({ path: path.resolve(process.cwd(), envFile) });

const contractAddress = process.env.STABLES_PROXY_ADDRESS; // StableCoins
const contractABIPath = './script/ABI/StableBondCoins.json';

const newMinterAddress = process.env.NFT_STAKING_PROXY_ADDRESS; // NFT Staking
const privateKey = process.env.PRIVATE_KEY;
// Use the appropriate RPC URL based on the network
const rpcUrl = network === 'mainnet' ? process.env.MAINNET_RPC_URL : process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function grantMinterRole() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(contractAddress, contractABI, wallet);

    const minterRole = ethers.keccak256(ethers.toUtf8Bytes('MINTER_ROLE'));

    console.log('Granting minter role...');
    const tx = await contract.grantRole(minterRole, newMinterAddress);
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
  }
}

grantMinterRole();
