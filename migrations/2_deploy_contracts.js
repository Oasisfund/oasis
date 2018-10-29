const Oasis = artifacts.require('Oasis');

module.exports = async function (deployer) {
    deployer.deploy(Oasis);
};
