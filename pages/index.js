import { useState } from 'react';
import { ethers } from 'ethers';

export default function Home() {
  const [message, setMessage] = useState('');
  const [deploying, setDeploying] = useState(false);
  const [contractAddress, setContractAddress] = useState('');

  const handleDeploy = async (event) => {
    event.preventDefault();

    if (!window.ethereum) {
      alert('Please install MetaMask!');
      return;
    }

    try {
      // Request account access
      await window.ethereum.request({ method: 'eth_requestAccounts' });

      // Create a provider connected to MetaMask
      const provider = new ethers.providers.Web3Provider(window.ethereum);

      // Get the signer
      const signer = provider.getSigner();

      // Fetch contract ABI and bytecode from your API
      const response = await fetch('/api/contract-details');
      const contractDetails = await response.json();

      // Create a ContractFactory instance
      const factory = new ethers.ContractFactory(
        contractDetails.abi,
        contractDetails.bytecode,
        signer
      );

      // Deploy the contract
      setDeploying(true);
      const contract = await factory.deploy(message);
      await contract.deployed();
      setContractAddress(contract.address);
      alert(`Contract deployed at address: ${contract.address}`);
    } catch (error) {
      console.error('Failed to deploy contract:', error);
      alert('Failed to deploy contract');
    } finally {
      setDeploying(false);
    }
  };

  return (
    <div>
      <h1>Deploy Smart Contract</h1>
      <form onSubmit={handleDeploy}>
        <label htmlFor="message">Initial Message:</label>
        <input
          type="text"
          id="message"
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          required
        />
        <button type="submit" disabled={deploying}>
          {deploying ? 'Deploying...' : 'Deploy'}
        </button>
      </form>
      {contractAddress && (
        <p>Contract deployed at: <strong>{contractAddress}</strong></p>
      )}
    </div>
  );
}
