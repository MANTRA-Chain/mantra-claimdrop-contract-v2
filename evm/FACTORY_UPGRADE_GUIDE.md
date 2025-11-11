# ClaimdropFactory Upgradeable Deployment Guide

## Overview

The ClaimdropFactory is now an upgradeable contract using OpenZeppelin's TransparentUpgradeableProxy pattern. This allows for future upgrades while maintaining state and deployed Claimdrop addresses.

## Architecture

The upgradeable system consists of three main components:

1. **Implementation Contract** (`ClaimdropFactory`): Contains the actual logic
2. **Proxy Contract** (`TransparentUpgradeableProxy`): Points to the implementation and maintains state
3. **ProxyAdmin Contract**: Manages upgrades to the proxy

## Deployment

### Initial Deployment

To deploy the upgradeable ClaimdropFactory:

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
# OR use Ledger
export USE_LEDGER=true
export LEDGER_ADDRESS=your_ledger_address

# Deploy the factory with proxy
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

This will deploy:
- ClaimdropFactory implementation contract
- ProxyAdmin contract (owned by deployer)
- TransparentUpgradeableProxy contract

The proxy address is what users will interact with for all factory operations.

### Deployment Outputs

After deployment, you'll receive three important addresses:
- **Implementation**: The ClaimdropFactory logic contract
- **ProxyAdmin**: The admin contract that can upgrade the proxy
- **Proxy**: The address users interact with (ClaimdropFactory)

**Important**: Save the ProxyAdmin and Proxy addresses - you'll need them for upgrades!

## Upgrading

### Upgrade Process

To upgrade the ClaimdropFactory to a new implementation:

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export PROXY_ADDRESS=0x... # Address of the TransparentUpgradeableProxy
export PROXY_ADMIN_ADDRESS=0x... # Address of the ProxyAdmin

# OR use Ledger
export USE_LEDGER=true
export LEDGER_ADDRESS=your_ledger_address

# Execute upgrade
forge script script/UpgradeFactory.s.sol:UpgradeFactory \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### What Happens During Upgrade

1. A new implementation contract is deployed
2. The ProxyAdmin updates the proxy to point to the new implementation
3. All state (deployed claimdrops, mappings) is preserved
4. The proxy address remains unchanged

## Testing

The test suite includes comprehensive tests for the upgradeable functionality:

```bash
# Run all factory tests
forge test --match-contract ClaimdropFactoryTest -vv
```

Test coverage includes:
- ✅ Basic factory operations (deploy, track claimdrops)
- ✅ Pause/unpause functionality
- ✅ Ownership controls
- ✅ Initialization protection (cannot reinitialize)
- ✅ Implementation initialization protection
- ✅ Upgrade functionality
- ✅ State preservation after upgrade
- ✅ ProxyAdmin ownership controls

## Security Considerations

### Initialization
- The implementation contract is initialized with `_disableInitializers()` in the constructor to prevent direct initialization
- The proxy is initialized only once during deployment
- Subsequent calls to `initialize()` will fail

### Upgrade Authority
- Only the ProxyAdmin owner can upgrade the implementation
- The ProxyAdmin is owned by the deployer address
- Transfer ProxyAdmin ownership carefully using `ProxyAdmin.transferOwnership()`

### State Preservation
- All state variables are preserved across upgrades
- New implementation must maintain storage layout compatibility
- Never remove or reorder existing state variables in upgrades

## Best Practices

### Before Upgrading

1. **Test thoroughly**: Deploy new implementation on testnet first
2. **Verify storage compatibility**: Ensure new variables are added at the end
3. **Audit new code**: Have security experts review changes
4. **Backup critical data**: Record current state before upgrade

### After Upgrading

1. **Verify upgrade**: Check that the proxy points to the new implementation
2. **Test functionality**: Ensure all existing functions work correctly
3. **Monitor**: Watch for any unexpected behavior

## Common Operations

### Check Current Implementation

```solidity
// From ProxyAdmin
address currentImpl = proxyAdmin.getProxyImplementation(
    ITransparentUpgradeableProxy(proxyAddress)
);
```

### Transfer ProxyAdmin Ownership

```bash
cast send $PROXY_ADMIN_ADDRESS \
  "transferOwnership(address)" $NEW_OWNER \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

### Check Factory Owner

```bash
cast call $PROXY_ADDRESS "owner()" --rpc-url $RPC_URL
```

## Troubleshooting

### "Address: low-level delegate call failed"
- Ensure new implementation is properly initialized (uses `_disableInitializers()`)
- Check that you're using `upgrade()` not `upgradeAndCall()` for simple upgrades

### "Ownable: caller is not the owner"
- Verify you're calling from the ProxyAdmin owner address
- Check ProxyAdmin ownership with `proxyAdmin.owner()`

### Storage Layout Issues
- Never remove or reorder existing state variables
- Always add new variables at the end
- Use storage gaps for future-proofing if needed

## Additional Resources

- [OpenZeppelin Upgrades Documentation](https://docs.openzeppelin.com/upgrades-plugins/)
- [TransparentUpgradeableProxy Pattern](https://docs.openzeppelin.com/contracts/api/proxy#TransparentUpgradeableProxy)
- [Writing Upgradeable Contracts](https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable)

