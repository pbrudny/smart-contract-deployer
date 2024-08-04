// pages/api/contract-details.js

import fs from 'fs';
import path from 'path';

export default function handler(req, res) {
  const abiPath = path.resolve('./build', 'MyContract.abi');
  const bytecodePath = path.resolve('./build', 'MyContract.bin');

  const abi = fs.readFileSync(abiPath, 'utf8');
  const bytecode = fs.readFileSync(bytecodePath, 'utf8');

  res.status(200).json({ abi: JSON.parse(abi), bytecode });
}
