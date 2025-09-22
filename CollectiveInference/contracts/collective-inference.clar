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

;; Request inference computation with enhanced parameters
(define-public (request-inference 
  (model-type (string-ascii 50))
  (compute-hours uint)
  (preferred-provider (optional principal))
  (max-rate uint))
  (let
    (
      (request-id (+ (var-get request-count) u1))
      (model-config (unwrap! (map-get? model-types { model-type: model-type }) ERR-INVALID-STATUS))
      (base-payment (* compute-hours (get base-rate model-config)))
      (complexity-fee (* base-payment (get complexity-multiplier model-config)))
      (total-payment (+ base-payment complexity-fee))
      (platform-fee (/ (* total-payment (var-get platform-fee-rate)) u100))
      (provider-payment (- total-payment platform-fee))
      (selected-provider (default-to CONTRACT-OWNER preferred-provider))
    )
    (asserts! (get enabled model-config) ERR-INVALID-STATUS)
    (asserts! (<= total-payment max-rate) ERR-INSUFFICIENT-FUNDS)
    (try! (stx-transfer? total-payment tx-sender (as-contract tx-sender)))
    
    (map-set inference-requests
      { request-id: request-id }
      {
        client: tx-sender,
        provider: selected-provider,
        model-type: model-type,
        compute-required: compute-hours,
        payment: provider-payment,
        status: "pending",
        created-at: block-height,
        completed-at: u0,
        result-hash: none,
        client-rating: none,
        provider-rating: none
      }
    )
    
    (var-set request-count request-id)
    (ok request-id)
  )
)

;; Accept inference request with validation
(define-public (accept-request (request-id uint))
  (let
    (
      (request (unwrap! (map-get? inference-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (provider (unwrap! (map-get? compute-providers { provider: tx-sender }) ERR-PROVIDER-NOT-FOUND))
      (model-config (unwrap! (map-get? model-types { model-type: (get model-type request) }) ERR-INVALID-STATUS))
      (last-activity (get last-activity provider))
    )
    (asserts! (get active provider) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get gpu-power provider) (get min-gpu-power model-config)) ERR-INSUFFICIENT-FUNDS)
    (asserts! (is-eq (get status request) "pending") ERR-INVALID-STATUS)
    (asserts! (> (get stake-amount provider) u0) ERR-STAKING-REQUIRED)
    (asserts! (>= (+ last-activity (var-get cooldown-period)) block-height) ERR-COOLDOWN-ACTIVE)
    
    (map-set inference-requests
      { request-id: request-id }
      (merge request { status: "accepted", provider: tx-sender })
    )
    
    ;; Update provider activity
    (map-set compute-providers
      { provider: tx-sender }
      (merge provider { last-activity: block-height })
    )
    
    (ok true)
  )
)

;; Complete inference request with result verification
(define-public (complete-request (request-id uint) (result-hash (buff 32)))
  (let
    (
      (request (unwrap! (map-get? inference-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (provider (unwrap! (map-get? compute-providers { provider: tx-sender }) ERR-PROVIDER-NOT-FOUND))
      (payment (get payment request))
    )
    (asserts! (is-eq tx-sender (get provider request)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "accepted") ERR-INVALID-STATUS)
    
    ;; Pay provider (85% immediately, 15% held for rating period)
    (let ((immediate-payment (/ (* payment u85) u100)))
      (try! (as-contract (stx-transfer? immediate-payment tx-sender (get provider request))))
    )
    
    ;; Update request status
    (map-set inference-requests
      { request-id: request-id }
      (merge request { 
        status: "completed", 
        completed-at: block-height,
        result-hash: (some result-hash)
      })
    )
    
    ;; Update provider stats
    (map-set compute-providers
      { provider: tx-sender }
      (merge provider {
        total-earnings: (+ (get total-earnings provider) payment),
        completed-jobs: (+ (get completed-jobs provider) u1),
        reputation-score: (+ (get reputation-score provider) u5),
        last-activity: block-height
      })
    )
    
    (ok true)
  )
)

;; Rate a completed request
(define-public (rate-request 
  (request-id uint) 
  (rating uint) 
  (comment (optional (string-ascii 100)))
  (is-provider-rating bool))
  (let
    (
      (request (unwrap! (map-get? inference-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (existing-rating (map-get? provider-ratings { request-id: request-id, rater: tx-sender }))
    )
    (asserts! (is-eq (get status request) "completed") ERR-INVALID-STATUS)
    (asserts! (<= rating u5) ERR-INVALID-RATING)
    (asserts! (is-none existing-rating) ERR-ALREADY-RATED)
    
    (if is-provider-rating
      (asserts! (is-eq tx-sender (get provider request)) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq tx-sender (get client request)) ERR-NOT-AUTHORIZED)
    )
    
    ;; Store rating
    (map-set provider-ratings
      { request-id: request-id, rater: tx-sender }
      { rating: rating, comment: comment }
    )
    
    ;; Update request with rating
    (if is-provider-rating
      (map-set inference-requests
        { request-id: request-id }
        (merge request { provider-rating: (some rating) })
      )
      (map-set inference-requests
        { request-id: request-id }
        (merge request { client-rating: (some rating) })
      )
    )
    
    ;; Release remaining payment if both parties rated or after timeout
    (if (and (is-some (get client-rating request)) (is-some (get provider-rating request)))
      (let ((remaining-payment (/ (* (get payment request) u15) u100)))
        (try! (as-contract (stx-transfer? remaining-payment tx-sender (get provider request))))
        (ok true)
      )
      (ok true)
    )
  )
)

;; Create dispute for a request
(define-public (create-dispute 
  (request-id uint) 
  (reason (string-ascii 200)))
  (let
    (
      (request (unwrap! (map-get? inference-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (dispute-id (+ (var-get dispute-count) u1))
      (disputed-against (if (is-eq tx-sender (get client request))
                          (get provider request)
                          (get client request)))
    )
    (asserts! (or (is-eq tx-sender (get client request))
                  (is-eq tx-sender (get provider request))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "completed") ERR-INVALID-STATUS)
    
    (map-set disputes
      { dispute-id: dispute-id }
      {
        request-id: request-id,
        disputer: tx-sender,
        disputed-against: disputed-against,
        reason: reason,
        status: "open",
        created-at: block-height,
        resolved-at: u0,
        resolution: none
      }
    )
    
    (var-set dispute-count dispute-id)
    (ok dispute-id)
  )
)

;; Resolve dispute (contract owner only)
(define-public (resolve-dispute 
  (dispute-id uint) 
  (resolution (string-ascii 200))
  (favor-disputer bool))
  (let
    (
      (dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-DISPUTE-NOT-FOUND))
      (request (unwrap! (map-get? inference-requests { request-id: (get request-id dispute) }) ERR-REQUEST-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status dispute) "open") ERR-INVALID-STATUS)
    
    ;; Update dispute status
    (map-set disputes
      { dispute-id: dispute-id }
      (merge dispute {
        status: "resolved",
        resolved-at: block-height,
        resolution: (some resolution)
      })
    )
    
    ;; Handle resolution consequences
    (if favor-disputer
      ;; Favor disputer - penalize disputed party
      (let ((disputed-provider (map-get? compute-providers { provider: (get disputed-against dispute) })))
        (if (is-some disputed-provider)
          (map-set compute-providers
            { provider: (get disputed-against dispute) }
            (merge (unwrap-panic disputed-provider) {
              reputation-score: (if (> (get reputation-score (unwrap-panic disputed-provider)) u10)
                                  (- (get reputation-score (unwrap-panic disputed-provider)) u10)
                                  u0)
            })
          )
          true
        )
      )
      ;; Favor disputed party - penalize disputer
      (let ((disputer-provider (map-get? compute-providers { provider: (get disputer dispute) })))
        (if (is-some disputer-provider)
          (map-set compute-providers
            { provider: (get disputer dispute) }
            (merge (unwrap-panic disputer-provider) {
              reputation-score: (if (> (get reputation-score (unwrap-panic disputer-provider)) u5)
                                  (- (get reputation-score (unwrap-panic disputer-provider)) u5)
                                  u0)
            })
          )
          true
        )
      )
    )
    
    (ok true)
  )
)

;; Toggle provider availability
(define-public (toggle-availability)
  (let
    (
      (provider (unwrap! (map-get? compute-providers { provider: tx-sender }) ERR-PROVIDER-NOT-FOUND))
    )
    (map-set compute-providers
      { provider: tx-sender }
      (merge provider { 
        active: (not (get active provider)),
        last-activity: block-height
      })
    )
    (ok (not (get active provider)))
  )
)

;; Withdraw stake (with cooldown)
(define-public (withdraw-stake (amount uint))
  (let
    (
      (provider (unwrap! (map-get? compute-providers { provider: tx-sender }) ERR-PROVIDER-NOT-FOUND))
      (cooldown-end (+ (get last-activity provider) (var-get cooldown-period)))
    )
    (asserts! (not (get active provider)) ERR-INVALID-STATUS)
    (asserts! (>= block-height cooldown-end) ERR-COOLDOWN-ACTIVE)
    (asserts! (>= (get stake-amount provider) amount) ERR-INSUFFICIENT-FUNDS)
    
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    (map-set compute-providers
      { provider: tx-sender }
      (merge provider {
        stake-amount: (- (get stake-amount provider) amount)
      })
    )
    
    (ok true)
  )
)

;; Admin function to update platform parameters
(define-public (update-platform-params 
  (fee-rate uint) 
  (min-stake uint) 
  (cooldown uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= fee-rate u10) ERR-INVALID-STATUS) ;; Max 10% fee
    (var-set platform-fee-rate fee-rate)
    (var-set min-stake-amount min-stake)
    (var-set cooldown-period cooldown)
    (ok true)
  )
)

;; Emergency pause (admin only)
(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    ;; Implementation would disable all functions except admin ones
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-provider (provider principal))
  (map-get? compute-providers { provider: provider })
)

(define-read-only (get-request (request-id uint))
  (map-get? inference-requests { request-id: request-id })
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

(define-read-only (get-model-config (model-type (string-ascii 50)))
  (map-get? model-types { model-type: model-type })
)

(define-read-only (get-rating (request-id uint) (rater principal))
  (map-get? provider-ratings { request-id: request-id, rater: rater })
)

(define-read-only (get-total-providers)
  (var-get total-providers)
)

(define-read-only (get-request-count)
  (var-get request-count)
)

(define-read-only (get-dispute-count)
  (var-get dispute-count)
)

(define-read-only (get-platform-stats)
  {
    total-providers: (var-get total-providers),
    total-requests: (var-get request-count),
    total-disputes: (var-get dispute-count),
    platform-fee-rate: (var-get platform-fee-rate),
    min-stake-amount: (var-get min-stake-amount)
  }
)

(define-read-only (calculate-payment (model-type (string-ascii 50)) (compute-hours uint))
  (let
    (
      (model-config (unwrap! (map-get? model-types { model-type: model-type }) ERR-INVALID-STATUS))
      (base-payment (* compute-hours (get base-rate model-config)))
      (complexity-fee (* base-payment (get complexity-multiplier model-config)))
      (total-payment (+ base-payment complexity-fee))
      (platform-fee (/ (* total-payment (var-get platform-fee-rate)) u100))
    )
    (ok {
      base-payment: base-payment,
      complexity-fee: complexity-fee,
      platform-fee: platform-fee,
      total-payment: total-payment,
      provider-payment: (- total-payment platform-fee)
    })
  )
)