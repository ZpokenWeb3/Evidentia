const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const contractAddress = '0xc745ffdF5cE0F277a0d42EDD07FaFbE8d57be0F4'; // BondNFT
const contractABIPath = './script/ABI/BondNFT.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function mintAllowance() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(contractAddress, contractABI, wallet);

    const timestamp = provider.getBlock("latest").timestamp;

    const tokenId = "68364407216462399799028636857268510032958042329620656293310648714915379830340";

    console.log('Set allowance for minting tokens...');
    const allowToAddress = "0x7Df601525A53AbaD47C69E78ae151b6F96c59097";
    const mintAmount = 100;
    const tx = await contract.setAllowedMints(allowToAddress, tokenId, mintAmount);
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
  }
}

mintAllowance();