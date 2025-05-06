const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const bondNFTAddress = process.env.BOND_NFT_PROXY_ADDRESS; // BondNFT
const contractABIPath = './script/ABI/BondNFT.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function setMetadata() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(bondNFTAddress, contractABI, wallet);

    const timestamp = provider.getBlock("latest").timestamp;

    metadata = {
        value: 1000_000000,
        couponValue: 88_000000,
        issueTimestamp: 1707688800, // 13.02.2024
        expirationTimestamp: 1769551200, // 28.01.2026
        ISIN: "UA4000230262"
    };

    const stringHash = ethers.keccak256(ethers.toUtf8Bytes(metadata.ISIN));
    const tokenId = BigInt(stringHash).toString();

    console.log("Metadata:", metadata);
    console.log("TokenId: ", tokenId);

    console.log('Setting metadata...');
    const tx = await contract.setMetaData(tokenId, metadata);
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
  }
}

setMetadata();
