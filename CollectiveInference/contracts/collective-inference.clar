;; CollectiveInference - Distributed AI inference network
;; Community members contribute GPU resources, earn tokens for inference requests

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-FUNDS (err u101))
(define-constant ERR-PROVIDER-NOT-FOUND (err u102))
(define-constant ERR-REQUEST-NOT-FOUND (err u103))
(define-constant ERR-INVALID-STATUS (err u104))
(define-constant ERR-INVALID-RATING (err u105))
(define-constant ERR-ALREADY-RATED (err u106))
(define-constant ERR-DISPUTE-NOT-FOUND (err u107))
(define-constant ERR-STAKING-REQUIRED (err u108))
(define-constant ERR-COOLDOWN-ACTIVE (err u109))

(define-data-var request-count uint u0)
(define-data-var total-providers uint u0)
(define-data-var dispute-count uint u0)
(define-data-var platform-fee-rate uint u5) ;; 5% platform fee
(define-data-var min-stake-amount uint u1000) ;; Minimum stake for providers
(define-data-var cooldown-period uint u144) ;; Blocks (~24 hours)

(define-map compute-providers
  { provider: principal }
  {
    gpu-power: uint,
    hourly-rate: uint,
    active: bool,
    total-earnings: uint,
    completed-jobs: uint,
    reputation-score: uint,
    stake-amount: uint,
    last-activity: uint,
    specializations: (list 5 (string-ascii 50)),
    uptime-score: uint
  }
)

(define-map inference-requests
  { request-id: uint }
  {
    client: principal,
    provider: principal,
    model-type: (string-ascii 50),
    compute-required: uint,
    payment: uint,
    status: (string-ascii 20),
    created-at: uint,
    completed-at: uint,
    result-hash: (optional (buff 32)),
    client-rating: (optional uint),
    provider-rating: (optional uint)
  }
)

(define-map model-types
  { model-type: (string-ascii 50) }
  { 
    min-gpu-power: uint, 
    base-rate: uint,
    complexity-multiplier: uint,
    enabled: bool
  }
)

(define-map disputes
  { dispute-id: uint }
  {
    request-id: uint,
    disputer: principal,
    disputed-against: principal,
    reason: (string-ascii 200),
    status: (string-ascii 20),
    created-at: uint,
    resolved-at: uint,
    resolution: (optional (string-ascii 200))
  }
)

(define-map provider-ratings
  { request-id: uint, rater: principal }
  { rating: uint, comment: (optional (string-ascii 100)) }
)