# Growth recommendation decision system

The analytics card selects one opportunity using evidence thresholds and a deterministic priority order. It is local Dart logic, not an LLM call. The recommendation stays business-wide when the dashboard profession filter changes. Individual professions may be named as evidence for that one priority.

## Signal inventory

| Signal | Stored source | How it is used / limitation |
|---|---|---|
| Overall and profession views | `publicWorkerProfiles/{uid}/Views` | Lifetime total is summed once across profession counters. Current-week daily counts are evaluated separately. These are view events, not unique visitors. |
| View history | Weekly counters reset | No prior-week/month archive; no claims of view growth or decline. |
| Ratings and samples | `ReviewStats/overall` and profession documents | Overall is authoritative. Only when absent, use review-weighted profession stats, never add both scopes. Missing category scores do not become low scores. |
| Review recency | `reviews`, timestamp and rating | Compare current dated 30-day and preceding 30-day cohorts only with at least five reviews each. These are current review records, not historical overall-rating snapshots; users may edit reviews. No automated claim about sentiment in comment text. |
| Strongest profession | Existing `calculateTopSkillScore` | Review-weighted ranking across listed professions, checked against current profession views. |
| Payments | `users/{uid}/paymentAnalytics/all_time.totalPayments` | Context for gathering feedback. Represents finalized receipts and invoice-receipts, not a job count or invoiced-revenue forecast. |
| Profession earnings / completed jobs | No dependable attribution or completion lifecycle found | Not inferred from invoices, accepted quotes or accepted requests. |
| In-app inquiries | `users/{uid}/RequestToMe` | Work and quote requests are separate types. Uses timestamps, profession and statuses. Not all phone/chat leads. No view-to-request conversion percentage is calculated. |
| Bookings | Accepted work requests | Remain labelled accepted work requests. An accepted quote request may only mean a quote was sent. |
| Waiting requests | Pending status and timestamp | Excludes expired appointments and future records; age is not response time. |
| Lost requests | Cancelled/declined/rejected work requests | Needs at least 10 work requests aged 2+ days, at least 3 lost and 30% lost. No attribution of fault or cause. |
| Profile completeness | Public description, image, professions, town | Names one verified missing field, links to profile editing. A zero radius is not automatically wrong. |
| Portfolio | `projects`, media and timestamp | Projects are not profession-tagged: project counts are explicitly for the whole portfolio. Recency claims need dates on all fetched projects. |
| Availability | `Schedule/info` | Upcoming explicit work dates and disabled days; hidden calendars and upcoming vacations suppress the gap recommendation. Dates are not appointment-slot counts. |
| Repeat interest | Request `fromId` | Multiple requests from the same sender, labelled repeat inquiries, not completed repeat customers. |
| Response-time metric | Not reliably tracked | Not inferred from pending age, read receipts or quote timestamps. |
| Comparisons/search impressions | No usable dataset found | No competitor benchmarks, search-click rates or ranking claims. |

## Priority rules

Highest priority wins. Ties resolve deterministically. All thresholds are editorial safeguards, not empirically calibrated benchmarks.

1. Actionable requests pending 48+ hours.
2. A supported pattern of cancelled/declined work requests.
3. Recent review-group deterioration or a category gap within the overall/profession rating (five-review minimum; category at most 8/10 and at least one point below peers).
4. Sparse portfolio with current views, few tagged/in-app requests and well-supported strong ratings.
5. Availability gaps with actual recent requests; outdated portfolio with current views and few in-app requests.
6. Very small samples: build evidence instead of diagnosing conversion. Missing profession setup can take precedence.
7. A strongly reviewed profession receiving a small share of views relative to other listed services.
8. Specific portfolio, review-recency, feedback or profile-field opportunities.
9. Repeat inquiry interest; otherwise a useful request-outcome tracking action.

When no higher-priority opportunity exists, a positive fallback is shown only
when all core sources are available and healthy: at least 10 overall reviews
with a 9.0+ average, every rating category at 8.5+, at least 5 reviews and an
8.5+ average for every listed profession, at least 3 portfolio projects with a
project from the last 180 days, at least 2 available work dates in the next 14
days, and at least 5 recent work requests with 3 accepted, no overdue pending
requests, and no more than 20% cancelled/declined/rejected. These thresholds are
product safeguards, not external benchmarks.

The output includes only evidence needed for the chosen decision plus one focused action. Targets concern controllable actions (review requests today, add enough projects to show three useful examples) or explicit observation checkpoints. No promised revenue, inquiry or rating increase.

## Reads and navigation

Additional reads run in parallel inside the existing authorized analytics fetch. Requests and reviews use a 60-day timestamp query, with a 500-record cap; projects have a 100-record cap. A failed or truncated source becomes unknown, not zero. These queries require no new composite indexes. Public profile and primary analytics failure shows a retry state.

CTAs open the existing Edit Profile, Add Project, Schedule, or Requests page. Requests opens directly to the incoming tab. Returning refreshes analytics. Manual service-quality or customer-feedback actions do not get a misleading button. No dedicated price editor or review-list page is fabricated.

The card supports Hebrew, Arabic, English, Russian and Amharic, with RTL and isolated numeric runs. Tests cover decision priority, missing data, scope separation, samples, requests/quotes, dates, localization and the narrow-screen Hebrew card with enlarged text and CTA interaction.

## Verification limits

Local tests do not establish the contents of production Firestore. Live production Firestore records were not read during verification; the CLI project check resolves the existing project. No backend deployment, telemetry schema, conversion attribution, or historic-view storage is added by this change.
