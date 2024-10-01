const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const contractAddress = '0xc745ffdF5cE0F277a0d42EDD07FaFbE8d57be0F4'; // BondNFT
const contractABIPath = './script/ABI/BondNFT.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function approveNft() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(contractAddress, contractABI, wallet);

    console.log('Approving NFT...');
    const toAddress = "0x5fc677Bec2ccF1E4fDb3b621AC5ae7CD7AaA7EA5"; // NFT Staking
    const tx = await contract.setApprovalForAll(toAddress, true);
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
  }
}

approveNft();