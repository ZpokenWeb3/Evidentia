const { ethers } = require('ethers');
const { DateTime } = require('luxon');
const fs = require('fs');
const path = require('path');
const yargs = require('yargs');

// Determine which env file to use based on NODE_ENV
const network = process.env.NODE_ENV || 'sepolia';
const envFile = network === 'mainnet' ? '.env_mainnet' : '.env';

// Load the appropriate env file
require('dotenv').config({ path: path.resolve(process.cwd(), envFile) });

// Contract configuration
const bondNFTAddress = process.env.BOND_NFT_PROXY_ADDRESS; // BondNFT
const contractABIPath = './script/ABI/BondNFT.json';

// Wallet and provider configuration
const privateKey = process.env.PRIVATE_KEY;
// Use the appropriate RPC URL based on the network
const rpcUrl = network === 'mainnet' ? process.env.MAINNET_RPC_URL : process.env.SEPOLIA_RPC_URL;

// Load contract ABI
const contractABI = JSON.parse(fs.readFileSync(contractABIPath, 'utf8'));

/**
 * Validate and parse financial values
 */
function parseFinancialValue(value) {
  if (!/^\d+(_\d+)?$/.test(value)) {
    throw new Error(`Invalid value format: ${value}. Use underscore as thousand separator (e.g. 1000_000000)`);
  }
  return parseInt(value.replace(/_/g, ''), 10);
}

/**
 * Validate ISIN format (ISO 6166)
 */
function validateISIN(isin) {
  if (!/^[A-Z]{2}[A-Z0-9]{9}[0-9]$/.test(isin)) {
    throw new Error(`Invalid ISIN format: ${isin}`);
  }
  return isin;
}

/**
 * Configure command line interface
 */
const argv = yargs(process.argv.slice(2))
  .usage('Usage: $0 [options]')
  .option('issue-date', {
    alias: 'i',
    describe: 'Issue date in DD.MM.YYYY format',
    demandOption: true,
    type: 'string'
  })
  .option('expiration-date', {
    alias: 'e',
    describe: 'Expiration date in DD.MM.YYYY format',
    demandOption: true,
    type: 'string'
  })
  .option('value', {
    alias: 'v',
    describe: 'Bond face value (with decimal places)',
    demandOption: true,
    type: 'string'
  })
  .option('coupon', {
    alias: 'c',
    describe: 'Coupon value (with decimal places)',
    demandOption: true,
    type: 'string'
  })
  .option('isin', {
    alias: 'n',  // -n for International Securities Identification Number
    describe: 'ISIN code (ISO 6166 format)',
    demandOption: true,
    type: 'string'
  })
  .example('$0 -i 13.02.2024 -e 28.01.2026 -v 1000_000000 -c 88_000000 -n UA4000230262')
  .help('h')
  .alias('h', 'help')
  .strict()
  .fail((msg, err) => {
    if (err) throw err;
    console.error(msg);
    process.exit(1);
  })
  .parse();

/**
 * Convert date to Kyiv timestamp
 */
function dateToKyivTimestamp(dateString) {
  const [day, month, year] = dateString.split('.').map(Number);
  const dt = DateTime.fromObject(
    { day, month, year },
    { zone: 'Europe/Kyiv' }
  ).startOf('day');
  
  if (!dt.isValid) {
    throw new Error(`Invalid date: ${dt.invalidExplanation}`);
  }
  
  return Math.floor(dt.toSeconds());
}

/**
 * Main function to set metadata
 */
async function setMetadata() {
  try {
    // Parse and validate inputs
    const issueTimestamp = dateToKyivTimestamp(argv.issueDate);
    const expirationTimestamp = dateToKyivTimestamp(argv.expirationDate);
    const parsedValue = parseFinancialValue(argv.value);
    const parsedCouponValue = parseFinancialValue(argv.coupon);
    const validatedISIN = validateISIN(argv.isin.toUpperCase());

    // Initialize Ethereum components
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);
    const contract = new ethers.Contract(bondNFTAddress, contractABI, wallet);

    // Prepare metadata
    const metadata = {
      value: parsedValue,
      couponValue: parsedCouponValue,
      issueTimestamp,
      expirationTimestamp,
      ISIN: validatedISIN
    };

    // Generate token ID
    const stringHash = ethers.keccak256(ethers.toUtf8Bytes(validatedISIN));
    const tokenId = BigInt(stringHash).toString();

    // Display validation summary
    console.log('Transaction Summary:');
    console.log(`- Issue Date:    ${argv.issueDate} (timestamp: ${issueTimestamp})`);
    console.log(`- Expiration:    ${argv.expirationDate} (timestamp: ${expirationTimestamp})`);
    console.log(`- Face Value:    ${parsedValue}`);
    console.log(`- Coupon Value:  ${parsedCouponValue}`);
    console.log(`- ISIN:          ${validatedISIN}`);
    console.log(`- Token ID:      ${tokenId}\n`);

    // Execute transaction
    console.log('Sending transaction...');
    const tx = await contract.setMetaData(tokenId, metadata);
    console.log(`Transaction broadcasted: ${tx.hash}`);
    
    const receipt = await tx.wait();
    console.log('\nTransaction confirmed:');
    console.log(`- Block: ${receipt.blockNumber}`);
    console.log(`- Gas Used: ${receipt.gasUsed.toString()}`);
    
  } catch (error) {
    console.error('\nError:', error.message);
    if (error.reason) console.error('Contract Error:', error.reason);
    process.exit(1);
  }
}

// Execute main function
setMetadata();
