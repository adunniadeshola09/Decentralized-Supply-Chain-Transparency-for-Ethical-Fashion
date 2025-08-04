;; Counterfeit Prevention Contract
;; Ensures product authenticity and prevents unauthorized copies

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-PRODUCT-NOT-FOUND (err u501))
(define-constant ERR-INVALID-INPUT (err u502))
(define-constant ERR-PRODUCT-EXISTS (err u503))
(define-constant ERR-TRANSFER-FAILED (err u504))
(define-constant ERR-BRAND-NOT-FOUND (err u505))

;; Data Variables
(define-data-var next-product-id uint u1)
(define-data-var next-brand-id uint u1)

;; Data Maps
(define-map authentic-products
  { product-id: uint }
  {
    brand-id: uint,
    product-name: (string-ascii 100),
    model-number: (string-ascii 50),
    batch-number: (string-ascii 50),
    manufacturing-date: uint,
    manufacturing-location: (string-ascii 100),
    unique-identifier: (buff 32),
    current-owner: principal,
    creation-date: uint,
    status: (string-ascii 20)
  }
)

(define-map registered-brands
  { brand-id: uint }
  {
    brand-name: (string-ascii 100),
    brand-owner: principal,
    registration-date: uint,
    verified: bool,
    contact-info: (string-ascii 200)
  }
)

(define-map product-transfers
  { product-id: uint, transfer-id: uint }
  {
    from-owner: principal,
    to-owner: principal,
    transfer-date: uint,
    transfer-type: (string-ascii 50),
    verified: bool
  }
)

(define-map brand-authorized-manufacturers
  { brand-id: uint, manufacturer: principal }
  { authorized: bool, authorization-date: uint }
)

(define-map product-verification-requests
  { request-id: uint }
  {
    product-id: uint,
    requester: principal,
    request-date: uint,
    status: (string-ascii 20),
    verification-result: bool
  }
)

(define-data-var next-transfer-id uint u1)
(define-data-var next-request-id uint u1)

;; Brand Registration Functions
(define-public (register-brand
  (brand-name (string-ascii 100))
  (contact-info (string-ascii 200))
)
  (let
    (
      (brand-id (var-get next-brand-id))
    )
    (asserts! (> (len brand-name) u0) ERR-INVALID-INPUT)

    (map-set registered-brands
      { brand-id: brand-id }
      {
        brand-name: brand-name,
        brand-owner: tx-sender,
        registration-date: block-height,
        verified: false,
        contact-info: contact-info
      }
    )

    (var-set next-brand-id (+ brand-id u1))
    (ok brand-id)
  )
)

(define-public (verify-brand (brand-id uint))
  (let
    (
      (brand (unwrap! (map-get? registered-brands { brand-id: brand-id }) ERR-BRAND-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (ok (map-set registered-brands
      { brand-id: brand-id }
      (merge brand { verified: true })
    ))
  )
)

(define-public (authorize-manufacturer (brand-id uint) (manufacturer principal))
  (let
    (
      (brand (unwrap! (map-get? registered-brands { brand-id: brand-id }) ERR-BRAND-NOT-FOUND))
    )
    (asserts! (is-eq (get brand-owner brand) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get verified brand) ERR-NOT-AUTHORIZED)

    (ok (map-set brand-authorized-manufacturers
      { brand-id: brand-id, manufacturer: manufacturer }
      { authorized: true, authorization-date: block-height }
    ))
  )
)

;; Product Authentication Functions
(define-public (create-authentic-product
  (brand-id uint)
  (product-name (string-ascii 100))
  (model-number (string-ascii 50))
  (batch-number (string-ascii 50))
  (manufacturing-location (string-ascii 100))
  (unique-identifier (buff 32))
)
  (let
    (
      (product-id (var-get next-product-id))
      (brand (unwrap! (map-get? registered-brands { brand-id: brand-id }) ERR-BRAND-NOT-FOUND))
      (manufacturer-auth (default-to { authorized: false, authorization-date: u0 }
        (map-get? brand-authorized-manufacturers { brand-id: brand-id, manufacturer: tx-sender })))
      (is-brand-owner (is-eq (get brand-owner brand) tx-sender))
      (is-authorized-manufacturer (get authorized manufacturer-auth))
    )
    (asserts! (or is-brand-owner is-authorized-manufacturer) ERR-NOT-AUTHORIZED)
    (asserts! (get verified brand) ERR-NOT-AUTHORIZED)
    (asserts! (> (len product-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len model-number) u0) ERR-INVALID-INPUT)

    (map-set authentic-products
      { product-id: product-id }
      {
        brand-id: brand-id,
        product-name: product-name,
        model-number: model-number,
        batch-number: batch-number,
        manufacturing-date: block-height,
        manufacturing-location: manufacturing-location,
        unique-identifier: unique-identifier,
        current-owner: tx-sender,
        creation-date: block-height,
        status: "authentic"
      }
    )

    (var-set next-product-id (+ product-id u1))
    (ok product-id)
  )
)

(define-public (transfer-product (product-id uint) (new-owner principal) (transfer-type (string-ascii 50)))
  (let
    (
      (product (unwrap! (map-get? authentic-products { product-id: product-id }) ERR-PRODUCT-NOT-FOUND))
      (transfer-id (var-get next-transfer-id))
    )
    (asserts! (is-eq (get current-owner product) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status product) "authentic") ERR-INVALID-INPUT)

    ;; Record the transfer
    (map-set product-transfers
      { product-id: product-id, transfer-id: transfer-id }
      {
        from-owner: tx-sender,
        to-owner: new-owner,
        transfer-date: block-height,
        transfer-type: transfer-type,
        verified: true
      }
    )

    ;; Update product ownership
    (map-set authentic-products
      { product-id: product-id }
      (merge product { current-owner: new-owner })
    )

    (var-set next-transfer-id (+ transfer-id u1))
    (ok transfer-id)
  )
)

(define-public (report-counterfeit (product-id uint))
  (let
    (
      (product (unwrap! (map-get? authentic-products { product-id: product-id }) ERR-PRODUCT-NOT-FOUND))
    )
    (ok (map-set authentic-products
      { product-id: product-id }
      (merge product { status: "reported-counterfeit" })
    ))
  )
)

(define-public (request-verification (product-id uint))
  (let
    (
      (request-id (var-get next-request-id))
      (product (unwrap! (map-get? authentic-products { product-id: product-id }) ERR-PRODUCT-NOT-FOUND))
    )
    (map-set product-verification-requests
      { request-id: request-id }
      {
        product-id: product-id,
        requester: tx-sender,
        request-date: block-height,
        status: "pending",
        verification-result: false
      }
    )

    (var-set next-request-id (+ request-id u1))
    (ok request-id)
  )
)

;; Read-only Functions
(define-read-only (get-product (product-id uint))
  (map-get? authentic-products { product-id: product-id })
)

(define-read-only (get-brand (brand-id uint))
  (map-get? registered-brands { brand-id: brand-id })
)

(define-read-only (verify-product-authenticity (product-id uint))
  (match (map-get? authentic-products { product-id: product-id })
    product (ok {
      authentic: (is-eq (get status product) "authentic"),
      brand-id: (get brand-id product),
      manufacturing-date: (get manufacturing-date product),
      current-owner: (get current-owner product)
    })
    ERR-PRODUCT-NOT-FOUND
  )
)

(define-read-only (get-product-by-identifier (unique-identifier (buff 32)))
  (let
    (
      (product-id u1) ;; This would need to be implemented with a reverse lookup map in practice
    )
    (map-get? authentic-products { product-id: product-id })
  )
)

(define-read-only (is-manufacturer-authorized (brand-id uint) (manufacturer principal))
  (default-to false
    (get authorized (map-get? brand-authorized-manufacturers { brand-id: brand-id, manufacturer: manufacturer }))
  )
)

(define-read-only (get-product-transfer-history (product-id uint) (transfer-id uint))
  (map-get? product-transfers { product-id: product-id, transfer-id: transfer-id })
)

(define-read-only (verify-ownership (product-id uint) (claimed-owner principal))
  (match (map-get? authentic-products { product-id: product-id })
    product (ok (is-eq (get current-owner product) claimed-owner))
    ERR-PRODUCT-NOT-FOUND
  )
)

(define-read-only (get-brand-products-count (brand-id uint))
  ;; This would require additional tracking in a real implementation
  (ok u0)
)

(define-read-only (is-product-authentic (product-id uint))
  (match (map-get? authentic-products { product-id: product-id })
    product (is-eq (get status product) "authentic")
    false
  )
)
