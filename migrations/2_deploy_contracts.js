var TestRazeToken = artifacts.require("TestRazeToken");
var Utils = artifacts.require("Utils");
var RazeIP = artifacts.require("RazeIP");
var RazeRedeem = artifacts.require("RazeRedeem");
var RazeTransfer = artifacts.require("RazeTransfer");
var RazeETH = artifacts.require("RazeETH");
var RazeERC20 = artifacts.require("RazeERC20");

module.exports = function(deployer) {

    console.log("Deploying Utils, TestRazeToken, RazeIP...");
    return Promise.all([
        deployer.deploy(Utils),
        deployer.deploy(TestRazeToken),
        deployer.deploy(RazeIP)
    ])
    .then(() => {
        console.log("Deploying RazeRedeem...");
        return Promise.all([
            deployer.deploy(RazeRedeem, RazeIP.address),
        ]);
    })
    .then(() => {
        console.log("Deploying RazeTransfer...");
        return Promise.all([
            deployer.deploy(RazeTransfer, RazeIP.address)
        ]);
    })
    .then(() => {
        console.log("Deploying RazeETH...");
        return Promise.all([
            // Should use string for large number. This seems to be a bug:
            // https://github.com/ethereum/web3.js/issues/2077
            deployer.deploy(RazeETH, RazeTransfer.address, RazeRedeem.address, "10000000000000000"),
        ]);
    })
    .then(() => {
        console.log("Deploying RazeERC20...");
        return Promise.all([
            // Should use string for large number. This seems to be a bug:
            // https://github.com/ethereum/web3.js/issues/2077
            deployer.deploy(RazeERC20, TestRazeToken.address, RazeTransfer.address, RazeRedeem.address, "10000000000000000000000")
        ]);
    });
};
