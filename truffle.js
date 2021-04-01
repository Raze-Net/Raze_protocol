const HDWalletProvider = require('@truffle/hdwallet-provider');
var mnemonic = "forest sentence vacant solid craft satoshi cash bridge science uncle weekend sea";

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // for more about customizing your Truffle configuration!
    networks: {
        development: {
        host: "127.0.0.1",
        port: 7545,
        network_id: "*" // Match any network id
    },
    develop: {
        host: "127.0.0.1",
        port: 8545
    },
    heco_testnet: {
        provider: () => new HDWalletProvider(mnemonic, 'https://http-testnet.hecochain.com'),
        network_id: 256
    },
    heco_mainnet: {
        provider: () => new HDWalletProvider(mnemonic, 'https://http-mainnet.hecochain.com'),
        network_id: 128
    },
    bsc_testnet: {
        provider: () => new HDWalletProvider(mnemonic, `https://data-seed-prebsc-1-s1.binance.org:8545`),
        network_id: 97,
        confirmations: 10,
        timeoutBlocks: 200,
        skipDryRun: true    
    },
    bsc_mainnet: {
        provider: () => new HDWalletProvider(mnemonic, `https://bsc-dataseed1.binance.org`),
        network_id: 56,
        confirmations: 10,
        timeoutBlocks: 200,
        skipDryRun: true
    }
  },

  compilers: {
      solc: {
          version: "^0.6.0"
      }
  }
};
