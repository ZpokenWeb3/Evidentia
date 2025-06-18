// Usage:
// node script/bridge/js/testOFTCrossChainTransfer.js --src "sepolia" --dst "tron-testnet" --amount 100000000 [--to DESTINATION_ADDRESS] [--mint]
// ENV_FILE=.env_mainnet node script/bridge/js/testOFTCrossChainTransfer.js --src "ethereum-mainnet" --dst "tron-mainnet" --amount 1000000 [--to DESTINATION_ADDRESS] [--mint]

const path = require('path');
const envFile = process.env.ENV_FILE || '.env';

// Load the appropriate env file
require('dotenv').config({ path: path.resolve(process.cwd(), envFile) });

const { ethers } = require('ethers');
const { Options } = require('@layerzerolabs/lz-v2-utilities');
const yargs = require('yargs/yargs');
const { hideBin } = require('yargs/helpers');
const { TronWeb } = require('tronweb');

// ABI definitions
const StableBondCoinsABI = [
  "function mint(address to, uint256 amount)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)"
];

const StableOFTAdapterABI = [
  "function quoteSend(tuple(uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd), bool payInLzToken) view returns (tuple(uint256 nativeFee, uint256 lzTokenFee))",
  "function send(tuple(uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd), tuple(uint256 nativeFee, uint256 lzTokenFee), address refundAddress) payable"
];

// LayerZero chain configurations
const chainConfigs = {
  'fuji': {
    eid: 40106,
    endpoint: '0x6EDCE65403992e310A62460808c4b910D972f10f',
    ulnSendLib: '0x69BF5f48d2072DfeBc670A1D19dff91D0F4E8170',
    ulnRecvLib: '0x819F0FAF2cb1Fba15b9cB24c9A2BDaDb0f895daf',
    gracePeriod: 0
  },
  'sepolia': {
    eid: 40161,
    endpoint: '0x6EDCE65403992e310A62460808c4b910D972f10f',
    ulnSendLib: '0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE',
    ulnRecvLib: '0xdAf00F5eE2158dD58E0d3857851c432E34A3A851',
    gracePeriod: 0
  },
  'tron-testnet': { // shasta
    eid: 40420,
    endpoint: '0x1b356f3030CE0c1eF9D3e1E250Bf0BB11D81b2d1',
    ulnSendLib: '0xaef63752785Ad2104cea1aa42b69b46f2530312F',
    ulnRecvLib: '0x843810EB9f002E940870a95B366cc59E623bF5f1',
    gracePeriod: 0
  },
  'ethereum-mainnet': {
    eid: 30101,
    endpoint: '0x1a44076050125825900e736c501f859c50fE728c',
    ulnSendLib: '0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1',
    ulnRecvLib: '0xc02Ab410f0734EFa3F14628780e6e695156024C2',
    gracePeriod: 0
  },
// v1 protocol
//   'ethereum-mainnet': {
//     eid: 30101,
//     endpoint: '0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675',
//     ulnSendLib: '0x4D73AdB72bC3DD368966edD0f0b2148401A178E2',
//     ulnRecvLib: '0xc02Ab410f0734EFa3F14628780e6e695156024C2',
//     gracePeriod: 0
//   },
  'tron-mainnet': {
    eid: 30420,
    endpoint: '0x0Af59750D5dB5460E5d89E268C474d5F7407c061',
    ulnSendLib: '0xE369D146219380B24Bb5D9B9E08a5b9936F9E719',
    ulnRecvLib: '0x612215D4dB0475a76dCAa36C7f9afD748c42ed2D',
    gracePeriod: 0
  },
};

// Helper functions to get proxy addresses
function getStableOFTProxy(network) {
  if (network === 'tron-testnet' || network === 'tron-mainnet') return process.env.TRON_OFT_TOKEN_ADDRESS;
  if (network === 'sepolia' || network === 'ethereum-mainnet') return process.env.STABLES_PROXY_ADDRESS;
  throw new Error(`Unknown network in getStableOFTProxy: ${network}`);
}

function getAdapterProxy(network) {
  if (network === 'sepolia' || network === 'ethereum-mainnet') return process.env.OFT_ADAPTER_PROXY_ADDRESS;
  if (network === 'tron-testnet' || network === 'tron-mainnet') return process.env.TRON_OFT_TOKEN_ADDRESS;
  throw new Error(`Unknown network in getAdapterProxy: ${network}`);
}

// Helper function to convert Tron address to Ethereum format
function convertTronToEthAddress(tronAddress) {
  try {
    // Create a TronWeb instance (without private key, just for address conversion)
    const tronWeb = new TronWeb({
      fullHost: 'https://api.shasta.trongrid.io'
    });

    // Convert Tron address to hex format
    const hexAddress = tronWeb.address.toHex(tronAddress);

    // Convert to Ethereum checksum address format
    // Remove '41' prefix from Tron hex address and add '0x' prefix
    const ethAddress = ethers.getAddress('0x' + hexAddress.slice(2));

    return ethAddress;
  } catch (error) {
    throw new Error(`Failed to convert Tron address ${tronAddress} to Ethereum format: ${error.message}`);
  }
}

// Helper function to convert Ethereum address to Tron format
function convertEthToTronAddress(ethAddress) {
  try {
    // Create a TronWeb instance (without private key, just for address conversion)
    const tronWeb = new TronWeb({
      fullHost: 'https://api.shasta.trongrid.io'
    });

    // Convert Ethereum address to Tron format
    // Add '41' prefix to Ethereum address (without '0x') and convert to base58
    const tronAddress = tronWeb.address.fromHex('41' + ethAddress.slice(2));

    return tronAddress;
  } catch (error) {
    throw new Error(`Failed to convert Ethereum address ${ethAddress} to Tron format: ${error.message}`);
  }
}

async function main() {
  // Parse command line arguments
  const argv = yargs(hideBin(process.argv))
    .option('src', {
      description: 'Source network (e.g., "ethereum-mainnet", "sepolia", "tron-testnet", "tron-mainnet")',
      type: 'string',
      demandOption: true
    })
    .option('dst', {
      description: 'Destination network (e.g., "sepolia", "ethereum-mainnet", "tron-testnet", "tron-mainnet")',
      type: 'string',
      demandOption: true
    })
    .option('amount', {
      description: 'Amount to transfer (in base units)',
      type: 'number',
      demandOption: true
    })
    .option('to', {
      description: 'Destination address (if not provided, sender address will be used)',
      type: 'string'
    })
    .option('mint', {
      description: 'Mint tokens before transfer',
      type: 'boolean',
      default: false
    })
    .help()
    .alias('help', 'h')
    .argv;

  const { src, dst, amount, to, mint } = argv;

  // Get destination chain config
  const dstChainConfig = chainConfigs[dst];
  if (!dstChainConfig) {
    throw new Error(`Unknown destination network: ${dst}`);
  }

  // Initialize provider, signer, and contracts based on source network
  let provider, signer, sender, token, oftAdapter;
  const privateKey = process.env.PRIVATE_KEY;

  if (src === 'tron-testnet' || src === 'tron-mainnet') {
    // Initialize TronWeb for Tron network
    const tronRpcUrl = process.env.TRON_RPC_URL;
    const tronWeb = new TronWeb({
      fullHost: tronRpcUrl,
      privateKey: privateKey
    });

    // Set provider and sender for Tron
    provider = tronWeb;
    sender = tronWeb.defaultAddress.base58;
    console.log(`Connected to Tron network with address: ${sender}`);

    // Get contract addresses for Tron
    const srcStableProxyAddress = getStableOFTProxy(src);
    const srcAdapterProxyAddress = getAdapterProxy(src);

    // Create contract instances for Tron
    token = await tronWeb.contract().at(srcStableProxyAddress);
    oftAdapter = await tronWeb.contract().at(srcAdapterProxyAddress);
  } else {
    // Initialize provider for EVM networks (Sepolia, Fuji)
    let rpcUrl;
    if (src === 'sepolia') {
      rpcUrl = process.env.SEPOLIA_RPC_URL;
    } else if (src === 'ethereum-mainnet') {
      rpcUrl = process.env.MAINNET_RPC_URL;
    } else if (src === 'fuji') {
      rpcUrl = process.env.FUJI_RPC_URL;
    }

    if (!rpcUrl) {
      throw new Error(`No RPC URL found for network: ${src}. Please add it to your .env file.`);
    }

    console.log(`rpcUrl: ${rpcUrl}`);

    // Set up provider and signer for EVM networks
    provider = new ethers.JsonRpcProvider(rpcUrl);
    signer = new ethers.Wallet(privateKey, provider);
    sender = signer.address;
    console.log(`Connected to ${src} network with address: ${sender}`);

    // Get contract addresses for EVM networks
    const srcStableProxyAddress = getStableOFTProxy(src);
    const srcAdapterProxyAddress = getAdapterProxy(src);

    console.log(`srcStableProxyAddress: ${srcStableProxyAddress}`);

    // Create contract instances for EVM networks
    token = new ethers.Contract(srcStableProxyAddress, StableBondCoinsABI, signer);
    oftAdapter = new ethers.Contract(srcAdapterProxyAddress, StableOFTAdapterABI, signer);
  }

  try {
    // Check current balance
    let initialBalance;
    
    if (src === 'tron-testnet' || src === 'tron-mainnet') {
      initialBalance = await token.balanceOf(sender).call();
    } else {
      initialBalance = await token.balanceOf(sender);
    }
    console.log(`Initial token balance: ${initialBalance.toString()}`);

    // Mint tokens to sender if --mint flag is provided
    if (mint) {
      console.log(`Minting ${amount} tokens to ${sender}...`);
      let mintTx;
      
      if (src === 'tron-testnet' || src === 'tron-mainnet') {
        mintTx = await token.mint(sender, amount).send();
        console.log(`Minted successfully! Transaction hash: ${mintTx}`);
      } else {
        mintTx = await token.mint(sender, amount);
        await mintTx.wait();
        console.log(`Minted successfully! Transaction hash: ${mintTx.hash}`);
      }

      // Verify new balance after minting
      let balanceAfterMint;
      if (src === 'tron-testnet' || src === 'tron-mainnet') {
        balanceAfterMint = await token.balanceOf(sender).call();
      } else {
        balanceAfterMint = await token.balanceOf(sender);
      }
      console.log(`Balance after minting: ${balanceAfterMint.toString()}`);
    } else {
      console.log(`Skipping mint step. Using existing balance for transfer.`);

      // Check if balance is sufficient
      if (BigInt(initialBalance) < BigInt(amount)) {
        throw new Error(`Insufficient balance: ${initialBalance.toString()}. Required: ${amount}. Use --mint flag to mint tokens.`);
      }
    }

    // Approve the OFT adapter to spend tokens
    console.log(`Approving OFT adapter to spend tokens...`);
    const srcAdapterProxyAddress = getAdapterProxy(src);
    
    let approveTx;
    if (src === 'tron-testnet' || src === 'tron-mainnet') {
      approveTx = await token.approve(srcAdapterProxyAddress, amount).send();
      console.log(`Approved OFT adapter to spend tokens: ${amount}`);
      console.log(`Transaction hash: ${approveTx}`);
    } else {
      approveTx = await token.approve(srcAdapterProxyAddress, amount);
      await approveTx.wait();
      console.log(`Approved OFT adapter to spend tokens: ${amount}`);
      console.log(`Transaction hash: ${approveTx.hash}`);
    }

    console.log(`Sender: ${sender}`);
    console.log(`OFT adapter: ${srcAdapterProxyAddress}`);

    const _gas = 71000;
    // Create options for cross-chain transfer
    const options = Options.newOptions()
      .addExecutorLzReceiveOption(_gas, 0)
      .toHex();

    // Determine destination address
    let destinationAddress;

    if (to) {
      try {
        if ((dst === 'tron-testnet' || dst === 'tron-mainnet') && to.startsWith('T')) {
          // For Tron addresses, convert from Tron format to Ethereum format
          console.log(`Detected Tron address format. Converting to Ethereum format for cross-chain transfer...`);
          destinationAddress = convertTronToEthAddress(to);
          console.log(`Converted Tron address ${to} to Ethereum format: ${destinationAddress}`);
        } else if ((src === 'tron-testnet' || src === 'tron-mainnet') && (dst === 'sepolia' || dst === 'ethereum-mainnet')) {
          // If source is Tron and destination is Sepolia, make sure the address is in Ethereum format
          if (to.startsWith('T')) {
            destinationAddress = convertTronToEthAddress(to);
          } else {
            destinationAddress = ethers.getAddress(to);
          }
        } else {
          // For Ethereum addresses, just validate
          destinationAddress = ethers.getAddress(to);
        }
      } catch (error) {
        throw new Error(`Invalid destination address: ${to}. Error: ${error.message}`);
      }
    } else {
      // If no destination address provided, use sender address
      if ((src === 'tron-testnet' && dst === 'sepolia') || (src === 'tron-mainnet' && dst === 'ethereum-mainnet')) {
        // If sending from Tron to Sepolia, convert sender address to Ethereum format
        destinationAddress = convertTronToEthAddress(sender);
      } else if ((src === 'sepolia' && dst === 'tron-testnet') || (src === 'ethereum-mainnet' && dst === 'tron-mainnet')) {
        // If sending from Sepolia to Tron, use sender address as is (already in Ethereum format)
        destinationAddress = sender;
      } else {
        destinationAddress = sender;
      }
    }

    console.log(`Destination address: ${destinationAddress}`);

    // Create send parameters
    let sendParam;
    
    if (src === 'tron-testnet' || src === 'tron-mainnet') {
      // For Tron, we need to format the parameters differently
      sendParam = {
        dstEid: dstChainConfig.eid,
        to: '0x' + destinationAddress.slice(2).padStart(64, '0'), // Convert address to bytes32
        amountLD: amount.toString(),
        minAmountLD: Math.floor(amount * 95 / 100).toString(), // 95% of amount
        extraOptions: options,
        composeMsg: '0x',
        oftCmd: '0x'
      };
    } else {
      // For EVM chains
      sendParam = {
        dstEid: dstChainConfig.eid,
        to: ethers.zeroPadValue(ethers.getBytes(destinationAddress), 32), // Convert address to bytes32
        amountLD: amount,
        minAmountLD: Math.floor(amount * 95 / 100), // 95% of amount
        extraOptions: options,
        composeMsg: '0x',
        oftCmd: '0x'
      };
    }

    console.log("sendParam:", sendParam);

    // Quote fee for cross-chain transfer
    console.log('Quoting fee for cross-chain transfer...');
    let fee;
    
    if (src === 'tron-testnet' || src === 'tron-mainnet') {
      fee = await oftAdapter.quoteSend(sendParam, false).call();
    } else {
      fee = await oftAdapter.quoteSend(sendParam, false);
    }
    
    console.log(`Fee (native): ${fee.nativeFee.toString()}`);

    // Send tokens cross-chain
    console.log('Sending tokens cross-chain...');

    // Create copies of objects to avoid issues with read-only properties
    const sendParamCopy = { ...sendParam };
    const feeCopy = { 
      nativeFee: fee.nativeFee.toString(),
      lzTokenFee: (fee.lzTokenFee || 0).toString()
    };

    // Helper function to convert BigInt to string for JSON serialization
    const replacer = (key, value) => {
      if (typeof value === 'bigint') {
        return value.toString();
      }
      return value;
    };

    console.log('Send parameters:', JSON.stringify(sendParamCopy, replacer));
    console.log('Fee parameters:', JSON.stringify(feeCopy, replacer));

    let tx;
    
    if (src === 'tron-testnet' || src === 'tron-mainnet') {
      // For Tron, we don't use staticCall
      tx = await oftAdapter.send(
        sendParamCopy,
        feeCopy,
        sender
      ).send({
        callValue: fee.nativeFee.toString()
      });
      
      console.log('Transaction sent!');
      console.log(`Tokens sent successfully! Transaction hash: ${tx}`);
    } else {
      // For EVM chains, we can use staticCall first
      const sendTx = await oftAdapter.send.staticCall(
        sendParamCopy,
        feeCopy,
        sender,
        { value: fee.nativeFee }
      ).catch(error => {
        console.error('Static call error:', error.message);
        // Continue execution even if staticCall fails
        return null;
      });

      // Execute the actual transaction
      tx = await oftAdapter.send(
        sendParamCopy,
        feeCopy,
        sender,
        { value: fee.nativeFee }
      );

      console.log('Transaction sent, waiting for confirmation...');
      await tx.wait();
      console.log(`Tokens sent successfully! Transaction hash: ${tx.hash}`);
    }

    // Check balance after transfer
    let balance;
    if (src === 'tron-testnet' || src === 'tron-mainnet') {
      balance = await token.balanceOf(sender).call();
    } else {
      balance = await token.balanceOf(sender);
    }
    console.log(`Remaining balance: ${balance}`);

  } catch (error) {
    console.error('Error:', error);
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
