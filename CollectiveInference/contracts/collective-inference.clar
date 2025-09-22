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

;; Initialize with supported model types
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set model-types { model-type: "llm-small" } 
      { min-gpu-power: u4, base-rate: u100, complexity-multiplier: u1, enabled: true })
    (map-set model-types { model-type: "llm-large" } 
      { min-gpu-power: u8, base-rate: u300, complexity-multiplier: u2, enabled: true })
    (map-set model-types { model-type: "image-generation" } 
      { min-gpu-power: u6, base-rate: u200, complexity-multiplier: u3, enabled: true })
    (map-set model-types { model-type: "computer-vision" } 
      { min-gpu-power: u4, base-rate: u150, complexity-multiplier: u2, enabled: true })
    (map-set model-types { model-type: "speech-synthesis" } 
      { min-gpu-power: u2, base-rate: u80, complexity-multiplier: u1, enabled: true })
    (map-set model-types { model-type: "video-processing" } 
      { min-gpu-power: u12, base-rate: u500, complexity-multiplier: u4, enabled: true })
    (ok true)
  )
)

;; Register as compute provider with staking
(define-public (register-provider 
  (gpu-power uint) 
  (hourly-rate uint) 
  (specializations (list 5 (string-ascii 50))))
  (let
    (
      (existing-provider (map-get? compute-providers { provider: tx-sender }))
      (stake-amount (var-get min-stake-amount))
    )
    ;; Require minimum stake
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (if (is-some existing-provider)
      (map-set compute-providers
        { provider: tx-sender }
        (merge (unwrap-panic existing-provider) { 
          gpu-power: gpu-power, 
          hourly-rate: hourly-rate,
          active: true,
          specializations: specializations,
          stake-amount: (+ (get stake-amount (unwrap-panic existing-provider)) stake-amount),
          last-activity: block-height
        })
      )
      (begin
        (map-set compute-providers
          { provider: tx-sender }
          {
            gpu-power: gpu-power,
            hourly-rate: hourly-rate,
            active: true,
            total-earnings: u0,
            completed-jobs: u0,
            reputation-score: u100,
            stake-amount: stake-amount,
            last-activity: block-height,
            specializations: specializations,
            uptime-score: u100
          }
        )
        (var-set total-providers (+ (var-get total-providers) u1))
      )
    )
    (ok true)
  )
)

;; Update provider configuration
(define-public (update-provider-config
  (gpu-power uint)
  (hourly-rate uint)
  (specializations (list 5 (string-ascii 50))))
  (let
    (
      (provider (unwrap! (map-get? compute-providers { provider: tx-sender }) ERR-PROVIDER-NOT-FOUND))
    )
    (map-set compute-providers
      { provider: tx-sender }
      (merge provider {
        gpu-power: gpu-power,
        hourly-rate: hourly-rate,
        specializations: specializations,
        last-activity: block-height
      })
    )
    (ok true)
  )
)

;; Increase provider stake
(define-public (increase-stake (amount uint))
  (let
    (
      (provider (unwrap! (map-get? compute-providers { provider: tx-sender }) ERR-PROVIDER-NOT-FOUND))
    )
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set compute-providers
      { provider: tx-sender }
      (merge provider {
        stake-amount: (+ (get stake-amount provider) amount)
      })
    )
    (ok true)
  )
)
