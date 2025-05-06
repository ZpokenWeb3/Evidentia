const fs = require('fs');
const path = require('path');

const srcPaths = ['./src', './src/V2']; // Main src folder and V2 folder
const outPath = './out'; // Replace with your actual out folder path
const abiPath = './script/ABI'; // Replace with your actual ABI folder path

// Create the ABI folder if it doesn't exist
if (!fs.existsSync(abiPath)) {
  fs.mkdirSync(abiPath);
}

// Process files in a directory
function processDirectory(dirPath) {
  fs.readdir(dirPath, (err, files) => {
    if (err) {
      console.error(`Error reading directory ${dirPath}: ${err}`);
      return;
    }

    files.forEach(file => {
      const fullPath = path.join(dirPath, file);
      
      // Check if it's a directory
      if (fs.statSync(fullPath).isDirectory()) {
        // Skip Interfaces directory and other special directories
        if (file !== 'Interfaces') {
          processDirectory(fullPath);
        }
        return;
      }
      
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
            if (err) {
              console.error(`Error reading JSON file ${jsonFile}: ${err}`);
              return;
            }

            try {
              // Parse the JSON data
              const jsonData = JSON.parse(data);

              // Write the updated JSON data to the ABI folder
              fs.writeFile(abiFile, JSON.stringify(jsonData.abi, null, 2), (err) => {
                if (err) {
                  console.error(`Error writing ABI file ${abiFile}: ${err}`);
                  return;
                }
                console.log(`ABI written for ${contractName}`);
              });
            } catch (parseError) {
              console.error(`Error parsing JSON file ${jsonFile}: ${parseError}`);
            }
          });
        } else {
          console.error(`Corresponding folder or JSON file not found for ${contractName}`);
        }
      }
    });
  });
}

// Process all source directories
srcPaths.forEach(srcPath => {
  processDirectory(srcPath);
});