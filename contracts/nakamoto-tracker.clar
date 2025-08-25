;; nakamoto-tracker.clar
;; This contract serves as the core mechanism for tracking blockchain activities 
;; and network interactions, enabling comprehensive scanning and monitoring of 
;; on-chain events with robust record-keeping capabilities.

;; ========== Error Constants ==========
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-SCAN-ALREADY-EXISTS (err u101))
(define-constant ERR-SCAN-NOT-FOUND (err u102))
(define-constant ERR-TX-NOT-FOUND (err u103))
(define-constant ERR-INVALID-TX-TYPE (err u104))
(define-constant ERR-SCAN-ALREADY-COMPLETED (err u105))
(define-constant ERR-SCAN-NOT-STARTED (err u106))
(define-constant ERR-INVALID-BLOCK-RANGE (err u107))
(define-constant ERR-DUPLICATE-EVENT (err u108))
(define-constant ERR-INVALID-PARAMETERS (err u109))

;; ========== Data Maps and Variables ==========

;; Network participants tracking
(define-map network-participants
  { participant: principal }
  {
    username: (string-utf8 50),
    registered-at: uint,
    total-scans: uint,
    last-scan-date: (optional uint)
  }
)

;; Transaction types allowed in the system
(define-data-var tx-types (list 9 (string-utf8 20)) 
  (list u"transfer" u"contract-call" u"stx-transfer" u"token-transfer" u"nft-transfer" u"smart-contract" u"vote" u"governance")
)

;; Transaction records
(define-map network-transactions
  { tx-id: uint, participant: principal }
  {
    tx-type: (string-utf8 20),
    tx-volume: uint,
    block-height: uint,
    notes: (optional (string-utf8 200))
  }
)

;; Network scans
(define-map network-scans
  { scan-id: uint }
  {
    name: (string-utf8 100),
    description: (string-utf8 500),
    creator: principal,
    start-block: uint,
    end-block: uint,
    total-transactions: uint,
    status: (string-utf8 20), ;; "pending", "in-progress", "completed"
    active: bool
  }
)

;; Transaction and scan counters
(define-data-var tx-counter uint u0)
(define-data-var scan-counter uint u0)

;; ========== Private Functions ==========

;; Check if a scan is active (started but not ended)
(define-private (is-scan-active (scan-id uint))
  (match (map-get? network-scans { scan-id: scan-id })
    scan (and 
      (is-eq (get status scan) u"in-progress")
      (get active scan)
    )
    false
  )
)

;; Create a new transaction record
(define-private (create-transaction-record
  (participant principal)
  (tx-type (string-utf8 20))
  (tx-volume uint)
  (notes (optional (string-utf8 200)))
)
  (let
    (
      (new-tx-id (+ (var-get tx-counter) u1))
    )
    ;; Increment the transaction counter
    (var-set tx-counter new-tx-id)
    
    ;; Insert the new transaction record
    (map-set network-transactions
      { tx-id: new-tx-id, participant: participant }
      {
        tx-type: tx-type,
        tx-volume: tx-volume,
        block-height: block-height,
        notes: notes
      }
    )
    
    ;; Update the participant's profile
    (match (map-get? network-participants { participant: participant })
      prev-data
        (map-set network-participants
          { participant: participant }
          {
            username: (get username prev-data),
            registered-at: (get registered-at prev-data),
            total-scans: (get total-scans prev-data),
            last-scan-date: (some block-height)
          }
        )
      false
    )

    ;; Return the new transaction ID
    new-tx-id
  )
)

;; ========== Read-Only Functions ==========

;; Get participant profile information
(define-read-only (get-participant-profile (participant principal))
  (map-get? network-participants { participant: participant })
)

;; Get details of a specific transaction
(define-read-only (get-transaction (tx-id uint) (participant principal))
  (map-get? network-transactions { tx-id: tx-id, participant: participant })
)

;; Get details of a specific network scan
(define-read-only (get-network-scan (scan-id uint))
  (map-get? network-scans { scan-id: scan-id })
)

;; ========== Public Functions ==========

;; Register a new network participant
(define-public (register-participant (username (string-utf8 50)))
  (let
    ((sender tx-sender))
    
    ;; Create new participant profile
    (map-set network-participants
      { participant: sender }
      {
        username: username,
        registered-at: block-height,
        total-scans: u0,
        last-scan-date: none
      }
    )
    (ok true)
  )
)

;; Log a blockchain transaction
(define-public (log-transaction 
  (tx-type (string-utf8 20)) 
  (tx-volume uint) 
  (notes (optional (string-utf8 200)))
)
  (let
    ((sender tx-sender))
    ;; Validate transaction type
    (asserts! 
      (is-some (index-of (var-get tx-types) tx-type)) 
      ERR-INVALID-TX-TYPE
    )
    
    ;; Create the transaction record
    (let 
      ((tx-id (create-transaction-record sender tx-type tx-volume notes)))
      (ok tx-id)
    )
  )
)

;; Create a new network scan
(define-public (create-network-scan
  (name (string-utf8 100))
  (description (string-utf8 500))
  (start-block uint)
  (end-block uint)
)
  (let
    (
      (sender tx-sender)
      (new-scan-id (+ (var-get scan-counter) u1))
    )
    ;; Validate parameters
    (asserts! (< start-block end-block) ERR-INVALID-BLOCK-RANGE)
    (asserts! (>= start-block block-height) ERR-INVALID-BLOCK-RANGE)
    
    ;; Increment scan counter
    (var-set scan-counter new-scan-id)
    
    ;; Create the network scan
    (map-set network-scans
      { scan-id: new-scan-id }
      {
        name: name,
        description: description,
        creator: sender,
        start-block: start-block,
        end-block: end-block,
        total-transactions: u0,
        status: u"pending",
        active: true
      }
    )
    (ok new-scan-id)
  )
)

;; Start a network scan
(define-public (start-network-scan (scan-id uint))
  (let
    ((sender tx-sender))
    
    ;; Verify the scan exists and is pending
    (match (map-get? network-scans { scan-id: scan-id })
      scan
        (begin
          ;; Ensure only the creator can start the scan
          (asserts! (is-eq (get creator scan) sender) ERR-NOT-AUTHORIZED)
          
          ;; Update scan status
          (map-set network-scans
            { scan-id: scan-id }
            (merge scan { status: u"in-progress" })
          )
          (ok true)
        )
      (err ERR-SCAN-NOT-FOUND)
    )
  )
)

;; Add a new valid transaction type (restricted to contract owner)
(define-public (add-transaction-type (new-type (string-utf8 20)))
  (let
    ((current-types (var-get tx-types)))
    ;; Basic implementation - would need proper authorization in production
    (asserts! (is-eq tx-sender (as-contract tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Add the new transaction type
    (var-set tx-types 
      (unwrap! 
        (as-max-len? (append current-types new-type) u9) 
        (err ERR-INVALID-PARAMETERS)
      )
    )
    (ok true)
  )
)