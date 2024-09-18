const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const contractAddress = '0x1a6026a6b3b1a535cA5259e5feC0cDC2E7b3261D'; // StableCoins
const contractABIPath = './script/ABI/StableBondCoins.json';

const newMinterAddress = '0x049fCAB83597C4E6dC2331D945736A3009AE60B7'; // NFT Staking
const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

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