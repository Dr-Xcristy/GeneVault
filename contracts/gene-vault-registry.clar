;; gene-vault-registry.clar
;; A contract for tokenizing and licensing biotechnology IP as NFTs.
;; Owners can mint, transfer, and create royalty-bearing licenses for their IP.

;; --- Traits and Interfaces ---
(impl-trait 'STX.sip-009-nft-trait.nft-trait)

;; --- Constants ---
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-LICENSED (err u102))
(define-constant ERR-NOT-OWNER (err u103))
(define-constant ERR-LISTING-NOT-FOUND (err u104))
(define-constant ERR-INCORRECT-PAYMENT (err u105))
(define-constant ERR-LICENSE-INACTIVE (err u106))
(define-constant ERR-METADATA-FROZEN (err u107))

;; --- Data Storage ---
(define-fungible-token gene-vault-nft)
(define-data-var last-token-id uint u0)
(define-map token-owner uint principal)
(define-map token-metadata uint {
  name: (string-ascii 256),
  description: (string-utf8 1024),
  metadata-hash: (buff 32),
  metadata-frozen: bool
})

;; Map for licensing listings
(define-map license-listings uint {
  licensor: principal,
  license-fee: uint,
  royalty-percent: uint ;; e.g., u5 = 5%
})

;; Map for active licenses
(define-map active-licenses (tuple (ip-id uint) (licensee principal)) {
  license-start-tx: (buff 32),
  royalties-paid: uint
})

;; --- SIP-009 NFT Trait Implementation ---

;; Get the last token ID
(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

;; Get the URI for a token's metadata
(define-read-only (get-token-uri (token-id uint))
  (ok none) ;; Metadata is stored on-chain in this implementation
)

;; Get the owner of a specific token
(define-read-only (get-owner (token-id uint))
  (ok (map-get? token-owner token-id))
)

;; Transfer a token to a new owner
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? token-owner token-id)) ERR-NOT-FOUND)
    (asserts! (is-eq (unwrap! (map-get? token-owner token-id) (err u0)) sender) ERR-NOT-OWNER)

    (map-set token-owner token-id recipient)
    (print { type: "nft-transfer", token-id: token-id, sender: sender, recipient: recipient })
    (ok true)
  )
)

;; --- Contract-Specific Functions ---

;; @desc Mints a new IP NFT. Can only be called by the contract owner.
;; @param recipient: The principal who will own the new IP NFT.
;; @param name: The name of the intellectual property.
;; @param description: A detailed description of the IP.
;; @param metadata-hash: A hash of off-chain documentation (e.g., patent filings).
(define-public (mint-ip-nft (recipient principal) (name (string-ascii 256)) (description (string-utf8 1024)) (metadata-hash (buff 32)))
  (let ((token-id (+ (var-get last-token-id) u1)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set token-owner token-id recipient)
    (map-set token-metadata token-id {
      name: name,
      description: description,
      metadata-hash: metadata-hash,
      metadata-frozen: false
    })
    (var-set last-token-id token-id)

    (print { type: "nft-mint", token-id: token-id, recipient: recipient })
    (ok token-id)
  )
)

;; @desc Allows the IP owner to freeze the metadata, making it immutable.
(define-public (freeze-metadata (ip-id uint))
  (let ((owner (unwrap! (map-get? token-owner ip-id) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender owner) ERR-NOT-OWNER)
    (let ((metadata (unwrap! (map-get? token-metadata ip-id) ERR-NOT-FOUND)))
      (asserts! (not (get metadata-frozen metadata)) ERR-METADATA-FROZEN)
      (map-set token-metadata ip-id (merge metadata { metadata-frozen: true }))
      (ok true)
    )
  )
)

;; @desc The owner of an IP-NFT lists it for licensing.
;; @param ip-id: The ID of the IP NFT to license.
;; @param license-fee: The upfront cost in uSTX to acquire the license.
;; @param royalty-percent: The percentage of future revenue due as royalty.
(define-public (list-for-license (ip-id uint) (license-fee uint) (royalty-percent uint))
  (let ((owner (unwrap! (map-get? token-owner ip-id) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender owner) ERR-NOT-OWNER)
    (map-set license-listings ip-id {
      licensor: owner,
      license-fee: license-fee,
      royalty-percent: royalty-percent
    })
    (print { type: "license-listing", ip-id: ip-id, fee: license-fee })
    (ok true)
  )
)

;; @desc A third party executes a license agreement by paying the fee.
;; @param ip-id: The ID of the IP NFT to license.
(define-public (execute-license (ip-id uint))
  (let ((listing (unwrap! (map-get? license-listings ip-id) ERR-LISTING-NOT-FOUND))
        (licensee tx-sender))
    (asserts! (is-none (map-get? active-licenses { ip-id: ip-id, licensee: licensee })) ERR-ALREADY-LICENSED)

    ;; Pay the license fee to the licensor
    (try! (stx-transfer? (get license-fee listing) tx-sender (get licensor listing)))

    (map-set active-licenses { ip-id: ip-id, licensee: licensee } {
      license-start-tx: tx-hash,
      royalties-paid: u0
    })

    ;; Delist after one license is granted (can be modified for multiple licenses)
    (map-delete license-listings ip-id)

    (print { type: "license-executed", ip-id: ip-id, licensee: licensee })
    (ok true)
  )
)

;; @desc A licensee pays royalties to the IP owner.
;; @param ip-id: The ID of the licensed IP.
;; @param royalty-amount: The amount of uSTX being paid as royalty.
(define-public (pay-royalty (ip-id uint) (royalty-amount uint))
  (let ((license-key { ip-id: ip-id, licensee: tx-sender }))
    (let ((license-details (unwrap! (map-get? active-licenses license-key) ERR-LICENSE-INACTIVE))
          (ip-owner (unwrap! (map-get? token-owner ip-id) ERR-NOT-FOUND)))

      (try! (stx-transfer? royalty-amount tx-sender ip-owner))

      (map-set active-licenses license-key (merge license-details {
        royalties-paid: (+ (get royalties-paid license-details) royalty-amount)
      }))
      (ok true)
    )
  )
)

;; --- Read-Only Functions ---

;; @desc Get the metadata for a specific IP NFT.
(define-read-only (get-ip-details (ip-id uint))
  (map-get? token-metadata ip-id)
)

;; @desc Get the details of a license listing.
(define-read-only (get-license-listing (ip-id uint))
  (map-get? license-listings ip-id)
)

;; @desc Check the status of an active license for a given licensee.
(define-read-only (get-licensee-status (ip-id uint) (licensee principal))
  (map-get? active-licenses { ip-id: ip-id, licensee: licensee })
)