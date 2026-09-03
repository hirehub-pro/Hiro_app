# PDF digital signatures

Hiro cryptographically signs finalized accounting PDFs after rendering and
before upload. Quotes, work orders, and preview PDFs are intentionally not
issuer-signed by this workflow.

## Signature format

- CMS detached PDF signature with the `adbe.pkcs7.detached` subfilter
- SHA-256 document digest
- RSA-2048 business signing key
- One self-signed X.509 certificate per verified Hiro business account
- The signature covers the complete PDF, so any later PDF modification makes
  verification fail

The certificate is created automatically on the first finalized accounting
document. Its PKCS#12 private key and random passphrase are encrypted with
AES-256-GCM and stored at
`users/{userId}/documentSigningCredentials/{businessId}`. Firestore client
rules deny all access to that collection.

## Required secret

The Cloud Functions secret `PDF_SIGNING_MASTER_KEY` must contain exactly 32
random bytes encoded as base64. It is bound only to functions that finalize
accounting documents.

Treat this secret as long-lived key material. Do not rotate or delete it until
all stored business credentials have been re-encrypted with the replacement.
Losing it makes existing business signing keys unrecoverable, although already
signed PDFs remain independently verifiable.

## Verification and trust

The automated test extracts the CMS signature and verifies it independently
with OpenSSL. It also changes one byte in a signed PDF and confirms that
verification fails.

The certificate is self-signed. PDF readers can verify document integrity and
show the embedded business identity, but they may label the signer certificate
as untrusted until Hiro's certificate/fingerprint is trusted by the verifier.
This implementation does not include a public certificate authority or an
RFC 3161 trusted timestamp. Legal classification under the Israeli Electronic
Signature Law should be confirmed separately before presenting the certificate
as an accredited signature.
