const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const contractAddress = "0x9A5F44F0161F9A897e2C2c3f54F24841324B62B3" // Stables Staking
const contractABIPath = './script/ABI/StableCoinsStaking.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function stakeStables() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(contractAddress, contractABI, wallet);

    console.log('Staking Stables...');
    const amount = 1000_000000;
    const tx = await contract.stake(amount, {gasLimit: 500_000});
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
  }
}

stakeStables();