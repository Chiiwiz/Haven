# Real Estate Investment Pool Contract

A Stacks blockchain smart contract that enables pooled property investment with automated rental income distribution among multiple investors.

## Overview

This contract allows multiple investors to pool funds for real estate investments and automatically distribute rental income based on their investment shares. It features management fees, dividend accumulation, and secure access controls.

## Features

- **Pooled Property Investment**: Multiple investors can participate in property purchases
- **Automated Dividend Distribution**: Rental income is automatically distributed based on investment shares
- **Management Fees**: Configurable management fees for property managers
- **Secure Access Controls**: Only authorized users can perform specific actions
- **Dividend Accumulation**: Investors can accumulate dividends and claim them when ready

## Contract Constants

- `MAX-MANAGEMENT-FEE`: 200 (20% maximum management fee)
- `SHARE-SCALE`: 1000 (100% = 1000 basis points)
- Maximum investors per property: 50

## Data Structures

### Properties Map
Stores property information:
- `property-id`: Unique property identifier
- `property-address`: Property address (max 128 characters)
- `primary-investor`: Principal who listed the property
- `purchase-cost`: Total cost to acquire the property
- `management-fee`: Fee percentage for property management
- `acquired`: Whether the property has been purchased
- `listed`: Whether the property is available for investment

### Investors Map
Tracks investor participation:
- `property-id` + `investor`: Composite key
- `investment-share`: Share of property ownership (out of 1000)
- `investor-type`: Type of investor (e.g., "primary", "co-investor")

### Dividend Pool Map
Manages accumulated dividends:
- `property-id` + `investor`: Composite key
- `accumulated`: Total accumulated dividends ready for withdrawal

## Public Functions

### Property Management

#### `list-property`
Creates a new property investment opportunity.

```clarity
(list-property (property-address (string-utf8 128)) (purchase-cost uint) (management-fee uint))
```

**Parameters:**
- `property-address`: Address of the property
- `purchase-cost`: Total cost to purchase the property
- `management-fee`: Management fee percentage (max 200 = 20%)

**Returns:** Property ID

**Validation:**
- Purchase cost must be greater than 0
- Management fee cannot exceed 20%
- Property address cannot be empty

#### `add-coinvestor`
Adds a co-investor to an existing property listing.

```clarity
(add-coinvestor (property-id uint) (coinvestor principal) (investment-share uint) (investor-type (string-ascii 32)))
```

**Parameters:**
- `property-id`: ID of the property
- `coinvestor`: Principal address of the co-investor
- `investment-share`: Share allocation (out of 1000)
- `investor-type`: Description of investor type

**Access:** Only primary investor can add co-investors

**Validation:**
- Property must exist and not be acquired
- Cannot add yourself as co-investor
- Investment share must be valid and available
- Investor type cannot be empty

#### `acquire-property`
Executes the property purchase.

```clarity
(acquire-property (property-id uint))
```

**Parameters:**
- `property-id`: ID of the property to acquire

**Validation:**
- Property must be listed and not already acquired
- Sender must have sufficient STX balance
- Transfers purchase cost to primary investor

#### `toggle-listing-status`
Toggles property availability for investment.

```clarity
(toggle-listing-status (property-id uint))
```

**Access:** Only primary investor

### Income Distribution

#### `distribute-rental-income`
Distributes rental income among all investors.

```clarity
(distribute-rental-income (property-id uint) (tenant principal) (rental-amount uint))
```

**Parameters:**
- `property-id`: ID of the property
- `tenant`: Principal address of the rent payer
- `rental-amount`: Total rental income to distribute

**Process:**
1. Calculates management fee based on property settings
2. Pays management fee to primary investor
3. Distributes remaining income to all investors based on their shares
4. Adds dividends to each investor's accumulated balance

**Validation:**
- Property must be acquired and listed
- Rental amount must be greater than 0
- Sender must have sufficient STX balance
- Tenant cannot be the sender

#### `claim-dividends`
Allows investors to withdraw their accumulated dividends.

```clarity
(claim-dividends (property-id uint))
```

**Parameters:**
- `property-id`: ID of the property

**Returns:** Amount claimed

**Validation:**
- Must have accumulated dividends greater than 0
- Resets dividend balance to 0 after claiming

## Read-Only Functions

### `get-property`
Retrieves property information.

```clarity
(get-property (property-id uint))
```

### `get-investor`
Gets investor information for a specific property.

```clarity
(get-investor (property-id uint) (investor principal))
```

### `get-dividends`
Checks accumulated dividends for an investor.

```clarity
(get-dividends (property-id uint) (investor principal))
```

### `get-property-investors`
Lists all investors for a property.

```clarity
(get-property-investors (property-id uint))
```

### `get-next-property-id`
Returns the next available property ID.

### `property-exists`
Checks if a property exists.

```clarity
(property-exists (property-id uint))
```

### `get-total-properties`
Returns the total number of properties created.

## Error Codes

- `ERR-ACCESS-DENIED` (100): Unauthorized access attempt
- `ERR-PROPERTY-MISSING` (101): Property does not exist
- `ERR-INVALID-DATA` (102): Invalid input parameters
- `ERR-ALREADY-PURCHASED` (103): Property already acquired
- `ERR-FUNDS-TOO-LOW` (104): Insufficient STX balance
- `ERR-NO-DIVIDENDS` (105): No dividends available to claim

## Usage Example

```clarity
;; 1. List a property
(contract-call? .real-estate-pool list-property 
  "123 Main St, City, State" 
  u1000000 ;; 1M microSTX
  u100)    ;; 10% management fee

;; 2. Add co-investors
(contract-call? .real-estate-pool add-coinvestor 
  u1 
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 
  u300 ;; 30% share
  "co-investor")

;; 3. Acquire the property
(contract-call? .real-estate-pool acquire-property u1)

;; 4. Distribute rental income
(contract-call? .real-estate-pool distribute-rental-income 
  u1 
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 ;; tenant
  u50000) ;; rental amount

;; 5. Claim dividends
(contract-call? .real-estate-pool claim-dividends u1)
```

## Security Features

- **Access Control**: Only primary investors can modify property settings and add co-investors
- **Input Validation**: Comprehensive validation of all inputs
- **Safe Math**: Uses Clarity's built-in safe arithmetic operations
- **Balance Checks**: Verifies sufficient funds before transfers
- **State Validation**: Ensures properties are in correct state for operations
