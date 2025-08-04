;; Certification Tracking Contract
;; Manages and verifies various industry certifications

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-CERTIFICATION-NOT-FOUND (err u401))
(define-constant ERR-INVALID-INPUT (err u402))
(define-constant ERR-CERTIFICATION-EXPIRED (err u403))
(define-constant ERR-AUTHORITY-NOT-FOUND (err u404))

;; Data Variables
(define-data-var next-certification-id uint u1)
(define-data-var next-authority-id uint u1)

;; Data Maps
(define-map certifications
  { certification-id: uint }
  {
    certification-type: (string-ascii 50),
    holder: principal,
    issuing-authority-id: uint,
    issue-date: uint,
    expiry-date: uint,
    status: (string-ascii 20),
    scope: (string-ascii 200),
    certificate-hash: (buff 32),
    renewal-count: uint
  }
)

(define-map certification-authorities
  { authority-id: uint }
  {
    authority-name: (string-ascii 100),
    authority-type: (string-ascii 50),
    accreditation-number: (string-ascii 50),
    contact-info: (string-ascii 200),
    authorized: bool,
    registration-date: uint
  }
)

(define-map certification-standards
  { standard-name: (string-ascii 50) }
  {
    description: (string-ascii 300),
    validity-period: uint,
    renewal-required: bool,
    minimum-score: uint,
    active: bool
  }
)

(define-map holder-certifications
  { holder: principal, certification-type: (string-ascii 50) }
  { certification-id: uint, active: bool }
)

;; Authority Management Functions
(define-public (register-certification-authority
  (authority-name (string-ascii 100))
  (authority-type (string-ascii 50))
  (accreditation-number (string-ascii 50))
  (contact-info (string-ascii 200))
)
  (let
    (
      (authority-id (var-get next-authority-id))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len authority-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len accreditation-number) u0) ERR-INVALID-INPUT)

    (map-set certification-authorities
      { authority-id: authority-id }
      {
        authority-name: authority-name,
        authority-type: authority-type,
        accreditation-number: accreditation-number,
        contact-info: contact-info,
        authorized: true,
        registration-date: block-height
      }
    )

    (var-set next-authority-id (+ authority-id u1))
    (ok authority-id)
  )
)

(define-public (authorize-certification-authority (authority-id uint) (authorized bool))
  (let
    (
      (authority (unwrap! (map-get? certification-authorities { authority-id: authority-id }) ERR-AUTHORITY-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (ok (map-set certification-authorities
      { authority-id: authority-id }
      (merge authority { authorized: authorized })
    ))
  )
)

;; Certification Standard Management
(define-public (add-certification-standard
  (standard-name (string-ascii 50))
  (description (string-ascii 300))
  (validity-period uint)
  (renewal-required bool)
  (minimum-score uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len standard-name) u0) ERR-INVALID-INPUT)
    (asserts! (> validity-period u0) ERR-INVALID-INPUT)
    (asserts! (<= minimum-score u100) ERR-INVALID-INPUT)

    (ok (map-set certification-standards
      { standard-name: standard-name }
      {
        description: description,
        validity-period: validity-period,
        renewal-required: renewal-required,
        minimum-score: minimum-score,
        active: true
      }
    ))
  )
)

;; Certification Issuance Functions
(define-public (issue-certification
  (certification-type (string-ascii 50))
  (holder principal)
  (issuing-authority-id uint)
  (expiry-date uint)
  (scope (string-ascii 200))
  (certificate-hash (buff 32))
)
  (let
    (
      (certification-id (var-get next-certification-id))
      (authority (unwrap! (map-get? certification-authorities { authority-id: issuing-authority-id }) ERR-AUTHORITY-NOT-FOUND))
      (standard (map-get? certification-standards { standard-name: certification-type }))
    )
    (asserts! (get authorized authority) ERR-NOT-AUTHORIZED)
    (asserts! (> expiry-date block-height) ERR-INVALID-INPUT)
    (asserts! (> (len certification-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len scope) u0) ERR-INVALID-INPUT)

    (map-set certifications
      { certification-id: certification-id }
      {
        certification-type: certification-type,
        holder: holder,
        issuing-authority-id: issuing-authority-id,
        issue-date: block-height,
        expiry-date: expiry-date,
        status: "active",
        scope: scope,
        certificate-hash: certificate-hash,
        renewal-count: u0
      }
    )

    (map-set holder-certifications
      { holder: holder, certification-type: certification-type }
      { certification-id: certification-id, active: true }
    )

    (var-set next-certification-id (+ certification-id u1))
    (ok certification-id)
  )
)

(define-public (renew-certification
  (certification-id uint)
  (new-expiry-date uint)
  (certificate-hash (buff 32))
)
  (let
    (
      (certification (unwrap! (map-get? certifications { certification-id: certification-id }) ERR-CERTIFICATION-NOT-FOUND))
      (authority (unwrap! (map-get? certification-authorities { authority-id: (get issuing-authority-id certification) }) ERR-AUTHORITY-NOT-FOUND))
    )
    (asserts! (get authorized authority) ERR-NOT-AUTHORIZED)
    (asserts! (> new-expiry-date block-height) ERR-INVALID-INPUT)

    (ok (map-set certifications
      { certification-id: certification-id }
      (merge certification {
        expiry-date: new-expiry-date,
        certificate-hash: certificate-hash,
        renewal-count: (+ (get renewal-count certification) u1),
        status: "active"
      })
    ))
  )
)

(define-public (revoke-certification (certification-id uint))
  (let
    (
      (certification (unwrap! (map-get? certifications { certification-id: certification-id }) ERR-CERTIFICATION-NOT-FOUND))
      (authority (unwrap! (map-get? certification-authorities { authority-id: (get issuing-authority-id certification) }) ERR-AUTHORITY-NOT-FOUND))
    )
    (asserts! (get authorized authority) ERR-NOT-AUTHORIZED)

    (map-set holder-certifications
      { holder: (get holder certification), certification-type: (get certification-type certification) }
      { certification-id: certification-id, active: false }
    )

    (ok (map-set certifications
      { certification-id: certification-id }
      (merge certification { status: "revoked" })
    ))
  )
)

;; Read-only Functions
(define-read-only (get-certification (certification-id uint))
  (map-get? certifications { certification-id: certification-id })
)

(define-read-only (get-certification-authority (authority-id uint))
  (map-get? certification-authorities { authority-id: authority-id })
)

(define-read-only (get-certification-standard (standard-name (string-ascii 50)))
  (map-get? certification-standards { standard-name: standard-name })
)

(define-read-only (verify-certification (certification-id uint))
  (match (map-get? certifications { certification-id: certification-id })
    certification
    (let
      (
        (is-active (is-eq (get status certification) "active"))
        (not-expired (> (get expiry-date certification) block-height))
        (authority (map-get? certification-authorities { authority-id: (get issuing-authority-id certification) }))
      )
      (ok {
        valid: (and is-active not-expired),
        status: (get status certification),
        expires: (get expiry-date certification),
        authority-authorized: (default-to false (get authorized authority))
      })
    )
    ERR-CERTIFICATION-NOT-FOUND
  )
)

(define-read-only (get-holder-certification (holder principal) (certification-type (string-ascii 50)))
  (match (map-get? holder-certifications { holder: holder, certification-type: certification-type })
    holder-cert
    (if (get active holder-cert)
      (map-get? certifications { certification-id: (get certification-id holder-cert) })
      none
    )
    none
  )
)

(define-read-only (is-certification-valid (certification-id uint))
  (match (map-get? certifications { certification-id: certification-id })
    certification
    (and
      (is-eq (get status certification) "active")
      (> (get expiry-date certification) block-height)
    )
    false
  )
)

(define-read-only (get-certification-details (holder principal) (certification-type (string-ascii 50)))
  (match (get-holder-certification holder certification-type)
    certification (ok {
      certification-type: (get certification-type certification),
      issue-date: (get issue-date certification),
      expiry-date: (get expiry-date certification),
      status: (get status certification),
      scope: (get scope certification)
    })
    ERR-CERTIFICATION-NOT-FOUND
  )
)
