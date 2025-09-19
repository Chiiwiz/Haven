;; Real Estate Investment Pool Contract
;; Enables pooled property investment with rental income distribution

;; Error constants
(define-constant ERR-ACCESS-DENIED (err u100))
(define-constant ERR-PROPERTY-MISSING (err u101))
(define-constant ERR-INVALID-DATA (err u102))
(define-constant ERR-ALREADY-PURCHASED (err u103))
(define-constant ERR-FUNDS-TOO-LOW (err u104))
(define-constant ERR-NO-DIVIDENDS (err u105))

;; Constants
(define-constant MAX-MANAGEMENT-FEE u200) ;; 20%
(define-constant SHARE-SCALE u1000) ;; 100% = 1000

;; Data structures
(define-map properties
  { property-id: uint }
  {
    property-address: (string-utf8 128),
    primary-investor: principal,
    purchase-cost: uint,
    management-fee: uint,
    acquired: bool,
    listed: bool
  }
)

(define-map investors
  { property-id: uint, investor: principal }
  { investment-share: uint, investor-type: (string-ascii 32) }
)

(define-map dividend-pool
  { property-id: uint, investor: principal }
  { accumulated: uint }
)

;; Store list of investors for each property
(define-map property-investors
  { property-id: uint }
  { investors: (list 50 principal) }
)

(define-data-var next-property-id uint u1)

;; List new property investment opportunity
(define-public (list-property 
                (property-address (string-utf8 128))
                (purchase-cost uint)
                (management-fee uint))
  (let ((property-id (var-get next-property-id)))
    ;; Validate inputs
    (asserts! (> purchase-cost u0) ERR-INVALID-DATA)
    (asserts! (<= management-fee MAX-MANAGEMENT-FEE) ERR-INVALID-DATA)
    (asserts! (> (len property-address) u0) ERR-INVALID-DATA)
    
    ;; Create property listing
    (map-set properties
      { property-id: property-id }
      {
        property-address: property-address,
        primary-investor: tx-sender,
        purchase-cost: purchase-cost,
        management-fee: management-fee,
        acquired: false,
        listed: true
      })
    
    ;; Add primary investor with full share initially
    (map-set investors
      { property-id: property-id, investor: tx-sender }
      { investment-share: SHARE-SCALE, investor-type: "primary" })
    
    ;; Initialize investor list
    (map-set property-investors
      { property-id: property-id }
      { investors: (list tx-sender) })
    
    ;; Increment counter
    (var-set next-property-id (+ property-id u1))
    (ok property-id)))

;; Add co-investor to property
(define-public (add-coinvestor
                (property-id uint)
                (coinvestor principal)
                (investment-share uint)
                (investor-type (string-ascii 32)))
  (let ((property (unwrap! (map-get? properties { property-id: property-id }) ERR-PROPERTY-MISSING))
        (primary-data (unwrap! (map-get? investors { property-id: property-id, investor: (get primary-investor property) }) ERR-PROPERTY-MISSING))
        (remaining-primary-share (- (get investment-share primary-data) investment-share))
        (current-investors (get investors (unwrap! (map-get? property-investors { property-id: property-id }) ERR-PROPERTY-MISSING))))
    
    ;; Validate
    (asserts! (> property-id u0) ERR-INVALID-DATA)
    (asserts! (not (is-eq coinvestor tx-sender)) ERR-INVALID-DATA) ;; Can't add self
    (asserts! (> (len investor-type) u0) ERR-INVALID-DATA)
    (asserts! (is-eq tx-sender (get primary-investor property)) ERR-ACCESS-DENIED)
    (asserts! (not (get acquired property)) ERR-ALREADY-PURCHASED)
    (asserts! (> investment-share u0) ERR-INVALID-DATA)
    (asserts! (<= investment-share (get investment-share primary-data)) ERR-INVALID-DATA)
    
    ;; Add co-investor
    (map-set investors
      { property-id: property-id, investor: coinvestor }
      { investment-share: investment-share, investor-type: investor-type })
    
    ;; Update primary investor's share
    (map-set investors
      { property-id: property-id, investor: (get primary-investor property) }
      { investment-share: remaining-primary-share, investor-type: "primary" })
    
    ;; Add to investor list if not already present
    (map-set property-investors
      { property-id: property-id }
      { investors: (unwrap! (as-max-len? (append current-investors coinvestor) u50) ERR-INVALID-DATA) })
    
    (ok true)))

;; Execute property acquisition
(define-public (acquire-property (property-id uint))
  (let ((property (unwrap! (map-get? properties { property-id: property-id }) ERR-PROPERTY-MISSING))
        (cost (get purchase-cost property)))
    
    ;; Validate
    (asserts! (> property-id u0) ERR-INVALID-DATA)
    (asserts! (get listed property) ERR-INVALID-DATA)
    (asserts! (not (get acquired property)) ERR-ALREADY-PURCHASED)
    (asserts! (>= (stx-get-balance tx-sender) cost) ERR-FUNDS-TOO-LOW)
    
    ;; Transfer acquisition cost to contract
    (try! (stx-transfer? cost tx-sender (as-contract tx-sender)))
    
    ;; Mark as acquired
    (map-set properties
      { property-id: property-id }
      (merge property { acquired: true }))
    
    ;; Pay to primary investor (simplified)
    (let ((primary-investor (get primary-investor property)))
      (as-contract (try! (stx-transfer? cost tx-sender primary-investor))))
    
    (ok true)))

;; Distribute rental income to investors
(define-public (distribute-rental-income
                (property-id uint)
                (tenant principal)
                (rental-amount uint))
  (let ((property (unwrap! (map-get? properties { property-id: property-id }) ERR-PROPERTY-MISSING))
        (management-cut (/ (* rental-amount (get management-fee property)) SHARE-SCALE))
        (investor-cut (- rental-amount management-cut)))
    
    ;; Validate
    (asserts! (> property-id u0) ERR-INVALID-DATA)
    (asserts! (not (is-eq tenant tx-sender)) ERR-INVALID-DATA) ;; Tenant can't be sender
    (asserts! (get listed property) ERR-INVALID-DATA)
    (asserts! (get acquired property) ERR-INVALID-DATA)
    (asserts! (> rental-amount u0) ERR-INVALID-DATA)
    (asserts! (>= (stx-get-balance tx-sender) rental-amount) ERR-FUNDS-TOO-LOW)
    
    ;; Transfer rental income to contract
    (try! (stx-transfer? rental-amount tx-sender (as-contract tx-sender)))
    
    ;; Pay management fee to primary investor
    (if (> management-cut u0)
        (as-contract (try! (stx-transfer? management-cut tx-sender (get primary-investor property))))
        true)
    
    ;; Distribute remaining to all investors
    (try! (distribute-investor-dividends property-id investor-cut))
    
    (ok true)))

;; Distribute dividends to property investors (FIXED VERSION)
(define-private (distribute-investor-dividends (property-id uint) (total-dividends uint))
  (let ((investor-list (get investors (unwrap! (map-get? property-investors { property-id: property-id }) ERR-PROPERTY-MISSING))))
    (begin
      (fold distribute-to-investor investor-list { property-id: property-id, total-dividends: total-dividends, success: true })
      (ok true))))

;; Helper function to distribute dividends to individual investor
(define-private (distribute-to-investor 
                (investor principal) 
                (data { property-id: uint, total-dividends: uint, success: bool }))
  (if (get success data)
      (let ((investor-data (map-get? investors { property-id: (get property-id data), investor: investor })))
        (if (is-some investor-data)
            (let ((investor-share (get investment-share (unwrap-panic investor-data)))
                  (investor-dividend (/ (* (get total-dividends data) investor-share) SHARE-SCALE))
                  (current-dividends (default-to { accumulated: u0 }
                                   (map-get? dividend-pool { property-id: (get property-id data), investor: investor }))))
              
              ;; Add to dividend pool
              (map-set dividend-pool
                { property-id: (get property-id data), investor: investor }
                { accumulated: (+ (get accumulated current-dividends) investor-dividend) })
              
              data)
            data))
      data))

;; Claim accumulated dividends
(define-public (claim-dividends (property-id uint))
  (let ((dividends (unwrap! (map-get? dividend-pool { property-id: property-id, investor: tx-sender }) ERR-NO-DIVIDENDS))
        (amount (get accumulated dividends)))
    
    ;; Validate
    (asserts! (> property-id u0) ERR-INVALID-DATA)
    (asserts! (> amount u0) ERR-NO-DIVIDENDS)
    
    ;; Reset dividend pool
    (map-set dividend-pool
      { property-id: property-id, investor: tx-sender }
      { accumulated: u0 })
    
    ;; Transfer dividends
    (as-contract (try! (stx-transfer? amount tx-sender tx-sender)))
    
    (ok amount)))

;; Toggle property listing status (primary investor only)
(define-public (toggle-listing-status (property-id uint))
  (let ((property (unwrap! (map-get? properties { property-id: property-id }) ERR-PROPERTY-MISSING)))
    
    ;; Validate
    (asserts! (> property-id u0) ERR-INVALID-DATA)
    (asserts! (is-eq tx-sender (get primary-investor property)) ERR-ACCESS-DENIED)
    
    ;; Toggle listing status
    (map-set properties
      { property-id: property-id }
      (merge property { listed: (not (get listed property)) }))
    
    (ok true)))

;; Read-only functions
(define-read-only (get-property (property-id uint))
  (map-get? properties { property-id: property-id }))

(define-read-only (get-investor (property-id uint) (investor principal))
  (map-get? investors { property-id: property-id, investor: investor }))

(define-read-only (get-dividends (property-id uint) (investor principal))
  (default-to { accumulated: u0 }
              (map-get? dividend-pool { property-id: property-id, investor: investor })))

(define-read-only (get-property-investors (property-id uint))
  (map-get? property-investors { property-id: property-id }))

(define-read-only (get-next-property-id)
  (var-get next-property-id))

(define-read-only (property-exists (property-id uint))
  (is-some (map-get? properties { property-id: property-id })))

(define-read-only (get-total-properties)
  (- (var-get next-property-id) u1))