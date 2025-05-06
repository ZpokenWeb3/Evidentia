const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const contractAddress = process.env.NFT_STAKING_PROXY_ADDRESS; // NftStaking
const contractABIPath = './script/ABI/NFTStakingAndBorrowing.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function setStablesStaking() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(contractAddress, contractABI, wallet);

    const stablesStakingAddress = process.env.STABLES_STAKING_PROXY_ADDRESS;

    console.log('Setting stables staking contract...');
    const tx = await contract.setStablesStakingAddress(stablesStakingAddress);
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
