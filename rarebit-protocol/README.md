# RareBits Protocol

**RareBits Protocol** is an advanced NFT Marketplace smart contract built on the Stacks blockchain. It supports fixed-price listings, auctions, fractional ownership, royalty distributions, lending pools, and real-time collection and user analytics.

## 🔗 Overview

RareBits Protocol enables a decentralized NFT trading experience that empowers both creators and collectors with:

- **Fixed-price sales**
- **Auction bidding with auto-extension**
- **Fractional NFT ownership**
- **Royalty management**
- **NFT-backed lending**
- **Verified collections and analytics**

## ⚙️ Features

### ✅ Fixed-Price Listings
Buy and sell NFTs at a fixed price with royalty and marketplace fee support.

### 🕒 Auction Listings
Time-based auctions with reserve price, auto-extend, and bid tracking.

### 🧩 Fractional Ownership
Split NFTs into shares for collaborative ownership and future buyouts.

### 💰 Lending Pools
Lend or borrow against NFTs using trustless loan contracts with interest rates and collateral.

### 📊 Analytics Engine
Track floor prices, average prices, volume traded, user reputation, and collection stats.

---

## 📄 Contract Details

| Key Constant | Description |
|--------------|-------------|
| `MARKETPLACE_OPERATOR` | Contract deployer/operator |
| `marketplace-fee` | Default: `u250` (2.5%) |
| `royalty-percentage` | Max: 20% (2000 basis points) |

---

## 🧪 Core Functions

### 📈 Listings

- `create-fixed-price-listing(...)`  
  List NFTs at a fixed price.

- `purchase-fixed-price-nft(...)`  
  Purchase listed NFTs and trigger fee + royalty logic.

### ⏱️ Auctions

- `create-auction-listing(...)`  
  Start an auction with reserve price and duration.

- `place-bid(...)`  
  Bid on active auctions with minimum bid increment logic.

- `finalize-auction(...)`  
  Finalize the auction after its end block.

### 🔗 Fractionalization

- `create-fractional-listing(...)`  
  Offer NFT shares to users.

- `purchase-shares(...)`  
  Buy shares of a fractional NFT.

### 🏦 Lending

- `create-lending-pool(...)`  
  Set terms and NFT collateral for loans.

- `accept-loan(...)`  
  Accept an existing loan offer as a borrower.

---

## 🔐 Admin & Verification

- `verify-collection(...)`  
  Operator-only function to verify trusted NFT contracts.

- `update-marketplace-fee(...)`  
  Update the platform fee (max 10%).

- `toggle-platform-status()`  
  Enable or disable trading activities.

---

## 🔍 View Functions

- `get-listing-details(listing-id)`
- `get-auction-details(auction-id)`
- `get-fractional-details(fraction-id)`
- `get-loan-details(loan-id)`
- `get-collection-stats(collection)`
- `get-user-stats(user)`
- `get-marketplace-metrics()`
- `get-pending-royalties(recipient, collection)`
- `calculate-total-fees(price, royalty-percentage)`

---

## 🧾 Royalty & Treasury Accounting

All royalties are stored in a `pending-royalty-payments` map and can be aggregated by recipient and collection. Trading fees accumulate in the `marketplace-treasury` under the `"trading-fees"` key.

---

## 🚀 Getting Started

1. **Deploy the contract** on a Clarity-compatible environment (e.g., Hiro Web IDE or Stacks testnet).
2. **Verify NFT collections** using the `verify-collection` function.
3. **Start listing NFTs**, hosting auctions, or creating fractional ownership opportunities.
