const { ethers, MaxInt256 } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const contractAddress = process.env.STABLES_PROXY_ADDRESS; // StableBondCoins
const contractABIPath = './script/ABI/StableBondCoins.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

const gasLimit = process.env.GAS_LIMIT || 200_000;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function approveStables() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(contractAddress, contractABI, wallet);

    console.log('Approving Stables...');
    const amount = MaxInt256;
    const spender = process.env.STABLES_STAKING_PROXY_ADDRESS; // StableCoinsStaking
    const tx = await contract.approve(spender, amount, { gasLimit });
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
