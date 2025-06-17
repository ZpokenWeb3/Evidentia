// Usage: node script/bridge/js/checkTronBalance.js [--address TRON_ADDRESS] [--token TOKEN_ADDRESS] [--network mainnet|testnet|nile|shasta] [--rpc CUSTOM_RPC_URL]

require('dotenv').config();
const { TronWeb } = require('tronweb');
const yargs = require('yargs/yargs');
const { hideBin } = require('yargs/helpers');

// ABI for StableBondCoinsOFT contract
const tokenABI = [
  {
    "inputs": [{"name": "account", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "name",
    "outputs": [{"type": "string"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "symbol",
    "outputs": [{"type": "string"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "decimals",
    "outputs": [{"type": "uint8"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "totalSupply",
    "outputs": [{"type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
];

async function main() {
  // Parse command line arguments
  const argv = yargs(hideBin(process.argv))
    .option('address', {
      description: 'TRON address to check balance for',
      type: 'string'
    })
    .option('token', {
      description: 'Token contract address (overrides TRON_OFT_TOKEN_BASE58_ADDRESS from .env)',
      type: 'string'
    })
    .option('network', {
      description: 'TRON network to connect to',
      type: 'string',
      choices: ['mainnet', 'testnet', 'nile', 'shasta'],
      default: 'testnet'
    })
    .option('rpc', {
      description: 'Custom RPC URL (overrides network option)',
      type: 'string'
    })
    .help()
    .alias('help', 'h')
    .argv;

  // Determine RPC URL based on network or custom RPC
  let rpcUrl;
  if (argv.rpc) {
    rpcUrl = argv.rpc;
  } else {
    switch (argv.network) {
      case 'mainnet':
        rpcUrl = 'https://api.trongrid.io';
        break;
      case 'testnet':
      case 'shasta':
        rpcUrl = 'https://api.shasta.trongrid.io';
        break;
      case 'nile':
        rpcUrl = 'https://nile.trongrid.io';
        break;
      default:
        rpcUrl = 'https://api.shasta.trongrid.io';
    }
  }

  console.log(`Connecting to TRON network: ${argv.rpc ? 'Custom RPC' : argv.network}`);
  console.log(`RPC URL: ${rpcUrl}`);

  // Setup TronWeb instance
  const tronWeb = new TronWeb({
    fullHost: rpcUrl,
    privateKey: process.env.TRON_PRIVATE_KEY
  });

  // Get address - either from command line or from private key
  let address;
  if (argv.address) {
    address = argv.address;
    console.log(`Checking balance for provided address: ${address}`);
  } else {
    address = tronWeb.address.fromPrivateKey(process.env.TRON_PRIVATE_KEY);
    console.log(`Checking balance for wallet address: ${address}`);
  }

  // Get OFT token contract instance - either from command line or from .env
  let tokenAddress;
  if (argv.token) {
    tokenAddress = argv.token;
  } else {
    tokenAddress = process.env.TRON_OFT_TOKEN_BASE58_ADDRESS;
    if (!tokenAddress) {
      throw new Error('Token address not provided. Use --token option or set TRON_OFT_TOKEN_BASE58_ADDRESS in .env file');
    }
  }

  console.log(`Token contract address: ${tokenAddress}`);

  try {
    // Check TRX balance
    const trxBalance = await tronWeb.trx.getBalance(address);
    console.log(`TRX balance: ${tronWeb.fromSun(trxBalance)}`);

    // Get contract instance with custom ABI
    const contract = await tronWeb.contract(tokenABI, tokenAddress);

    // Get available methods
    const availableMethods = Object.keys(contract).filter(key => typeof contract[key] === 'function');
    console.log('Available contract methods:', availableMethods);

    // Try to check token balance
    try {
      const balanceResult = await contract.balanceOf(address).call();
      console.log(`Token balance: ${balanceResult.toString()}`);
    } catch (error) {
      console.log('Error calling balanceOf:', error.message);
    }

    // Try to get token name
    try {
      const nameResult = await contract.name().call();
      console.log(`Token name: ${nameResult}`);
    } catch (error) {
      console.log('Error calling name:', error.message);
    }

    // Try to get token symbol
    try {
      const symbolResult = await contract.symbol().call();
      console.log(`Token symbol: ${symbolResult}`);
    } catch (error) {
      console.log('Error calling symbol:', error.message);
    }

    // Try to get token decimals
    try {
      const decimalsResult = await contract.decimals().call();
      console.log(`Token decimals: ${decimalsResult}`);
    } catch (error) {
      console.log('Error calling decimals:', error.message);
    }

    // Try to get total supply
    try {
      const totalSupplyResult = await contract.totalSupply().call();
      console.log(`Total supply: ${totalSupplyResult.toString()}`);
    } catch (error) {
      console.log('Error calling totalSupply:', error.message);
    }

    // Note: This is a proxy contract with StableBondCoinsOFT implementation
    console.log('\nThis is a proxy contract with StableBondCoinsOFT implementation');

  } catch (error) {
    console.error('Error checking balance:', error);
    if (error.transaction) {
      console.error('Transaction error details:', error.transaction);
    }
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
