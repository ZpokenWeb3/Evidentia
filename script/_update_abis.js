const fs = require('fs');
const path = require('path');

const srcPath = './src'; // Replace with your actual src folder path
const outPath = './out'; // Replace with your actual out folder path
const abiPath = './script/ABI'; // Replace with your actual ABI folder path

// Create the ABI folder if it doesn't exist
if (!fs.existsSync(abiPath)) {
  fs.mkdirSync(abiPath);
}

// Read all files in the src folder
fs.readdir(srcPath, (err, files) => {
  if (err) throw err;

  files.forEach(file => {
    // Check if the file is a Solidity contract file
    if (path.extname(file) === '.sol' && !file.includes('Test')) {
      const contractName = path.basename(file, '.sol');
      const outFolder = path.join(outPath, file);
      const jsonFile = path.join(outFolder, `${contractName}.json`);
      const abiFile = path.join(abiPath, `${contractName}.json`);

      // Check if the corresponding folder and JSON file exist in the out folder
      if (fs.existsSync(outFolder) && fs.existsSync(jsonFile)) {
        // Read the JSON file
        fs.readFile(jsonFile, 'utf8', (err, data) => {
          if (err) throw err;

          // Parse the JSON data
          const jsonData = JSON.parse(data);

          // Write the updated JSON data to the ABI folder
          fs.writeFile(abiFile, JSON.stringify(jsonData.abi, null, 2), (err) => {
            if (err) throw err;
            console.log(`ABI written for ${contractName}`);
          });
        });
      } else {
        console.error(`Corresponding folder or JSON file not found for ${contractName}`);
      }
    }
  });
});