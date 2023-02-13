require('dotenv').config({ path: '.secret.env' })
const HDWalletProvider = require('@truffle/hdwallet-provider');


// Moonbase Alpha Private Key --> Please change this to your own Private Key with funds
// NOTE: Do not store your private key in plaintext files
//       this is only for demostration purposes only
const privateKeysMoonbase = [
   process.env.MOONBASE_KEY,
   process.env.MOONBASE_MANAGER,
];

const privateKeysMoonriver = [
   process.env.TEST_1,
   process.env.TEST_1,
   process.env.TEST_1,
   process.env.TEST_1,
];

const privateKeysMoonbeam = [
   process.env.MOONBEAM_KEY,
   process.env.MOONBEAM_MANAGER
];

const privateKeys = [
   process.env.MANAGER,
   process.env.OFFICER,
   process.env.DELEGATOR_1,
   process.env.DELEGATOR_2,
   process.env.DELEGATOR_3,
   process.env.AGENT007_KEY,
   process.env.REWARDS
];


module.exports = {
   networks: {
      // Moonbeam Development Network
      dev: {
         provider: () => {
            return new HDWalletProvider({
               privateKeys,
               providerOrUrl: 'http://localhost:9933/',
               numberOfAddresses: 17,
               //derivationPath: "m/44'/60'/0'/0"
            });
         },
         network_id: 1281,
      },
      // Moonbase Alpha TestNet
      moonbase: {
         provider: () => {
            return new HDWalletProvider({
               privateKeys: privateKeysMoonbase,
               providerOrUrl: 'http://45.82.64.32:9933/'
            });
         },
         network_id: 1287,
         //networkCheckTimeout: 60000,
         //timeoutBlocks: 200
      },
      moonriver: {
         provider: () => {
            return new HDWalletProvider({
               privateKeys: privateKeysMoonriver,
               providerOrUrl: 'https://moonriver.api.onfinality.io/public'
            });
         },
         network_id: 1285,
         networkCheckTimeout: 60000,
         timeoutBlocks: 200
      },
      moonbeam1: {
         provider: () => {
            return new HDWalletProvider({
               privateKeys: privateKeysMoonbeam,
               providerOrUrl:  'https://moonbeam.public.blastapi.io' //'https://moonbeam.unitedbloc.com:3000'
            });
         },
         network_id: 1284,
         //networkCheckTimeout: 60000,
         //timeoutBlocks: 200
      },
   },
   // Solidity 0.8.2 Compiler
   compilers: {
      solc: {
         version: '^0.8.2',
         settings: {
            optimizer: {
              enabled: true,
              runs: 365*12*10*10
            },
            viaIR: true
          }
      },
   },
   // Moonbeam Truffle Plugin & Truffle Plugin for Verifying Smart Contracts
   plugins: ['moonbeam-truffle-plugin', 'truffle-plugin-verify'],
};
