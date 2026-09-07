# Subscription Firestore access audit

## Paths used by the subscription system

- `users/{uid}`: private account document. The client may read its own document,
  but subscription aggregate fields are server-controlled.
- `users/{uid}/subscriptionEntitlements/app_store`: authoritative Apple
  entitlement. Server-only read/write.
- `users/{uid}/subscriptionEntitlements/google_play`: authoritative Google Play
  entitlement. Server-only read/write.
- `subscriptionOwnership/{identifierHash}`: server-only ownership index used to
  map provider account/transaction identifiers to a Firebase UID.
- `subscriptionNotificationEvents/{eventId}`: server-only notification audit.
- `users/{uid}/subscriptionPayments/{paymentId}`: owner-visible diagnostic
  purchase record; it is not trusted when granting access.

## Queries and writers

- Callable purchase preparation claims an account-token ownership record before
  StoreKit or Play Billing opens.
- Callable verification validates the provider response, updates only that
  provider's entitlement document, then derives the aggregate user fields.
- Apple and Google notification handlers resolve the owner through the ownership
  index and update only their own provider document.
- The scheduled lifecycle job reads both entitlement documents for every worker,
  refreshes each provider independently, and recalculates aggregate access.

## Rule requirements

- Clients must not create, update, delete, list, or read provider entitlement or
  ownership documents.
- Clients must not modify aggregate subscription fields on `users/{uid}`.
- Admin SDK Cloud Functions bypass Firestore Rules and are the only writers.

## Paid-feature authorization audit

- Job-request comments and bids are written under
  `blog_posts/{postId}/blog_comments/{commentId}`. New paid job responses must
  require an active worker entitlement; ordinary community comments remain
  available without Pro.
- Worker quote/status responses update both
  `users/{customerUid}/requests/{requestId}` and
  `users/{workerUid}/RequestToMe/{requestId}`. The assigned worker branches
  must require Pro, while customer edits remain available.
- Client records stay owner-readable after cancellation so user data is not
  held hostage, but creating or editing clients requires Pro.
- Analytics reads from `metadata/financial_summary`, `ProRating`, and `VPD`.
  These paths require Pro. Server maintenance continues through Admin SDK.
- New document previews, documents, tax drafts, counter initialization,
  exports, signature requests, Tax Authority connection starts, and invoice
  email-code starts require provider-backed Pro authorization in Cloud
  Functions. Recovery/finalization of an already reserved legal document and
  reads of existing documents remain available after cancellation.
- Firestore checks the backend-maintained aggregate fields and a future expiry.
  Cloud Functions additionally inspect the private per-provider entitlement
  documents, accepting access when either Apple or Google remains active.
