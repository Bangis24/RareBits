;; NFT Marketplace Protocol - Basic Trading Platform for Stacks
;; Stage 1: Core Features - Fixed Price Listings, Basic Sales, Marketplace Fees

;; Constants
(define-constant MARKETPLACE_OPERATOR tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u701))
(define-constant ERR_INVALID_PRICE (err u702))
(define-constant ERR_NFT_NOT_LISTED (err u703))
(define-constant ERR_LISTING_EXPIRED (err u704))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u708))

;; Data Variables
(define-data-var marketplace-fee uint u250) ;; 2.5% marketplace fee
(define-data-var platform-active bool true)
(define-data-var listing-counter uint u0)

;; Data Maps
(define-map nft-listings
  uint
  {
    seller: principal,
    nft-contract: principal,
    token-id: uint,
    price: uint,
    expires-at: uint,
    active: bool
  }
)

(define-map collection-stats
  principal
  {
    total-volume: uint,
    total-sales: uint,
    floor-price: uint,
    total-listings: uint
  }
)

(define-map marketplace-treasury
  (string-ascii 32)
  uint
)

;; Authorization Functions
(define-private (is-marketplace-operator)
  (is-eq tx-sender MARKETPLACE_OPERATOR)
)

;; Administrative Functions
(define-public (update-marketplace-fee (new-fee uint))
  (begin
    (asserts! (is-marketplace-operator) ERR_NOT_AUTHORIZED)
    (asserts! (<= new-fee u1000) ERR_INVALID_PRICE) ;; Max 10% fee
    (var-set marketplace-fee new-fee)
    (ok new-fee)
  )
)

(define-public (toggle-platform-status)
  (begin
    (asserts! (is-marketplace-operator) ERR_NOT_AUTHORIZED)
    (var-set platform-active (not (var-get platform-active)))
    (ok (var-get platform-active))
  )
)

;; Core Listing Functions
(define-public (create-listing
  (nft-contract principal)
  (token-id uint)
  (price uint)
  (duration uint))
  (let (
    (listing-id (+ (var-get listing-counter) u1))
  )
    (asserts! (var-get platform-active) ERR_NOT_AUTHORIZED)
    (asserts! (> price u0) ERR_INVALID_PRICE)
    (asserts! (> duration u0) ERR_INVALID_PRICE)
    
    ;; Create listing
    (map-set nft-listings listing-id {
      seller: tx-sender,
      nft-contract: nft-contract,
      token-id: token-id,
      price: price,
      expires-at: (+ block-height duration),
      active: true
    })
    
    ;; Update counter
    (var-set listing-counter listing-id)
    
    ;; Update collection stats
    (update-collection-listing-stats nft-contract price)
    
    (print {
      event: "listing-created",
      listing-id: listing-id,
      seller: tx-sender,
      nft-contract: nft-contract,
      token-id: token-id,
      price: price,
      expires-at: (+ block-height duration)
    })
    
    (ok listing-id)
  )
)

(define-public (purchase-nft (listing-id uint))
  (let (
    (listing-data (unwrap! (map-get? nft-listings listing-id) ERR_NFT_NOT_LISTED))
    (marketplace-fee-amount (/ (* (get price listing-data) (var-get marketplace-fee)) u10000))
    (seller-amount (- (get price listing-data) marketplace-fee-amount))
  )
    (asserts! (get active listing-data) ERR_NFT_NOT_LISTED)
    (asserts! (< block-height (get expires-at listing-data)) ERR_LISTING_EXPIRED)
    
    ;; Mark listing as inactive
    (map-set nft-listings listing-id (merge listing-data {active: false}))
    
    ;; Update marketplace treasury
    (map-set marketplace-treasury "trading-fees" 
      (+ (default-to u0 (map-get? marketplace-treasury "trading-fees")) marketplace-fee-amount))
    
    ;; Update collection stats
    (update-collection-sale-stats (get nft-contract listing-data) (get price listing-data))
    
    (print {
      event: "nft-purchased",
      listing-id: listing-id,
      buyer: tx-sender,
      seller: (get seller listing-data),
      price: (get price listing-data),
      marketplace-fee: marketplace-fee-amount
    })
    
    (ok {seller-amount: seller-amount, marketplace-fee: marketplace-fee-amount})
  )
)

(define-public (cancel-listing (listing-id uint))
  (let (
    (listing-data (unwrap! (map-get? nft-listings listing-id) ERR_NFT_NOT_LISTED))
  )
    (asserts! (is-eq tx-sender (get seller listing-data)) ERR_NOT_AUTHORIZED)
    (asserts! (get active listing-data) ERR_NFT_NOT_LISTED)
    
    ;; Mark listing as inactive
    (map-set nft-listings listing-id (merge listing-data {active: false}))
    
    (print {
      event: "listing-cancelled",
      listing-id: listing-id,
      seller: tx-sender
    })
    
    (ok true)
  )
)

;; Helper Functions
(define-private (update-collection-listing-stats (collection principal) (price uint))
  (let (
    (current-stats (default-to {total-volume: u0, total-sales: u0, floor-price: u999999999, total-listings: u0} 
                              (map-get? collection-stats collection)))
  )
    (map-set collection-stats collection (merge current-stats {
      total-listings: (+ (get total-listings current-stats) u1),
      floor-price: (if (< price (get floor-price current-stats)) price (get floor-price current-stats))
    }))
  )
)

(define-private (update-collection-sale-stats (collection principal) (price uint))
  (let (
    (current-stats (default-to {total-volume: u0, total-sales: u0, floor-price: u999999999, total-listings: u0} 
                              (map-get? collection-stats collection)))
    (new-total-sales (+ (get total-sales current-stats) u1))
    (new-total-volume (+ (get total-volume current-stats) price))
  )
    (map-set collection-stats collection (merge current-stats {
      total-volume: new-total-volume,
      total-sales: new-total-sales
    }))
  )
)

;; View Functions
(define-read-only (get-listing-details (listing-id uint))
  (map-get? nft-listings listing-id)
)

(define-read-only (get-collection-stats (collection principal))
  (map-get? collection-stats collection)
)

(define-read-only (get-marketplace-metrics)
  {
    marketplace-fee: (var-get marketplace-fee),
    platform-active: (var-get platform-active),
    listing-counter: (var-get listing-counter),
    total-trading-fees: (default-to u0 (map-get? marketplace-treasury "trading-fees"))
  }
)

(define-read-only (calculate-fees (price uint))
  (let (
    (marketplace-fee-amount (/ (* price (var-get marketplace-fee)) u10000))
  )
    {
      marketplace-fee: marketplace-fee-amount,
      seller-amount: (- price marketplace-fee-amount)
    }
  )
)

(define-read-only (is-listing-active (listing-id uint))
  (match (map-get? nft-listings listing-id)
    listing-data (and (get active listing-data) (< block-height (get expires-at listing-data)))
    false
  )
)