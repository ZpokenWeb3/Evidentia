// Usage: node script/bridge/js/checkTronBalance.js

require('dotenv').config();
const { TronWeb } = require('tronweb');

async function main() {
  // Setup TronWeb instance
  const tronWeb = new TronWeb({
    fullHost: 'https://api.shasta.trongrid.io', // Shasta testnet
    privateKey: process.env.TRON_PRIVATE_KEY
  });

  // Get address from private key
  const address = tronWeb.address.fromPrivateKey(process.env.TRON_PRIVATE_KEY);
  console.log(`Checking balance for address: ${address}`);

  // Get OFT token contract instance
  const tokenAddress = process.env.TRON_OFT_TOKEN_BASE58_ADDRESS;
  if (!tokenAddress) {
    throw new Error('TRON_OFT_TOKEN_BASE58_ADDRESS not found in .env file');
  }

  console.log(`Token contract address: ${tokenAddress}`);
  const contract = await tronWeb.contract().at(tokenAddress);

  try {
    // Check TRX balance
    const trxBalance = await tronWeb.trx.getBalance(address);
    console.log(`TRX balance: ${tronWeb.fromSun(trxBalance)}`);

    // Check token balance
    const balance = await contract.balanceOf(address).call();
    console.log(`Token balance: ${balance.toString()}`);

    // Get token name and symbol for verification
    const name = await contract.name().call();
    const symbol = await contract.symbol().call();
    console.log(`Token name: ${name}`);
    console.log(`Token symbol: ${symbol}`);

  } catch (error) {
    console.error('Error checking balance:', error);
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
