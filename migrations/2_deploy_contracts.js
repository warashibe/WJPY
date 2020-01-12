const WJPY = artifacts.require("WJPY")
module.exports = async function(deployer) {
  const link = "0x20fE562d797A42Dcb3399062AE9546cd06f63280"
  const dai = "0xad6d458402f60fd3bd25163575031acdce07538d"
  const oracle = "0xc99B3D447826532722E41bc36e644ba3479E4365"
  const job = web3.utils.fromAscii("e6d74030e4a440898965157bc5a08abc")
  const fee = web3.utils.toWei("1")
  const dai_ex_addr = "0xc0fc958f7108be4060F33a699a92d3ea49b0B5f0"
  await deployer.deploy(WJPY, dai, dai_ex_addr, link, link, oracle, job, fee)
}
