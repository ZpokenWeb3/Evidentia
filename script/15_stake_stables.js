const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

// Environment variables
const stableCoinsStakingAddress = process.env.STABLES_STAKING_PROXY_ADDRESS; // StableCoinsStaking
const contractABIPath = './script/ABI/StableCoinsStaking.json';
const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;
const gasLimit = process.env.GAS_LIMIT || 500_000;

// Validate environment variables
if (!stableCoinsStakingAddress || !privateKey || !rpcUrl) {
  console.error('Error: Missing required environment variables (STABLES_STAKING_PROXY_ADDRESS, PRIVATE_KEY, SEPOLIA_RPC_URL)');
  process.exit(1);
}

// Validate stableCoinsStakingAddress
if (!ethers.isAddress(stableCoinsStakingAddress)) {
  console.error('Error: STABLES_STAKING_PROXY_ADDRESS must be a valid Ethereum address');
  process.exit(1);
}

// Load contract ABI
const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

// Get command-line arguments
const [, , amount] = process.argv;

// Validate arguments
if (!amount) {
  console.error('Usage: node script/15_stake_stables.js <amount>');
  console.error('Example: node script/15_stake_stables.js 1000000000');
  process.exit(1);
}

// Validate amount
const amountInt = parseInt(amount, 10);
if (isNaN(amountInt) || amountInt <= 0) {
  console.error('Error: amount must be a positive integer');
  process.exit(1);
}

async function stakeStables() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const stableCoinsStaking = new ethers.Contract(stableCoinsStakingAddress, contractABI, wallet);

    console.log(`Staking ${amountInt} stables to contract ${stableCoinsStakingAddress}...`);

    const tx = await stableCoinsStaking.stake(amountInt, { gasLimit });
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

stakeStables();
