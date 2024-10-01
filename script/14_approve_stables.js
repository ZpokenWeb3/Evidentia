const { ethers, MaxInt256 } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const contractAddress = '0xbDBc6f32699c39DF208595BfC7Dfb96C6F837aBE'; // StableBond Coins
const contractABIPath = './script/ABI/StableBondCoins.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function approveStables() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(contractAddress, contractABI, wallet);

    console.log('Approving Stables...');
    const amount = MaxInt256;
    const spender = "0x9A5F44F0161F9A897e2C2c3f54F24841324B62B3" // Stables Staking
    const tx = await contract.approve(spender, amount, {gasLimit: 200_000});
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
  }
}

approveStables();