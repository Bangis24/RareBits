;; NFT Marketplace Protocol - Advanced Trading Platform for Stacks

;; Constants
(define-constant MARKETPLACE_OPERATOR tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u701))
(define-constant ERR_INVALID_PRICE (err u702))
(define-constant ERR_NFT_NOT_LISTED (err u703))
(define-constant ERR_AUCTION_ENDED (err u704))
(define-constant ERR_BID_TOO_LOW (err u705))
(define-constant ERR_AUCTION_ACTIVE (err u706))
(define-constant ERR_INVALID_ROYALTY (err u707))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u708))
(define-constant ERR_FRACTION_NOT_AVAILABLE (err u709))
(define-constant ERR_LOAN_ACTIVE (err u710))
(define-constant ERR_COLLECTION_NOT_VERIFIED (err u711))

;; Data Variables
(define-data-var marketplace-fee uint u250) ;; 2.5% marketplace fee
(define-data-var platform-active bool true)
(define-data-var listing-counter uint u0)
(define-data-var auction-counter uint u0)
(define-data-var fraction-counter uint u0)
(define-data-var loan-counter uint u0)

;; Data Maps
(define-map nft-listings
  uint
  {
    seller: principal,
    nft-contract: principal,
    token-id: uint,
    price: uint,
    listing-type: (string-ascii 16), ;; "fixed", "auction", "fractional"
    expires-at: uint,
    active: bool,
    royalty-recipient: (optional principal),
    royalty-percentage: uint
  }
)

(define-map auction-details
  uint
  {
    listing-id: uint,
    starting-price: uint,
    current-bid: uint,
    highest-bidder: (optional principal),
    bid-count: uint,
    auction-end: uint,
    reserve-met: bool,
    auto-extend: bool
  }
)

(define-map fractional-ownership
  uint
  {
    listing-id: uint,
    total-shares: uint,
    shares-sold: uint,
    price-per-share: uint,
    share-holders: (list 50 {holder: principal, shares: uint}),
    trading-enabled: bool,
    buyout-price: uint
  }
)

(define-map nft-lending-pools
  uint
  {
    lender: principal,
    nft-contract: principal,
    token-id: uint,
    loan-amount: uint,
    interest-rate: uint, ;; basis points
    loan-duration: uint, ;; blocks
    borrower: (optional principal),
    loan-start: uint,
    collateral-value: uint,
    loan-active: bool
  }
)

(define-map verified-collections principal bool)
(define-map collection-analytics
  principal
  {
    total-volume: uint,
    total-sales: uint,
    floor-price: uint,
    average-price: uint,
    last-sale-price: uint,
    total-listings: uint
  }
)

(define-map user-trading-stats
  principal
  {
    total-purchases: uint,
    total-sales: uint,
    volume-traded: uint,
    successful-auctions: uint,
    reputation-score: uint
  }
)

(define-map pending-royalty-payments
  {recipient: principal, collection: principal}
  uint
)

(define-map marketplace-treasury
  (string-ascii 32)
  uint
)

;; Authorization Functions
(define-private (is-marketplace-operator)
  (is-eq tx-sender MARKETPLACE_OPERATOR)
)

(define-private (is-collection-verified (collection principal))
  (default-to false (map-get? verified-collections collection))
)

;; Administrative Functions
(define-public (verify-collection (collection-contract principal))
  (begin
    (asserts! (is-marketplace-operator) ERR_NOT_AUTHORIZED)
    (map-set verified-collections collection-contract true)
    (print {event: "collection-verified", contract: collection-contract})
    (ok true)
  )
)

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
(define-public (create-fixed-price-listing
  (nft-contract principal)
  (token-id uint)
  (price uint)
  (duration uint)
  (royalty-recipient (optional principal))
  (royalty-percentage uint))
  (let (
    (listing-id (+ (var-get listing-counter) u1))
  )
    (asserts! (var-get platform-active) ERR_NOT_AUTHORIZED)
    (asserts! (> price u0) ERR_INVALID_PRICE)
    (asserts! (<= royalty-percentage u2000) ERR_INVALID_ROYALTY) ;; Max 20% royalty
    
    ;; Create listing
    (map-set nft-listings listing-id {
      seller: tx-sender,
      nft-contract: nft-contract,
      token-id: token-id,
      price: price,
      listing-type: "fixed",
      expires-at: (+ block-height duration),
      active: true,
      royalty-recipient: royalty-recipient,
      royalty-percentage: royalty-percentage
    })
    
    ;; Update counter
    (var-set listing-counter listing-id)
    
    ;; Update collection analytics
    (update-collection-listing-stats nft-contract price)
    
    (print {
      event: "fixed-price-listing-created",
      listing-id: listing-id,
      seller: tx-sender,
      nft-contract: nft-contract,
      token-id: token-id,
      price: price
    })
    
    (ok listing-id)
  )
)

(define-public (purchase-fixed-price-nft (listing-id uint) (payment-amount uint))
  (let (
    (listing-data (unwrap! (map-get? nft-listings listing-id) ERR_NFT_NOT_LISTED))
    (marketplace-fee-amount (/ (* (get price listing-data) (var-get marketplace-fee)) u10000))
    (royalty-amount (/ (* (get price listing-data) (get royalty-percentage listing-data)) u10000))
    (seller-amount (- (- (get price listing-data) marketplace-fee-amount) royalty-amount))
  )
    (asserts! (get active listing-data) ERR_NFT_NOT_LISTED)
    (asserts! (< block-height (get expires-at listing-data)) ERR_AUCTION_ENDED)
    (asserts! (is-eq (get listing-type listing-data) "fixed") ERR_NFT_NOT_LISTED)
    (asserts! (>= payment-amount (get price listing-data)) ERR_INSUFFICIENT_PAYMENT)
    
    ;; Mark listing as inactive
    (map-set nft-listings listing-id (merge listing-data {active: false}))
    
    ;; Process royalty payment
    (match (get royalty-recipient listing-data)
      recipient (map-set pending-royalty-payments 
                  {recipient: recipient, collection: (get nft-contract listing-data)} 
                  (+ (default-to u0 (map-get? pending-royalty-payments {recipient: recipient, collection: (get nft-contract listing-data)})) royalty-amount))
      true
    )
    
    ;; Update marketplace treasury
    (map-set marketplace-treasury "trading-fees" 
      (+ (default-to u0 (map-get? marketplace-treasury "trading-fees")) marketplace-fee-amount))
    
    ;; Update collection analytics
    (update-collection-sale-stats (get nft-contract listing-data) (get price listing-data))
    
    ;; Update user trading stats
    (update-user-trading-stats tx-sender (get seller listing-data) (get price listing-data))
    
    (print {
      event: "nft-purchased",
      listing-id: listing-id,
      buyer: tx-sender,
      seller: (get seller listing-data),
      price: (get price listing-data),
      marketplace-fee: marketplace-fee-amount,
      royalty-amount: royalty-amount
    })
    
    (ok {seller-amount: seller-amount, marketplace-fee: marketplace-fee-amount, royalty-amount: royalty-amount})
  )
)

;; Auction Functions
(define-public (create-auction-listing
  (nft-contract principal)
  (token-id uint)
  (starting-price uint)
  (reserve-price uint)
  (duration uint)
  (auto-extend bool)
  (royalty-recipient (optional principal))
  (royalty-percentage uint))
  (let (
    (listing-id (+ (var-get listing-counter) u1))
    (auction-id (+ (var-get auction-counter) u1))
  )
    (asserts! (var-get platform-active) ERR_NOT_AUTHORIZED)
    (asserts! (> starting-price u0) ERR_INVALID_PRICE)
    (asserts! (>= reserve-price starting-price) ERR_INVALID_PRICE)
    (asserts! (<= royalty-percentage u2000) ERR_INVALID_ROYALTY)
    
    ;; Create listing
    (map-set nft-listings listing-id {
      seller: tx-sender,
      nft-contract: nft-contract,
      token-id: token-id,
      price: reserve-price,
      listing-type: "auction",
      expires-at: (+ block-height duration),
      active: true,
      royalty-recipient: royalty-recipient,
      royalty-percentage: royalty-percentage
    })
    
    ;; Create auction details
    (map-set auction-details auction-id {
      listing-id: listing-id,
      starting-price: starting-price,
      current-bid: u0,
      highest-bidder: none,
      bid-count: u0,
      auction-end: (+ block-height duration),
      reserve-met: (is-eq reserve-price starting-price),
      auto-extend: auto-extend
    })
    
    ;; Update counters
    (var-set listing-counter listing-id)
    (var-set auction-counter auction-id)
    
    (print {
      event: "auction-listing-created",
      listing-id: listing-id,
      auction-id: auction-id,
      seller: tx-sender,
      starting-price: starting-price,
      reserve-price: reserve-price,
      duration: duration
    })
    
    (ok {listing-id: listing-id, auction-id: auction-id})
  )
)

(define-public (place-bid (auction-id uint) (bid-amount uint))
  (let (
    (auction-data (unwrap! (map-get? auction-details auction-id) ERR_NFT_NOT_LISTED))
    (listing-data (unwrap! (map-get? nft-listings (get listing-id auction-data)) ERR_NFT_NOT_LISTED))
    (minimum-bid (+ (get current-bid auction-data) (/ (get current-bid auction-data) u20))) ;; 5% minimum increase
  )
    (asserts! (get active listing-data) ERR_NFT_NOT_LISTED)
    (asserts! (< block-height (get auction-end auction-data)) ERR_AUCTION_ENDED)
    (asserts! (> bid-amount (get current-bid auction-data)) ERR_BID_TOO_LOW)
    (asserts! (>= bid-amount minimum-bid) ERR_BID_TOO_LOW)
    
    ;; Auto-extend auction if bid placed in last 10 blocks
    (let (
      (new-end (if (and (get auto-extend auction-data) 
                       (< (- (get auction-end auction-data) block-height) u10))
                 (+ block-height u144) ;; Extend by 1 day
                 (get auction-end auction-data)))
      (reserve-met (>= bid-amount (get price listing-data)))
    )
      ;; Update auction with new bid
      (map-set auction-details auction-id (merge auction-data {
        current-bid: bid-amount,
        highest-bidder: (some tx-sender),
        bid-count: (+ (get bid-count auction-data) u1),
        auction-end: new-end,
        reserve-met: reserve-met
      }))
      
      (print {
        event: "bid-placed",
        auction-id: auction-id,
        bidder: tx-sender,
        bid-amount: bid-amount,
        auction-extended: (not (is-eq new-end (get auction-end auction-data)))
      })
      
      (ok bid-amount)
    )
  )
)

(define-public (finalize-auction (auction-id uint))
  (let (
    (auction-data (unwrap! (map-get? auction-details auction-id) ERR_NFT_NOT_LISTED))
    (listing-data (unwrap! (map-get? nft-listings (get listing-id auction-data)) ERR_NFT_NOT_LISTED))
  )
    (asserts! (>= block-height (get auction-end auction-data)) ERR_AUCTION_ACTIVE)
    (asserts! (get active listing-data) ERR_NFT_NOT_LISTED)
    
    (if (get reserve-met auction-data)
      ;; Successful auction
      (let (
        (final-price (get current-bid auction-data))
        (marketplace-fee-amount (/ (* final-price (var-get marketplace-fee)) u10000))
        (royalty-amount (/ (* final-price (get royalty-percentage listing-data)) u10000))
        (seller-amount (- (- final-price marketplace-fee-amount) royalty-amount))
      )
        ;; Mark listing as inactive
        (map-set nft-listings (get listing-id auction-data) (merge listing-data {active: false}))
        
        ;; Process payments (same as fixed price)
        (match (get royalty-recipient listing-data)
          recipient (map-set pending-royalty-payments 
                      {recipient: recipient, collection: (get nft-contract listing-data)} 
                      (+ (default-to u0 (map-get? pending-royalty-payments {recipient: recipient, collection: (get nft-contract listing-data)})) royalty-amount))
          true
        )
        
        ;; Update stats
        (update-collection-sale-stats (get nft-contract listing-data) final-price)
        (match (get highest-bidder auction-data)
          winner (update-user-trading-stats winner (get seller listing-data) final-price)
          true
        )
        
        (print {
          event: "auction-finalized-successful",
          auction-id: auction-id,
          winner: (get highest-bidder auction-data),
          final-price: final-price
        })
        
        (ok {successful: true, final-price: final-price, winner: (get highest-bidder auction-data)})
      )
      ;; Failed auction - reserve not met
      (begin
        (map-set nft-listings (get listing-id auction-data) (merge listing-data {active: false}))
        (print {event: "auction-finalized-failed", auction-id: auction-id})
        (ok {successful: false, final-price: u0, winner: none})
      )
    )
  )
)

;; Fractional Ownership Functions
(define-public (create-fractional-listing
  (nft-contract principal)
  (token-id uint)
  (total-shares uint)
  (price-per-share uint)
  (buyout-price uint)
  (royalty-recipient (optional principal))
  (royalty-percentage uint))
  (let (
    (listing-id (+ (var-get listing-counter) u1))
    (fraction-id (+ (var-get fraction-counter) u1))
  )
    (asserts! (var-get platform-active) ERR_NOT_AUTHORIZED)
    (asserts! (and (> total-shares u0) (<= total-shares u10000)) ERR_INVALID_PRICE)
    (asserts! (> price-per-share u0) ERR_INVALID_PRICE)
    (asserts! (> buyout-price (* total-shares price-per-share)) ERR_INVALID_PRICE)
    
    ;; Create listing
    (map-set nft-listings listing-id {
      seller: tx-sender,
      nft-contract: nft-contract,
      token-id: token-id,
      price: (* total-shares price-per-share),
      listing-type: "fractional",
      expires-at: u0, ;; No expiry for fractional
      active: true,
      royalty-recipient: royalty-recipient,
      royalty-percentage: royalty-percentage
    })
    
    ;; Create fractional ownership details
    (map-set fractional-ownership fraction-id {
      listing-id: listing-id,
      total-shares: total-shares,
      shares-sold: u0,
      price-per-share: price-per-share,
      share-holders: (list),
      trading-enabled: true,
      buyout-price: buyout-price
    })
    
    ;; Update counters
    (var-set listing-counter listing-id)
    (var-set fraction-counter fraction-id)
    
    (print {
      event: "fractional-listing-created",
      listing-id: listing-id,
      fraction-id: fraction-id,
      total-shares: total-shares,
      price-per-share: price-per-share,
      buyout-price: buyout-price
    })
    
    (ok {listing-id: listing-id, fraction-id: fraction-id})
  )
)

(define-public (purchase-shares (fraction-id uint) (shares-to-buy uint))
  (let (
    (fraction-data (unwrap! (map-get? fractional-ownership fraction-id) ERR_FRACTION_NOT_AVAILABLE))
    (listing-data (unwrap! (map-get? nft-listings (get listing-id fraction-data)) ERR_NFT_NOT_LISTED))
    (available-shares (- (get total-shares fraction-data) (get shares-sold fraction-data)))
    (purchase-cost (* shares-to-buy (get price-per-share fraction-data)))
    (current-holders (get share-holders fraction-data))
  )
    (asserts! (get active listing-data) ERR_NFT_NOT_LISTED)
    (asserts! (get trading-enabled fraction-data) ERR_FRACTION_NOT_AVAILABLE)
    (asserts! (<= shares-to-buy available-shares) ERR_FRACTION_NOT_AVAILABLE)
    (asserts! (> shares-to-buy u0) ERR_INVALID_PRICE)
    
    ;; Add new shareholder or update existing
    (let (
      (new-holders (unwrap! (as-max-len? (append current-holders {holder: tx-sender, shares: shares-to-buy}) u50) ERR_FRACTION_NOT_AVAILABLE))
    )
      ;; Update fractional ownership
      (map-set fractional-ownership fraction-id (merge fraction-data {
        shares-sold: (+ (get shares-sold fraction-data) shares-to-buy),
        share-holders: new-holders
      }))
      
      (print {
        event: "shares-purchased",
        fraction-id: fraction-id,
        buyer: tx-sender,
        shares-bought: shares-to-buy,
        cost: purchase-cost
      })
      
      (ok shares-to-buy)
    )
  )
)

;; NFT Lending Functions
(define-public (create-lending-pool
  (nft-contract principal)
  (token-id uint)
  (loan-amount uint)
  (interest-rate uint)
  (loan-duration uint)
  (collateral-value uint))
  (let (
    (loan-id (+ (var-get loan-counter) u1))
  )
    (asserts! (var-get platform-active) ERR_NOT_AUTHORIZED)
    (asserts! (> loan-amount u0) ERR_INVALID_PRICE)
    (asserts! (<= interest-rate u5000) ERR_INVALID_PRICE) ;; Max 50% interest
    (asserts! (> collateral-value loan-amount) ERR_INVALID_PRICE)
    
    ;; Create lending pool
    (map-set nft-lending-pools loan-id {
      lender: tx-sender,
      nft-contract: nft-contract,
      token-id: token-id,
      loan-amount: loan-amount,
      interest-rate: interest-rate,
      loan-duration: loan-duration,
      borrower: none,
      loan-start: u0,
      collateral-value: collateral-value,
      loan-active: false
    })
    
    ;; Update counter
    (var-set loan-counter loan-id)
    
    (print {
      event: "lending-pool-created",
      loan-id: loan-id,
      lender: tx-sender,
      loan-amount: loan-amount,
      interest-rate: interest-rate
    })
    
    (ok loan-id)
  )
)

(define-public (accept-loan (loan-id uint))
  (let (
    (loan-data (unwrap! (map-get? nft-lending-pools loan-id) ERR_NFT_NOT_LISTED))
  )
    (asserts! (not (get loan-active loan-data)) ERR_LOAN_ACTIVE)
    (asserts! (is-none (get borrower loan-data)) ERR_LOAN_ACTIVE)
    
    ;; Update loan with borrower info
    (map-set nft-lending-pools loan-id (merge loan-data {
      borrower: (some tx-sender),
      loan-start: block-height,
      loan-active: true
    }))
    
    (print {
      event: "loan-accepted",
      loan-id: loan-id,
      borrower: tx-sender,
      loan-amount: (get loan-amount loan-data)
    })
    
    (ok (get loan-amount loan-data))
  )
)

;; Helper Functions
(define-private (update-collection-listing-stats (collection principal) (price uint))
  (let (
    (current-stats (default-to {total-volume: u0, total-sales: u0, floor-price: u999999999, 
                               average-price: u0, last-sale-price: u0, total-listings: u0} 
                              (map-get? collection-analytics collection)))
  )
    (map-set collection-analytics collection (merge current-stats {
      total-listings: (+ (get total-listings current-stats) u1),
      floor-price: (if (< price (get floor-price current-stats)) price (get floor-price current-stats))
    }))
  )
)

(define-private (update-collection-sale-stats (collection principal) (price uint))
  (let (
    (current-stats (default-to {total-volume: u0, total-sales: u0, floor-price: u999999999, 
                               average-price: u0, last-sale-price: u0, total-listings: u0} 
                              (map-get? collection-analytics collection)))
    (new-total-sales (+ (get total-sales current-stats) u1))
    (new-total-volume (+ (get total-volume current-stats) price))
  )
    (map-set collection-analytics collection (merge current-stats {
      total-volume: new-total-volume,
      total-sales: new-total-sales,
      average-price: (/ new-total-volume new-total-sales),
      last-sale-price: price
    }))
  )
)

(define-private (update-user-trading-stats (buyer principal) (seller principal) (price uint))
  (let (
    (buyer-stats (default-to {total-purchases: u0, total-sales: u0, volume-traded: u0, 
                             successful-auctions: u0, reputation-score: u0} 
                            (map-get? user-trading-stats buyer)))
    (seller-stats (default-to {total-purchases: u0, total-sales: u0, volume-traded: u0, 
                              successful-auctions: u0, reputation-score: u0} 
                             (map-get? user-trading-stats seller)))
  )
    ;; Update buyer stats
    (map-set user-trading-stats buyer (merge buyer-stats {
      total-purchases: (+ (get total-purchases buyer-stats) u1),
      volume-traded: (+ (get volume-traded buyer-stats) price),
      reputation-score: (+ (get reputation-score buyer-stats) u1)
    }))
    
    ;; Update seller stats
    (map-set user-trading-stats seller (merge seller-stats {
      total-sales: (+ (get total-sales seller-stats) u1),
      volume-traded: (+ (get volume-traded seller-stats) price),
      reputation-score: (+ (get reputation-score seller-stats) u2)
    }))
  )
)

;; View Functions
(define-read-only (get-listing-details (listing-id uint))
  (map-get? nft-listings listing-id)
)

(define-read-only (get-auction-details (auction-id uint))
  (map-get? auction-details auction-id)
)

(define-read-only (get-fractional-details (fraction-id uint))
  (map-get? fractional-ownership fraction-id)
)

(define-read-only (get-loan-details (loan-id uint))
  (map-get? nft-lending-pools loan-id)
)

(define-read-only (get-collection-stats (collection principal))
  (map-get? collection-analytics collection)
)

(define-read-only (get-user-stats (user principal))
  (map-get? user-trading-stats user)
)

(define-read-only (get-marketplace-metrics)
  {
    marketplace-fee: (var-get marketplace-fee),
    platform-active: (var-get platform-active),
    listing-counter: (var-get listing-counter),
    auction-counter: (var-get auction-counter),
    fraction-counter: (var-get fraction-counter),
    loan-counter: (var-get loan-counter)
  }
)

(define-read-only (get-pending-royalties (recipient principal) (collection principal))
  (default-to u0 (map-get? pending-royalty-payments {recipient: recipient, collection: collection}))
)

(define-read-only (calculate-total-fees (price uint) (royalty-percentage uint))
  (let (
    (marketplace-fee-amount (/ (* price (var-get marketplace-fee)) u10000))
    (royalty-amount (/ (* price royalty-percentage) u10000))
  )
    {
      marketplace-fee: marketplace-fee-amount,
      royalty-fee: royalty-amount,
      seller-amount: (- (- price marketplace-fee-amount) royalty-amount)
    }
  )
)