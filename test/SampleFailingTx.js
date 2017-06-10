const lightwallet = require('eth-lightwallet')
const evm_increaseTime = require('./evmIncreaseTime.js')
const snapshots = require('./evmSnapshots.js')
const IdentityManager = artifacts.require('IdentityManager')
const MetaIdentityManager = artifacts.require('MetaIdentityManager')
const MetaTxRelay = artifacts.require('MetaTxRelay')
const Proxy = artifacts.require('Proxy')
const TestRegistry = artifacts.require('TestRegistry')
const Promise = require('bluebird')
const compareCode = require('./compareCode')
const solsha3 = require('solidity-sha3').default
web3.eth = Promise.promisifyAll(web3.eth)

const LOG_NUMBER_1 = 1234
const LOG_NUMBER_2 = 2345

const userTimeLock = 100;
const adminTimeLock = 1000;
const adminRate = 200;

contract('MetaIdentityManager - Sample Failing Test', (accounts) => {
  let proxy
  let testReg
  let metaIdenManager
  let txRelay
  let user1

  let recoveryKey

  before(done => {
    user1 = accounts[0]
    recoveryKey = accounts[8]

    MetaTxRelay.new().then((instance) => {
      txRelay = instance
      return MetaIdentityManager.new(userTimeLock, adminTimeLock, adminRate)
    }).then((instance) => {
      metaIdenManager = instance
      return TestRegistry.deployed()
    }).then((instance) => {
      testReg = instance
      return metaIdenManager.CreateIdentity(user1, recoveryKey, {from: user1})
    }).then(tx => {
      let log = tx.logs[0]
      assert.equal(log.event, 'IdentityCreated', 'wrong event')
      proxy = Proxy.at(log.args.identity)
      done()
    })
  })

  it('allow transactions initiated by owner', (done) => {

    //Not adding the 0x to data leads to it not be considered hex, as far as I can tell.
    let data = '0x' + lightwallet.txutils._encodeFunctionTxData('register', ['uint256'], [LOG_NUMBER_1])
    //This encoding does not work, for some reason.
    let newData = '0x' + lightwallet.txutils._encodeFunctionTxData('forwardTo',
                                                ['address', 'address', 'uint256', 'bytes', 'address'],
                                                [proxy.address, testReg.address, 0, data, user1])
    console.log("data: " + data)
    console.log("address that seems like it should be on end of new data: " + user1)
    console.log("new data: " + newData)
    txRelay.checkAddress.call(newData, user1).then(res => {
      assert.isTrue(res, "address should be allowed")
      return txRelay.relayTx(metaIdenManager.address, newData, {from: user1})
    }).then((tx) => {
      // Verify that the proxy address is logged as the sender
      return testReg.registry.call(proxy.address)
    }).then((regData) => {
      assert.equal(regData.toNumber(), LOG_NUMBER_1, 'User1 should be able to send transaction')
      done()
    }).catch(done)
  })
})
