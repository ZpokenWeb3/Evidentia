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

    metadata = {
        value: 1000_000000,
        couponValue: 50_000000,
        issueTimestamp: 1704067200, // 2024-01-01
        expirationTimestamp: 1704067200 + 31536000,
        ISIN: "US1234567890"
    };

    const stringHash = ethers.keccak256(ethers.toUtf8Bytes(metadata.ISIN));
    const tokenId = BigInt(stringHash).toString();

    console.log("Metadata:", metadata);
    console.log("TokenId: ", tokenId);

    console.log('Minting tokens...');
    const mintToAddress = "0x7Df601525A53AbaD47C69E78ae151b6F96c59097";
    const mintAmount = 10 
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