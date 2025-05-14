const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const bondNFTAddress = process.env.BOND_NFT_PROXY_ADDRESS; // BondNFT
const contractABIPath = './script/ABI/BondNFT.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function approveNft() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const bondNFT = new ethers.Contract(bondNFTAddress, contractABI, wallet);

    console.log('Approving NFT...');
    const toAddress = process.env.NFT_STAKING_PROXY_ADDRESS; // NftStakingAndBorrowing
    const tx = await bondNFT.setApprovalForAll(toAddress, true);
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
