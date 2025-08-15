# Gene Vault Registry
### Decentralized IP & Patent Licensing

A Stacks blockchain smart contract for tokenizing and licensing biotechnology intellectual property (IP) as Non-Fungible Tokens (NFTs). This contract enables IP owners to mint, transfer, and create royalty-bearing licenses for their biotechnology assets.

## Features

- **NFT-based IP Tokenization**: Convert biotechnology IP into tradeable NFTs
- **Licensing System**: Create and manage IP licenses with upfront fees and ongoing royalties
- **Metadata Management**: Store IP metadata on-chain with optional freezing for immutability
- **Royalty Payments**: Built-in system for licensees to pay ongoing royalties to IP owners
- **SIP-009 Compliance**: Fully compliant with the Stacks NFT standard

## Contract Overview

The Gene Vault Registry contract implements the SIP-009 NFT standard and provides additional functionality specific to intellectual property licensing:

### Core Components

1. **NFT Management**: Mint, transfer, and track ownership of IP-NFTs
2. **Licensing Marketplace**: List IPs for licensing with custom terms
3. **Royalty System**: Track and facilitate ongoing royalty payments
4. **Metadata Storage**: On-chain storage of IP details with optional immutability

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) v0.31.1 or compatible
- Stacks blockchain knowledge
- Understanding of NFTs and smart contracts

### Installation

1. Clone the repository or copy the contract file
2. Place `gene-vault-registry.clar` in your `contracts/` directory
3. Run contract checks:

```bash
clarinet check
```

## Contract Functions

### NFT Standard Functions (SIP-009)

#### `get-last-token-id`
Returns the ID of the last minted token.

```clarity
(get-last-token-id) -> (response uint uint)
```

#### `get-token-uri`
Returns the metadata URI for a token (returns none as metadata is stored on-chain).

```clarity
(get-token-uri (token-id uint)) -> (response (optional (string-ascii 256)) uint)
```

#### `get-owner`
Returns the owner of a specific token.

```clarity
(get-owner (token-id uint)) -> (response (optional principal) uint)
```

#### `transfer`
Transfers a token from sender to recipient.

```clarity
(transfer (token-id uint) (sender principal) (recipient principal)) -> (response bool uint)
```

### IP Management Functions

#### `mint-ip-nft`
**Owner Only**: Mints a new IP NFT with metadata.

```clarity
(mint-ip-nft 
  (recipient principal) 
  (name (string-ascii 256)) 
  (description (string-utf8 1024)) 
  (metadata-hash (buff 32))
) -> (response uint uint)
```

**Parameters:**
- `recipient`: The principal who will own the new IP NFT
- `name`: The name of the intellectual property
- `description`: Detailed description of the IP
- `metadata-hash`: Hash of off-chain documentation (e.g., patent filings)

#### `freeze-metadata`
**IP Owner Only**: Makes the metadata immutable.

```clarity
(freeze-metadata (ip-id uint)) -> (response bool uint)
```

### Licensing Functions

#### `list-for-license`
**IP Owner Only**: Lists an IP NFT for licensing.

```clarity
(list-for-license 
  (ip-id uint) 
  (license-fee uint) 
  (royalty-percent uint)
) -> (response bool uint)
```

**Parameters:**
- `ip-id`: The ID of the IP NFT to license
- `license-fee`: Upfront cost in microSTX (uSTX)
- `royalty-percent`: Percentage of future revenue (0-100)

#### `remove-license-listing`
**IP Owner Only**: Removes a license listing.

```clarity
(remove-license-listing (ip-id uint)) -> (response bool uint)
```

#### `execute-license`
**Public**: Purchase a license by paying the required fee.

```clarity
(execute-license (ip-id uint)) -> (response bool uint)
```

#### `pay-royalty`
**Licensee Only**: Pay royalties to the IP owner.

```clarity
(pay-royalty (ip-id uint) (royalty-amount uint)) -> (response bool uint)
```

#### `revoke-license`
**IP Owner Only**: Revoke an active license.

```clarity
(revoke-license (ip-id uint) (licensee principal)) -> (response bool uint)
```

### Read-Only Functions

#### `get-ip-details`
Get metadata for a specific IP NFT.

```clarity
(get-ip-details (ip-id uint)) -> (optional {name: (string-ascii 256), description: (string-utf8 1024), metadata-hash: (buff 32), metadata-frozen: bool})
```

#### `get-license-listing`
Get details of a license listing.

```clarity
(get-license-listing (ip-id uint)) -> (optional {licensor: principal, license-fee: uint, royalty-percent: uint, active: bool})
```

#### `get-licensee-status`
Check the status of an active license.

```clarity
(get-licensee-status (ip-id uint) (licensee principal)) -> (optional {license-start-block: uint, royalties-paid: uint, active: bool})
```

#### `get-total-royalties-paid`
Get total royalties paid by a licensee for specific IP.

```clarity
(get-total-royalties-paid (ip-id uint) (licensee principal)) -> (optional uint)
```

#### `token-exists`
Check if a token exists.

```clarity
(token-exists (token-id uint)) -> bool
```

#### `get-contract-info`
Get general contract information.

```clarity
(get-contract-info) -> {contract-owner: principal, total-tokens: uint}
```

## Usage Examples

### Minting an IP NFT

```clarity
;; Only contract owner can mint
(contract-call? .gene-vault-registry mint-ip-nft 
  'SP1EXAMPLE... 
  "Gene Therapy Patent X1"
  u"Revolutionary gene therapy technique for treating genetic disorders"
  0x1234567890abcdef...)
```

### Listing for License

```clarity
;; IP owner lists their NFT for licensing
(contract-call? .gene-vault-registry list-for-license 
  u1                    ;; IP ID
  u1000000             ;; 1 STX license fee
  u5)                  ;; 5% royalty
```

### Executing a License

```clarity
;; Anyone can execute a license by paying the fee
(contract-call? .gene-vault-registry execute-license u1)
```

### Paying Royalties

```clarity
;; Licensee pays royalties
(contract-call? .gene-vault-registry pay-royalty 
  u1        ;; IP ID
  u100000)  ;; 0.1 STX royalty payment
```

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 100 | `ERR-NOT-AUTHORIZED` | Caller not authorized for this action |
| 101 | `ERR-NOT-FOUND` | Token or resource not found |
| 102 | `ERR-ALREADY-LICENSED` | License already exists for this user |
| 103 | `ERR-NOT-OWNER` | Caller is not the owner of the token |
| 104 | `ERR-LISTING-NOT-FOUND` | License listing not found or inactive |
| 105 | `ERR-INCORRECT-PAYMENT` | Payment amount incorrect |
| 106 | `ERR-LICENSE-INACTIVE` | License is not active |
| 107 | `ERR-METADATA-FROZEN` | Metadata is already frozen |
| 108 | `ERR-INVALID-ROYALTY` | Royalty percentage exceeds 100% |
| 109 | `ERR-ZERO-AMOUNT` | Amount must be greater than zero |
| 110 | `ERR-INVALID-TOKEN-ID` | Invalid token ID or parameters |

## Events

The contract emits the following events for tracking:

- `nft-mint`: When a new IP NFT is minted
- `nft-transfer`: When an IP NFT is transferred
- `license-listing`: When an IP is listed for licensing
- `license-delisted`: When a license listing is removed
- `license-executed`: When a license is purchased
- `license-revoked`: When a license is revoked
- `royalty-paid`: When royalties are paid
- `metadata-frozen`: When metadata is made immutable

## Security Features

- **Owner-only minting**: Only contract owner can mint new IP NFTs
- **Input validation**: All functions validate inputs before execution
- **Transfer restrictions**: Prevents invalid transfers and self-transfers
- **License exclusivity**: Each IP can only be licensed once (exclusive licensing)
- **Royalty tracking**: Comprehensive tracking of all royalty payments
- **Metadata protection**: Optional metadata freezing for immutability

## Testing

To test the contract:

1. **Check syntax and warnings**:
   ```bash
   clarinet check
   ```

2. **Run unit tests** (create test files in `tests/`):
   ```bash
   clarinet test
   ```

3. **Deploy to local testnet**:
   ```bash
   clarinet integrate
   ```

## Development Notes

- Contract is compatible with Clarinet v0.31.1
- Uses built-in NFT functions for gas efficiency
- Implements exclusive licensing model (can be modified for multiple licenses)
- All metadata stored on-chain for transparency
- Royalty payments are voluntary but tracked

## Deployment

1. **Local deployment**:
   ```bash
   clarinet deploy --local
   ```

2. **Testnet deployment**:
   ```bash
   clarinet deploy --testnet
   ```

3. **Mainnet deployment**:
   ```bash
   clarinet deploy --mainnet
   ```

## License

This smart contract is provided as-is for educational and development purposes. Please ensure proper legal review before using in production environments.

## Contributing

Contributions are welcome! Please ensure:
- All code passes `clarinet check` without warnings
- Comprehensive testing of new features
- Clear documentation of changes
- Security considerations are addressed

## Support

For questions or issues:
- Review the error codes and function documentation
- Check the Clarinet documentation
- Review Stacks blockchain documentation for SIP-009 standard

---

**⚠️ Important**: This contract handles valuable intellectual property and financial transactions. Always conduct thorough testing and security audits before production deployment.