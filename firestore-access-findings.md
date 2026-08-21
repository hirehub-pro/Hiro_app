# Firestore access findings

Scope: worker profiles/contact fields, chat messages, reviews, public worker
schedules and projects, work requests, and chat-to-invoice/client creation.

- For new workers, `users/{uid}` contains account role, subscription,
  verification, billing, and other server/account fields. The app no longer
  writes the worker's name, contact details, profile content, service location,
  professions, languages, town, radius, or schedule visibility there.
- `publicWorkerProfiles/{uid}` is the canonical worker profile. The product
  intentionally exposes name, email, phone, optional phone, description, town,
  precise latitude/longitude, work radius, avatar, professions, languages, and
  verification badges whenever the worker is search-visible. Schedule
  visibility is stored only in the nested schedule document.
- The owner may edit only those bounded public-profile fields. Ratings,
  verification badges, role, creation identity, and search visibility remain
  backend-controlled. The `users/{uid}` trigger preserves public-owned fields
  while refreshing backend-controlled profile status.
- Existing Firebase documents are not migrated. Legacy profile fields can
  remain in `users/{uid}`, but worker-facing code treats the public document as
  authoritative.
- Contact details returned by the contact callable now come from the canonical
  public worker document for workers and from `users/{uid}` for customers.
- `chat_rooms/{roomId}` contains `users`, names, last-message metadata, and unread
  counters. An authenticated callable creates or repairs the canonical room for
  exactly the current user and requested receiver before the listener starts.
- `chat_rooms/{roomId}/messages/{messageId}` is participant-only. Optional fields
  must be omitted rather than written as null.
- `users/{senderUid}/requests/{requestId}` is owned by the sender.
- `users/{workerUid}/RequestToMe/{requestId}` is created by the authenticated
  sender for the worker named in the request and read by the worker.
- Work-request notification and chat-link payloads use bounded text, timestamps,
  media URL lists, location data, and immutable sender/worker identifiers.
- `publicWorkerProfiles/{workerUid}/reviews/{reviewerUid}` stores at most one review per
  reviewer/worker pair. The reviewer may create or replace that document, while
  a backend trigger owns aggregate fields on the worker and `ProRating` docs.
- Review payloads include profession, three required 1-5 category ratings,
  optional profile image, up to 10 image URLs, bounded comment, and timestamp.
- `publicWorkerProfiles/{workerUid}/Schedule/info` is the public availability
  document and the canonical location of `hideSchedule`. The worker owns
  writes; authenticated users may read it only while the parent profile is
  search-visible and the schedule document's `hideSchedule` is false.
- `publicWorkerProfiles/{workerUid}` does not contain `hideSchedule` or
  `isInsured`; both fields are rejected by the strict public-profile schema.
- `publicWorkerProfiles/{workerUid}/projects/{projectId}` stores public portfolio
  media and descriptions. The worker owns project creation, edits, and deletion.
  Guests and authenticated users may read projects only while the parent worker
  profile is search-visible. The create schema requires a recent timestamp and
  bounded description/media fields; the timestamp is immutable on update.
- Project comments contain the authenticated author's UID, bounded display name,
  optional HTTPS profile image, bounded text, and a recent timestamp. Public
  reads and authenticated creates require an existing project on a visible
  worker profile. Authors can edit/delete their comments; project owners and
  admins can delete them.
- Project likes use the liker UID as the document ID and store only that UID and
  a recent timestamp. A user can read and change only their own like; the project
  owner may list likes. Backend triggers calculate `likesCount` and
  `commentsCount`, so clients cannot replay counter increments.
- Legacy `users/{workerUid}/projects` documents are intentionally not migrated.
  They are owner/admin-readable rollback data and reject client writes.
- `reports/{reportId}` is admin-managed, but an authenticated reporter may read
  their own reports through a `where(reporterId == request.auth.uid)` query.

Relevant queries:

- Worker discovery: `publicWorkerProfiles` with
  `where(isSearchVisible == true)`, plus profession, rating/name, distance, and
  public phone lookup filters. The public phone lookup has a matching
  `isSearchVisible + phone` composite index.
- Chat messages: `orderBy(timestamp, descending: true)`.
- Saved clients: owner-scoped reads and `where(taxId == ...)`.
- Sent/incoming requests: owner-scoped `where(type, whereIn: [...])`.
- Reports page: `where(reporterId == currentUser.uid)`, with optional status
  equality filtering.
- Schedule: direct conditional read of
  `publicWorkerProfiles/{workerUid}/Schedule/info`.
- Worker social links are owner-written directly on
  `publicWorkerProfiles/{workerUid}.socialLinks`; each entry is restricted to
  bounded `type`, `name`, and HTTPS `url` fields. Customer links remain on the
  private `users/{uid}` account document.
- Favorites are one-way private bookmarks stored only under
  `users/{ownerUid}/favorites/{workerUid}`. The former reciprocal
  `users/{workerUid}/likedBy/{ownerUid}` write and read model is no longer used.
- The admin panel lists private `users` documents for customers and workers,
  then merges each worker's `publicWorkerProfiles/{uid}` display fields. Admin
  authorization accepts either the Auth `admin` custom claim or an existing
  server-assigned `users/{uid}.role == admin`; client creation and owner updates
  cannot create or modify that role.
- Professional verification decisions use the admin-only
  `reviewBusinessVerification` callable. A single backend transaction updates
  the private account approval flags, the latest request status, the public
  business-verification badge, the user notification, and the legacy queue.
- Business verification details live only in
  `users/{uid}/verification_info/latest`. Its canonical fields include
  `businessId`, `businessLogoUrl`, and `businessVerificationStatus`; the parent
  user document no longer stores or accepts those fields. Verification writes
  are server-only, while the owner and administrators may read the document.
- Projects: direct collection read of
  `publicWorkerProfiles/{workerUid}/projects`; nested comments are ordered by
  `timestamp` ascending or descending. Like state uses a direct document get.

Project-rule adversarial review:

- Public list exploit: hidden-profile project and comment reads are denied;
  visible-profile projects/comments are intentionally guest-readable.
- Unauthorized writes and ownership hijacking: only the path owner can create,
  edit, or delete a project; comment/like identity must match Firebase Auth.
- Update/schema bypass: project and comment updates re-run their validators;
  project and comment timestamps and comment author identity are immutable.
- Type/size/schema pollution: project, comment, and like documents use strict
  allowed-field validators with bounded strings, lists, URLs, and counters.
- Counter replay: clients cannot write project counters through interaction
  rules; backend triggers derive both counters from their subcollections.
- Orphan access: nested interactions require the parent project to exist, and
  non-owners additionally require a visible public worker profile.
- Query mismatch: project lists depend only on the parent profile; comment
  ordering has no document-level predicate, so both app queries are permitted.

Schedule/public-profile adversarial review (21-point rules checklist):

1. Public list: only search-visible profiles list; schedules require auth,
   visibility, and `hideSchedule == false`.
2. Unauthorized CRUD: only the worker owns profile/schedule writes.
3. Update bypass: both profile and schedule updates rerun strict validators.
4. Create ownership: profile UID/path ownership is enforced.
5. Update ownership: UID cannot be changed by an owner update.
6. Immutable fields: owner updates cannot change role, verification, creation,
   ratings, or search visibility.
7. Type juggling: schedule visibility must be a boolean.
8. Create/update parity: the same schedule validator covers both operations.
9. Resource exhaustion: schedule lists/maps and profile strings/lists are
   bounded.
10. Required fields: public profile UID, role, and name remain required.
11. Privilege escalation: clients cannot set verification/search fields.
12. Schema pollution: parent `hideSchedule`, `isInsured`, and unknown fields
    are rejected.
13. State transitions: no client-controlled workflow status exists here.
14. Path traversal: ownership derives from the authenticated path UID.
15. Timestamp manipulation: optional timestamps must be Firestore timestamps;
    server-controlled profile fields remain immutable.
16. Numeric abuse: coordinates, ratings, counts, and radius remain bounded.
17. Mixed-content leak: discovery data stays in the intentionally public
    worker projection; private account data remains owner/admin-only.
18. Counter replay: profile rating counters remain server-managed.
19. Orphan access: non-owner schedule reads require a visible parent profile.
20. Query mismatch: discovery uses `isSearchVisible == true`; schedules use
    direct document gets matching the conditional rule.
21. Validator pattern: both public-profile and schedule creates/updates call
    their domain validators.
