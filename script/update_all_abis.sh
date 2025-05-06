#!/bin/bash

# Compile contracts using Foundry
echo "Compiling contracts..."
forge build

# Update ABI files
echo "Updating ABI files..."
node script/_update_abis.js

echo "ABI files updated successfully!"