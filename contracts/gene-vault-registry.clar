;; gene-vault-registry.clar
;; A contract for tokenizing and licensing biotechnology IP as NFTs.
;; Owners can mint, transfer, and create royalty-bearing licenses for their IP.

;; --- SIP-009 NFT Trait Definition ---
(define-trait nft-trait
  (
    ;; Last token ID, limited to uint range
    (get-last-token-id () (response uint uint))

    ;; URI for metadata associated with the token
    (get-token-uri (uint) (response (optional (string-ascii 256)) uint))

    ;; Owner of a given token identifier
    (get-owner (uint) (response (optional principal) uint))

    ;; Transfer from the sender to a new principal
    (transfer (uint principal principal) (response bool uint))
  )
)

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
(define-constant ERR-INVALID-ROYALTY (err u108))
(define-constant ERR-ZERO-AMOUNT (err u109))
(define-constant ERR-INVALID-TOKEN-ID (err u110))

;; Maximum royalty percentage (100%)
(define-constant MAX-ROYALTY-PERCENT u100)

;; --- Data Storage ---
(define-non-fungible-token gene-vault-nft uint)
(define-data-var last-token-id uint u0)

;; Token metadata storage
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
  royalty-percent: uint,
  active: bool
})

;; Map for active licenses
(define-map active-licenses {ip-id: uint, licensee: principal} {
  license-start-block: uint,
  royalties-paid: uint,
  active: bool
})

;; --- SIP-009 NFT Trait Implementation ---

;; Get the last token ID
(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

;; Get the URI for a token's metadata (returns none as metadata is on-chain)
(define-read-only (get-token-uri (token-id uint))
  (if (is-some (nft-get-owner? gene-vault-nft token-id))
    (ok none)
    ERR-NOT-FOUND
  )
)

;; Get the owner of a specific token
(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? gene-vault-nft token-id))
)

;; Transfer a token to a new owner
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    ;; Verify the sender is the tx-sender
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)

    ;; Validate recipient is not zero address and not same as sender
    (asserts! (not (is-eq recipient sender)) ERR-NOT-AUTHORIZED)

    ;; Verify token exists and sender owns it
    (asserts! (is-eq (some sender) (nft-get-owner? gene-vault-nft token-id)) ERR-NOT-OWNER)

    ;; Perform the transfer using validated recipient
    (try! (nft-transfer? gene-vault-nft token-id sender recipient))

    (print {type: "nft-transfer", token-id: token-id, sender: sender, recipient: recipient})
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
    ;; Only contract owner can mint
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    ;; Validate inputs
    (asserts! (> (len name) u0) ERR-INVALID-TOKEN-ID)
    (asserts! (> (len description) u0) ERR-INVALID-TOKEN-ID)
    (asserts! (> (len metadata-hash) u0) ERR-INVALID-TOKEN-ID)

    ;; Validate recipient is not contract owner (prevent self-minting issues)
    (asserts! (not (is-eq recipient CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)

    ;; Mint the NFT - use recipient directly after validation
    (match (nft-mint? gene-vault-nft token-id recipient)
      success (begin
        ;; Store metadata
        (map-set token-metadata token-id {
          name: name,
          description: description,
          metadata-hash: metadata-hash,
          metadata-frozen: false
        })

        ;; Update last token ID
        (var-set last-token-id token-id)

        (print {type: "nft-mint", token-id: token-id, recipient: recipient})
        (ok token-id)
      )
      error ERR-NOT-AUTHORIZED
    )
  )
)

;; @desc Allows the IP owner to freeze the metadata, making it immutable.
(define-public (freeze-metadata (ip-id uint))
  (let ((current-owner (nft-get-owner? gene-vault-nft ip-id)))
    ;; Verify token exists
    (asserts! (is-some current-owner) ERR-NOT-FOUND)

    ;; Verify caller is owner
    (asserts! (is-eq tx-sender (unwrap-panic current-owner)) ERR-NOT-OWNER)

    ;; Get current metadata
    (match (map-get? token-metadata ip-id)
      metadata (begin
        ;; Check if already frozen
        (asserts! (not (get metadata-frozen metadata)) ERR-METADATA-FROZEN)

        ;; Freeze metadata
        (map-set token-metadata ip-id (merge metadata {metadata-frozen: true}))

        (print {type: "metadata-frozen", ip-id: ip-id})
        (ok true)
      )
      ERR-NOT-FOUND
    )
  )
)

;; @desc The owner of an IP-NFT lists it for licensing.
;; @param ip-id: The ID of the IP NFT to license.
;; @param license-fee: The upfront cost in uSTX to acquire the license.
;; @param royalty-percent: The percentage of future revenue due as royalty.
(define-public (list-for-license (ip-id uint) (license-fee uint) (royalty-percent uint))
  (let ((current-owner (nft-get-owner? gene-vault-nft ip-id)))
    ;; Verify token exists
    (asserts! (is-some current-owner) ERR-NOT-FOUND)

    ;; Verify caller is owner
    (asserts! (is-eq tx-sender (unwrap-panic current-owner)) ERR-NOT-OWNER)

    ;; Validate royalty percentage
    (asserts! (<= royalty-percent MAX-ROYALTY-PERCENT) ERR-INVALID-ROYALTY)

    ;; Validate license fee
    (asserts! (> license-fee u0) ERR-ZERO-AMOUNT)

    ;; Create listing
    (map-set license-listings ip-id {
      licensor: (unwrap-panic current-owner),
      license-fee: license-fee,
      royalty-percent: royalty-percent,
      active: true
    })

    (print {type: "license-listing", ip-id: ip-id, fee: license-fee, royalty: royalty-percent})
    (ok true)
  )
)

;; @desc Remove a license listing
(define-public (remove-license-listing (ip-id uint))
  (let ((current-owner (nft-get-owner? gene-vault-nft ip-id)))
    ;; Verify token exists
    (asserts! (is-some current-owner) ERR-NOT-FOUND)

    ;; Verify caller is owner
    (asserts! (is-eq tx-sender (unwrap-panic current-owner)) ERR-NOT-OWNER)

    ;; Remove listing
    (map-delete license-listings ip-id)

    (print {type: "license-delisted", ip-id: ip-id})
    (ok true)
  )
)

;; @desc A third party executes a license agreement by paying the fee.
;; @param ip-id: The ID of the IP NFT to license.
(define-public (execute-license (ip-id uint))
  (let (
    (listing (unwrap! (map-get? license-listings ip-id) ERR-LISTING-NOT-FOUND))
    (licensee tx-sender)
    (license-key {ip-id: ip-id, licensee: licensee})
  )
    ;; Verify listing is active
    (asserts! (get active listing) ERR-LISTING-NOT-FOUND)

    ;; Verify not already licensed
    (asserts! (is-none (map-get? active-licenses license-key)) ERR-ALREADY-LICENSED)

    ;; Verify licensee is not the licensor
    (asserts! (not (is-eq licensee (get licensor listing))) ERR-NOT-AUTHORIZED)

    ;; Pay the license fee to the licensor
    (try! (stx-transfer? (get license-fee listing) tx-sender (get licensor listing)))

    ;; Create active license
    (map-set active-licenses license-key {
      license-start-block: block-height,
      royalties-paid: u0,
      active: true
    })

    ;; Deactivate listing (allows for exclusive licensing)
    (map-set license-listings ip-id (merge listing {active: false}))

    (print {type: "license-executed", ip-id: ip-id, licensee: licensee, fee: (get license-fee listing)})
    (ok true)
  )
)

;; @desc A licensee pays royalties to the IP owner.
;; @param ip-id: The ID of the licensed IP.
;; @param royalty-amount: The amount of uSTX being paid as royalty.
(define-public (pay-royalty (ip-id uint) (royalty-amount uint))
  (let (
    (license-key {ip-id: ip-id, licensee: tx-sender})
    (current-owner (nft-get-owner? gene-vault-nft ip-id))
  )
    ;; Verify token exists
    (asserts! (is-some current-owner) ERR-NOT-FOUND)

    ;; Verify royalty amount is positive
    (asserts! (> royalty-amount u0) ERR-ZERO-AMOUNT)

    ;; Get license details
    (match (map-get? active-licenses license-key)
      license-details (begin
        ;; Verify license is active
        (asserts! (get active license-details) ERR-LICENSE-INACTIVE)

        ;; Pay royalty to current IP owner
        (try! (stx-transfer? royalty-amount tx-sender (unwrap-panic current-owner)))

        ;; Update royalties paid
        (map-set active-licenses license-key (merge license-details {
          royalties-paid: (+ (get royalties-paid license-details) royalty-amount)
        }))

        (print {type: "royalty-paid", ip-id: ip-id, licensee: tx-sender, amount: royalty-amount})
        (ok true)
      )
      ERR-LICENSE-INACTIVE
    )
  )
)

;; @desc Revoke an active license (only by IP owner)
(define-public (revoke-license (ip-id uint) (licensee principal))
  (let (
    (current-owner (nft-get-owner? gene-vault-nft ip-id))
    (license-key {ip-id: ip-id, licensee: licensee})
  )
    ;; Verify token exists
    (asserts! (is-some current-owner) ERR-NOT-FOUND)

    ;; Verify caller is owner
    (asserts! (is-eq tx-sender (unwrap-panic current-owner)) ERR-NOT-OWNER)

    ;; Get license details
    (match (map-get? active-licenses license-key)
      license-details (begin
        ;; Deactivate license
        (map-set active-licenses license-key (merge license-details {active: false}))

        (print {type: "license-revoked", ip-id: ip-id, licensee: licensee})
        (ok true)
      )
      ERR-LICENSE-INACTIVE
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
  (map-get? active-licenses {ip-id: ip-id, licensee: licensee})
)

;; @desc Get total royalties paid by a licensee for a specific IP
(define-read-only (get-total-royalties-paid (ip-id uint) (licensee principal))
  (match (map-get? active-licenses {ip-id: ip-id, licensee: licensee})
    license-details (some (get royalties-paid license-details))
    none
  )
)

;; @desc Check if a token exists
(define-read-only (token-exists (token-id uint))
  (is-some (nft-get-owner? gene-vault-nft token-id))
)

;; @desc Get contract info
(define-read-only (get-contract-info)
  {
    contract-owner: CONTRACT-OWNER,
    total-tokens: (var-get last-token-id)
  }
)