// Usage: node script/bridge/js/testOFTCrossChainTransfer.js --src "sepolia" --dst "tron-testnet" --amount 100000000 --mint

require('dotenv').config();
const { ethers } = require('ethers');
const { Options } = require('@layerzerolabs/lz-v2-utilities');
const yargs = require('yargs/yargs');
const { hideBin } = require('yargs/helpers');

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
    gracePeriod: 50
  },
  'sepolia': {
    eid: 40161,
    endpoint: '0x6EDCE65403992e310A62460808c4b910D972f10f',
    ulnSendLib: '0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE',
    ulnRecvLib: '0xdAf00F5eE2158dD58E0d3857851c432E34A3A851',
    gracePeriod: 50
  },
  'tron-testnet': {
    eid: 40420,
    endpoint: '0x1b356f3030CE0c1eF9D3e1E250Bf0BB11D81b2d1',
    ulnSendLib: '0xaef63752785Ad2104cea1aa42b69b46f2530312F',
    ulnRecvLib: '0x843810EB9f002E940870a95B366cc59E623bF5f1',
    gracePeriod: 50
  }
};

// Helper functions to get proxy addresses
function getStableOFTProxy(network) {
  if (network === 'tron-testnet') return process.env.TRON_OFT_TOKEN_ADDRESS;
  if (network === 'sepolia') return process.env.STABLES_PROXY_ADDRESS;
  throw new Error(`Unknown network in getStableOFTProxy: ${network}`);
}

function getAdapterProxy(network) {
  if (network === 'sepolia') return process.env.OFT_ADAPTER_PROXY_ADDRESS;
  if (network === 'tron-testnet') return process.env.TRON_OFT_TOKEN_ADDRESS;
  throw new Error(`Unknown network in getAdapterProxy: ${network}`);
}

async function main() {
  // Parse command line arguments
  const argv = yargs(hideBin(process.argv))
    .option('src', {
      description: 'Source network (e.g., "fuji", "sepolia")',
      type: 'string',
      demandOption: true
    })
    .option('dst', {
      description: 'Destination network (e.g., "sepolia", "fuji")',
      type: 'string',
      demandOption: true
    })
    .option('amount', {
      description: 'Amount to transfer (in base units)',
      type: 'number',
      demandOption: true
    })
    .option('mint', {
      description: 'Mint tokens before transfer',
      type: 'boolean',
      default: false
    })
    .help()
    .alias('help', 'h')
    .argv;

  const { src, dst, amount, mint } = argv;

  // Get destination chain config
  const dstChainConfig = chainConfigs[dst];
  if (!dstChainConfig) {
    throw new Error(`Unknown destination network: ${dst}`);
  }

  let rpcUrl;
  if (src === 'sepolia') {
    rpcUrl = process.env.SEPOLIA_RPC_URL;
  }

  if (!rpcUrl) {
    throw new Error(`No RPC URL found for network: ${src}`);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const privateKey = process.env.PRIVATE_KEY;
  const signer = new ethers.Wallet(privateKey, provider);
  const sender = signer.address;

  console.log(`Connected to network with address: ${sender}`);

  // Get contract addresses
  const srcStableProxyAddress = getStableOFTProxy(src);
  const srcAdapterProxyAddress = getAdapterProxy(src);

  // Create contract instances
  const token = new ethers.Contract(srcStableProxyAddress, StableBondCoinsABI, signer);
  const oftAdapter = new ethers.Contract(srcAdapterProxyAddress, StableOFTAdapterABI, signer);

  try {
    // Check current balance
    const initialBalance = await token.balanceOf(sender);
    console.log(`Initial token balance: ${initialBalance.toString()}`);

    // Mint tokens to sender if --mint flag is provided
    if (mint) {
      console.log(`Minting ${amount} tokens to ${sender}...`);
      const mintTx = await token.mint(sender, amount);
      await mintTx.wait();
      console.log(`Minted successfully! Transaction hash: ${mintTx.hash}`);

      // Verify new balance after minting
      const balanceAfterMint = await token.balanceOf(sender);
      console.log(`Balance after minting: ${balanceAfterMint.toString()}`);
    } else {
      console.log(`Skipping mint step. Using existing balance for transfer.`);

      // Check if balance is sufficient
      if (initialBalance < amount) {
        throw new Error(`Insufficient balance: ${initialBalance.toString()}. Required: ${amount}. Use --mint flag to mint tokens.`);
      }
    }

    // Approve the OFT adapter to spend tokens
    console.log(`Approving OFT adapter to spend tokens...`);
    const approveTx = await token.approve(srcAdapterProxyAddress, amount);
    await approveTx.wait();
    console.log(`Approved OFT adapter to spend tokens: ${amount}`);
    console.log(`Sender: ${sender}`);
    console.log(`OFT adapter: ${srcAdapterProxyAddress}`);

    // Create options for cross-chain transfer
    const options = Options.newOptions()
      .addExecutorLzReceiveOption(dstChainConfig.gracePeriod, 0)
      .addExecutorComposeOption(0, dstChainConfig.gracePeriod, 0)
      .toHex();

    // Create send parameters
    const sendParam = {
      dstEid: dstChainConfig.eid,
      to: ethers.zeroPadValue(ethers.getBytes(sender), 32), // Convert address to bytes32
      amountLD: amount,
      minAmountLD: Math.floor(amount * 95 / 100), // 95% of amount
      extraOptions: options,
      composeMsg: '0x',
      oftCmd: '0x'
    };

    // Quote fee for cross-chain transfer
    console.log('Quoting fee for cross-chain transfer...');
    const fee = await oftAdapter.quoteSend(sendParam, false);
    console.log(`Fee (native): ${fee.nativeFee.toString()}`);

    // Send tokens cross-chain
    console.log('Sending tokens cross-chain...');

    // Create copies of objects to avoid issues with read-only properties
    const sendParamCopy = { ...sendParam };
    const feeCopy = { 
      nativeFee: fee.nativeFee,
      lzTokenFee: fee.lzTokenFee || 0
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
    const tx = await oftAdapter.send(
      sendParamCopy,
      feeCopy,
      sender,
      { value: fee.nativeFee }
    );

    console.log('Transaction sent, waiting for confirmation...');
    await tx.wait();
    console.log(`Tokens sent successfully! Transaction hash: ${tx.hash}`);

    // Check balance after transfer
    const balance = await token.balanceOf(sender);
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
