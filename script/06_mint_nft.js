const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const contractAddress = '0xAc946D4eb88372446Dd658e358998236577179b7'; // BondNFT
const contractABIPath = './script/ABI/BondNFT.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function mintNft() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(contractAddress, contractABI, wallet);

    const timestamp = provider.getBlock("latest").timestamp;

    const tokenId = "68364407216462399799028636857268510032958042329620656293310648714915379830340";

    console.log('Minting tokens...');
    const mintToAddress = "0xC85906530Df2D4227f713CFCDD08085309A4f821";
    const mintAmount = 10;
    const tx = await contract.mint(mintToAddress, tokenId, mintAmount, ethers.toUtf8Bytes(""));
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
  }
}

mintNft();