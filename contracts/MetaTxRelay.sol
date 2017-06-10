pragma solidity ^0.4.8;

//This contract is meant as a "singleton" forwarding contract.
//Eventually, it will be able to forward any transaction to
//Any contract that is build to accept it.

contract MetaTxRelay {

  // Note: This is a local nonce.
  // Different from the nonce defined w/in protocol.
  mapping(address => uint) nonce;

  /*
   * @dev Relays normal transactions
   * @param destination The address to relay data to
   * @param data The bytes necessary to call the function in the destination contract.
                 Note, this must end in the msg.sender's address
   */
  function relayTx(address destination, bytes data) payable {
    if (!checkAddress(data, msg.sender)) throw;

    if (!destination.call.value(msg.value)(data)) {
        if (!msg.sender.send(msg.value)) {} //Ether may get trapped if relayer is contract w/ weird fallback
    }
  }

  /*
   * @dev Relays meta transactions
   * @param sigV, sigR, sigS ECDSA signature on some data to be forwarded
   * @param data The bytes necessary to call the function in the destination contract.
                 Note, this must end in the address of the user who is having tx forwarded
   * @param claimedSender Address of the user who is having tx forwarded
   */
  function relayMetaTx(uint8 sigV, bytes32 sigR, bytes32 sigS, bytes data, address claimedSender) payable {
    bytes32 h = sha3(this, nonce[claimedSender], data, msg.sender);
    nonce[claimedSender]++;
    address addressFromSig = ecrecover(h, sigV, sigR, sigS);

    if (claimedSender != addressFromSig || !checkAddress(data, addressFromSig)) throw;
    if (!this.call.value(msg.value)(data)) {
      if (!msg.sender.send(msg.value)) {} //Note: if this fails, then ether is trapped in this contract (maybe withdraw pattern)
    }
  }
  // Note, later version of meta-tx may define validity using msg.gas, block number, or defining an owner.
  // This was left out of the current version of simplicities sake.

  /*
   * @dev Compares the last 20 bytes of a byte array to an address
   * @param b The byte array that may have an address on the end
   * @param address Address to check on the end of the array
    (Special thanks to tjade273 w/ this optimization)
   */
  function checkAddress(bytes b, address a) constant returns (bool t) {
      assembly {
          let l := mload(b)
          let mask := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
          t := eq(and(mask, a), and(mask, mload(add(b,l))))
      }
  }

  /*
 * @dev Returns the local nonce of an account.
 * @param add The address to return the nonce for.
 * @return The specific-to-this-contract nonce of the address provided
 */
  function getNonce(address add) constant returns (uint) {
    return nonce[add];
  }

 /*
  * @dev Returns the current block number.
  * @return current block number
  */
  function getBlockNum() constant returns (uint) {
    return block.number;
  }
}
