const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

const contractAddress = '0x049fCAB83597C4E6dC2331D945736A3009AE60B7'; // NftStaking
const contractABIPath = './script/ABI/NFTStakingAndBorrowing.json';

const privateKey = process.env.PRIVATE_KEY;
const rpcUrl = process.env.SEPOLIA_RPC_URL;

const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

async function unstakeNft() {
  try {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    const contract = new ethers.Contract(contractAddress, contractABI, wallet);

    const bondNFT = "0xAc946D4eb88372446Dd658e358998236577179b7";
    const tokenId = "39261504401888043025286050630110397838656180042608236818960059268782563931973"

    console.log("TokenId: ", tokenId);

    console.log('Staking NFTs...');
    const amount = 10;
    const tx = await contract.unstakeNFT(bondNFT, tokenId, amount);
    console.log(`Transaction hash: ${tx.hash}`);

    const receipt = await tx.wait();
    console.log('Transaction confirmed');
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`Block number: ${receipt.blockNumber}`);

  } catch (error) {
    console.error(`Error: ${error.message}`);
  }
}

unstakeNft();