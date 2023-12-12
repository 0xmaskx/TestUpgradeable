import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import '@openzeppelin/hardhat-upgrades';

require('dotenv').config();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
    networks: {
      localhost: {
        url: "http://127.0.0.1:8545"
      },
      avalanche: {
        url: "https://api.avax.network/ext/bc/C/rpc",
        accounts: [process.env.AVALANCHE_PRIVATE_KEY]
      }
    },
  etherscan: {
    apiKey: {
      avalanche: process.env.ETHERSCAN_API_KEY
    }
  }
};

export default config;
