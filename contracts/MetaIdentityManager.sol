pragma solidity ^0.4.8;
import "./Proxy.sol";

contract MetaIdentityManager {
  uint adminTimeLock;
  uint userTimeLock;
  uint adminRate;
  address relay;

  event IdentityCreated(
    address indexed identity,
    address indexed creator,
    address owner,
    address indexed recoveryKey);

  event OwnerAdded(
    address indexed identity,
    address indexed owner,
    address instigator);

  event OwnerRemoved(
    address indexed identity,
    address indexed owner,
    address instigator);

  event RecoveryChanged(
    address indexed identity,
    address indexed recoveryKey,
    address instigator);

  event MigrationInitiated(
    address indexed identity,
    address indexed newIdManager,
    address instigator);

  event MigrationCanceled(
    address indexed identity,
    address indexed newIdManager,
    address instigator);

   event MigrationFinalized(
    address indexed identity,
    address indexed newIdManager,
    address instigator);

  mapping(address => mapping(address => uint)) owners;
  mapping(address => address) recoveryKeys;
  mapping(address => mapping(address => uint)) limiter;
  mapping(address => uint) migrationInitiated;
  mapping(address => address) migrationNewAddress;

  modifier onlyRelay() {
    if (msg.sender == relay) _;
    else throw;
  }

  modifier onlyOwner(address identity, address sender) {
    if (owners[identity][sender] > 0 && (owners[identity][sender] + userTimeLock) <= now ) _ ;
    else throw;
  }

  modifier onlyOlderOwner(address identity, address sender) {
    if (owners[identity][sender] > 0 && (owners[identity][sender] + adminTimeLock) <= now) _ ;
    else throw;
  }

  modifier onlyRecovery(address identity, address sender) {
    if (recoveryKeys[identity] == sender) _ ;
    else throw;
  }

  modifier rateLimited(Proxy identity, address sender) {
    if (limiter[identity][sender] < (now - adminRate)) {
      limiter[identity][sender] = now;
      _ ;
    } else throw;
  }

  // Instantiate IdentityManager with the following limits:
  // - userTimeLock - Time before new owner can control proxy
  // - adminTimeLock - Time before new owner can add/remove owners
  // - adminRate - Time period used for rate limiting a given key for admin functionality
  function IdentityManager(uint _userTimeLock, uint _adminTimeLock, uint _adminRate, address relayAddress) {
    adminTimeLock = _adminTimeLock;
    userTimeLock = _userTimeLock;
    adminRate = _adminRate;
    relay = relayAddress;
  }

  // Factory function
  // gas 289,311
  function CreateIdentity(address owner, address recoveryKey) {
    if (recoveryKey == address(0)) throw;
    Proxy identity = new Proxy();
    owners[identity][owner] = now - adminTimeLock; // This is to ensure original owner has full power from day one
    recoveryKeys[identity] = recoveryKey;
    IdentityCreated(identity, msg.sender, owner,  recoveryKey);
  }

  // An identity Proxy can use this to register itself with the IdentityManager
  // Note they also have to change the owner of the Proxy over to this, but after calling this
  function registerIdentity(address owner, address recoveryKey) {
    if (recoveryKey == address(0)) throw;
    if (owners[msg.sender][owner] > 0 || recoveryKeys[msg.sender] > 0 ) throw; // Deny any funny business
    owners[msg.sender][owner] = now - adminTimeLock; // This is to ensure original owner has full power from day one
    recoveryKeys[msg.sender] = recoveryKey;
    IdentityCreated(msg.sender, msg.sender, owner, recoveryKey);
  }

  // Primary forward function
  function forwardTo(Proxy identity, address destination, uint value, bytes data, address sender) onlyRelay onlyOwner(identity, sender) {
    identity.forward(destination, value, data);
  }

  // an owner can add a new device instantly
  function addOwner(Proxy identity, address newOwner, address sender) onlyOlderOwner(identity, sender) rateLimited(identity, sender) {
    owners[identity][newOwner] = now;
    OwnerAdded(identity, newOwner, sender);
  }

  // a recovery key owner can add a new device with 1 days wait time
  function addOwnerForRecovery(Proxy identity, address newOwner, address sender) onlyRelay onlyRecovery(identity, sender) rateLimited(identity, sender) {
    if (owners[identity][newOwner] > 0) throw;
    owners[identity][newOwner] = now;
    OwnerAdded(identity, newOwner, sender);
  }

  // an owner can remove another owner instantly
  function removeOwner(Proxy identity, address owner, address sender) onlyRelay onlyOlderOwner(identity, sender) rateLimited(identity, sender) {
    owners[identity][owner] = 0;
    OwnerRemoved(identity, owner, sender);
  }

  // an owner can add change the recoverykey whenever they want to
  function changeRecovery(Proxy identity, address recoveryKey, address sender) onlyRelay onlyOlderOwner(identity, sender) rateLimited(identity, sender) {
    if (recoveryKey == address(0)) throw;
    recoveryKeys[identity] = recoveryKey;
    RecoveryChanged(identity, recoveryKey, sender);
  }

  // an owner can migrate away to a new IdentityManager
  function initiateMigration(Proxy identity, address newIdManager, address sender) onlyRelay onlyOlderOwner(identity, sender) {
    migrationInitiated[identity] = now;
    migrationNewAddress[identity] = newIdManager;
    MigrationInitiated(identity, newIdManager, sender);
  }

  // any owner can cancel a migration
  function cancelMigration(Proxy identity, address sender) onlyRelay onlyOwner(identity, sender) {
    address canceledManager = migrationNewAddress[identity];
    migrationInitiated[identity] = 0;
    migrationNewAddress[identity] = 0;
    MigrationCanceled(identity, canceledManager, sender);
  }

  // owner needs to finalize migration once adminTimeLock time has passed
  // WARNING: before transfering to a new address, make sure this address is "ready to recieve" the proxy.
  // Not doing so risks the proxy becoming stuck.
  function finalizeMigration(Proxy identity, address sender) onlyRelay onlyOlderOwner(identity, sender) {
    if (migrationInitiated[identity] > 0 && migrationInitiated[identity] + adminTimeLock < now) {
      address newIdManager = migrationNewAddress[identity];
      migrationInitiated[identity] = 0;
      migrationNewAddress[identity] = 0;
      identity.transfer(newIdManager);
      MigrationFinalized(identity, newIdManager, sender);
    }
  }
}
