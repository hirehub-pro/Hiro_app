# Firestore request-edit security review

Date: 2026-08-23

## Codebase inventory

- Client: Flutter/Dart with Firebase Auth and Cloud Firestore.
- Trusted backend: Firebase Functions under `functions/`, using Admin SDK access.
- Authentication: Firebase Auth UID; admin checks use an admin custom claim or the existing protected user role.
- Firestore client access scan: 740 collection/query references were reviewed with `rg` across `lib/` (excluding generated dependencies).
- Referenced collection names: `users`, `publicWorkerProfiles`, `requests`, `RequestToMe`, `notifications`, `Schedule`, `chat_rooms`, `messages`, `metadata`, `professions`, `favorites`, `reviews`, `projects`, `ProRating`, `blog_posts`, `blog_comments`, `comments`, `likes`, `reports`, `system_announcements`, `invoices`, `receivedInvoices`, `clients`, `counters`, `files`, `saved_locations`, `deviceTokens`, `verification_info`, `verifications`, `subscriptionPayments`, `admin_activity`, `accountDeletionFeedback`, `clientNumbers`, `clientTaxIds`, `logs`, `shards`, `VPD`, `_document_operations`, and `invoice_builder_lock`.
- Query scan covered all Dart `.where()`, `.orderBy()`, and `.limit()` calls. Request-list queries are owner-scoped subcollections filtered by `type`. Other existing query/rules behavior is unchanged by this feature.

## Request data model and paths

The same validated request schema is denormalized to these paths:

- `users/{senderUid}/requests/{requestId}`: sender-owned canonical request.
- `users/{workerUid}/RequestToMe/{workerRequestToMeId}`: professional's incoming mirror.
- `users/{workerUid}/notifications/{workerNotificationId}`: professional's notification mirror.

Required identity fields are `requestId`, `workerId`, `fromId`, and immutable `timestamp`. Editable fields are optional bounded strings: `date` (40), `requestedFrom` (20), `requestedTo` (20), and `jobDescription` (10,000). `updatedAt` must be a server timestamp.

The sender may edit only when both old and new status are `pending`. The only affected fields may be the four editable fields and `updatedAt`. The sender cannot change status, identities, ownership, timestamps, prices, acceptance data, media, or any schema field. Mirrored edits additionally require the document's `workerId` to match the worker UID in its path.

## CRUD and query impact

- Existing create/read/delete behavior is unchanged.
- Existing worker/owner status and review updates are unchanged.
- New operation: authenticated sender atomically updates the three documents above.
- No new query, list, public read, role, index, or unauthenticated access is introduced.

## Devil's-advocate checks

1. Public list exploit: blocked; no read rules changed.
2. Unauthorized read/write: blocked; edit requires authenticated `fromId` match.
3. Update bypass / oversized description: blocked by `validWorkRequest`/`validNotification` length and schema validators.
4. Ownership hijacking on create: unchanged; existing create validators remain.
5. Ownership hijacking on update: blocked by affected-key allowlist and identity checks.
6. Immutable timestamp modification: blocked; original `timestamp` cannot change.
7. Type juggling: blocked by the existing domain validators.
8. Create-vs-update validation bypass: blocked; validators run on updates.
9. Resource exhaustion: editable string sizes remain bounded.
10. Required-field omission: blocked by the existing validators.
11. Privilege escalation: no role or permission field is editable.
12. Schema pollution: blocked by strict `hasOnly` validators and affected-key allowlist.
13. Invalid state transition: sender must keep `pending`; accepted/rejected/cancelled requests cannot be edited.
14. Path scoping: mirrors require `workerId == userId`; canonical request remains sender-owned.
15. Timestamp manipulation: `updatedAt == request.time`; original timestamp is immutable.
16. Negative/overflow values: no numeric field is newly editable.
17. Mixed-content leak: no read access changed.
18. Counter replay: no counters involved.
19. Orphaned subcollection access: partial creates fail full-schema validation; edit transaction targets known document IDs.
20. Query mismatch: no query behavior changed.
21. Validator pattern: every changed update rule calls its existing domain validator.

## Assumptions and residual review

- Request documents were created by the current send-request flow and contain the mirror IDs.
- The rules are a narrowly scoped prototype change and must be reviewed before broad production rollout.
- The client also performs pending/expiry and future-time checks for UX; authorization does not rely on those client checks.
