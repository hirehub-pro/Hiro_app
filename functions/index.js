const fs = require("fs");
const path = require("path");

const admin = require("firebase-admin");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onRequest} = require("firebase-functions/v2/https");
const {onMessagePublished} = require("firebase-functions/v2/pubsub");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const {google} = require("googleapis");
const {
  AutoRenewStatus,
  Environment,
  SignedDataVerifier,
  Status,
} = require("@apple/app-store-server-library");

admin.initializeApp();

const GOOGLE_PLAY_PACKAGE_NAME = "com.hirehub.app";
const APPLE_BUNDLE_ID = "com.hirehub.app";
const GOOGLE_PLAY_RTDN_TOPIC = "play-subscription-notifications";
const PLAY_ANDROID_PUBLISHER_SCOPE =
  "https://www.googleapis.com/auth/androidpublisher";

exports.sendChatPushOnNotificationCreate = onDocumentCreated(
    {
      document: "users/{userId}/notifications/{notificationId}",
      region: "us-central1",
    },
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const userId = event.params.userId;
      const payload = snap.data() || {};

      const supportedTypes = new Set([
        "chat_message",
        "work_request",
        "quote_request",
        "request_accepted",
        "request_declined",
        "quote_response",
      ]);

      if (!supportedTypes.has(payload.type)) {
        return;
      }

      const userDoc = await admin.firestore().collection("users").doc(userId).get();
      if (!userDoc.exists) {
        logger.warn("Target user doc not found", {userId});
        return;
      }

      const fcmToken = userDoc.get("fcmToken");
      if (!fcmToken || typeof fcmToken !== "string") {
        logger.info("No FCM token for user", {userId});
        return;
      }

      const title = payload.title || defaultTitleForType(payload.type);
      const body = payload.body || defaultBodyForType(payload.type);
      const senderId = payload.fromId || "";
      const senderName = payload.fromName || "User";
      const requestDate = payload.date || "";
      const requestStatus = payload.status || "";

      const message = {
        token: fcmToken,
        notification: {
          title,
          body,
        },
        data: {
          type: dataTypeForNotification(payload.type),
          senderId: String(senderId),
          senderName: String(senderName),
          requestDate: String(requestDate),
          requestStatus: String(requestStatus),
        },
        android: {
          priority: "high",
          notification: {
            channelId: "main_channel",
            priority: "high",
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              contentAvailable: true,
            },
          },
        },
      };

      try {
        await admin.messaging().send(message);
        logger.info("Notification push sent", {
          userId,
          notificationId: snap.id,
          type: payload.type,
        });
      } catch (error) {
        logger.error("Failed to send notification push", {
          userId,
          type: payload.type,
          error,
        });
      }
    },
);

exports.handleGooglePlaySubscriptionNotification = onMessagePublished(
    {
      topic: GOOGLE_PLAY_RTDN_TOPIC,
      region: "us-central1",
    },
    async (event) => {
      const payload = parsePubSubMessage(event?.data?.message);
      const subscriptionNotification = payload?.subscriptionNotification;
      const purchaseToken = subscriptionNotification?.purchaseToken?.trim();

      if (!purchaseToken) {
        logger.info("Ignoring Google Play RTDN without purchase token", {
          payload,
        });
        return;
      }

      const androidPublisher = await createAndroidPublisherClient();
      const syncResult = await syncGooglePlayPurchaseToken({
        androidPublisher,
        purchaseToken,
        notificationType: subscriptionNotification.notificationType,
        eventId: event.id,
      });

      logger.info("Processed Google Play RTDN", syncResult);
    },
);

exports.handleAppStoreServerNotification = onRequest(
    {
      region: "us-central1",
    },
    async (req, res) => {
      if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
      }

      const signedPayload = req.body?.signedPayload || req.body?.signedpayload;
      if (!signedPayload || typeof signedPayload !== "string") {
        res.status(400).send("Missing signedPayload");
        return;
      }

      try {
        const verification = await verifyAppleNotification(signedPayload);
        const notification = verification.notification;
        const transaction = verification.transaction;
        const renewalInfo = verification.renewalInfo;
        const accountToken = (
          transaction?.appAccountToken ||
          renewalInfo?.appAccountToken ||
          ""
        ).trim();

        if (!accountToken) {
          throw new Error("Apple notification is missing appAccountToken");
        }

        const userDoc = await findUserBySubscriptionAccountToken(accountToken);
        if (!userDoc) {
          throw new Error(
              `No user found for Apple subscription account token ${accountToken}`,
          );
        }

        const updates = createAppleSubscriptionUpdates({
          notification,
          transaction,
          renewalInfo,
          userData: userDoc.data(),
          accountToken,
        });

        await applyUserSubscriptionUpdates(userDoc.ref, userDoc.data(), updates);
        await storeNotificationAudit("apple", notification.notificationUUID, {
          accountToken,
          notificationType: notification.notificationType || null,
          subtype: notification.subtype || null,
          userId: userDoc.id,
          transactionId: transaction?.transactionId || null,
          originalTransactionId: transaction?.originalTransactionId || null,
        });

        logger.info("Processed App Store server notification", {
          userId: userDoc.id,
          notificationUUID: notification.notificationUUID || null,
          notificationType: notification.notificationType || null,
          subtype: notification.subtype || null,
        });

        res.status(200).json({ok: true});
      } catch (error) {
        logger.error("Failed to process App Store server notification", {
          error: error.message || String(error),
        });
        res.status(500).json({ok: false});
      }
    },
);

exports.syncWorkerSubscriptionLifecycle = onSchedule(
    {
      schedule: "every 15 minutes",
      region: "us-central1",
      timeZone: "UTC",
    },
    async () => {
      const db = admin.firestore();
      const pageSize = 300;

      let lastDoc = null;
      let scanned = 0;
      let updated = 0;
      let deactivated = 0;
      let playVerified = 0;
      let failures = 0;

      const androidPublisher = await createAndroidPublisherClient();

      while (true) {
        let query = db
            .collection("users")
            .where("role", "==", "worker")
            .orderBy(admin.firestore.FieldPath.documentId())
            .limit(pageSize);

        if (lastDoc) {
          query = query.startAfter(lastDoc.id);
        }

        const snap = await query.get();
        if (snap.empty) break;

        const updates = [];

        for (const doc of snap.docs) {
          scanned += 1;

          const data = doc.data() || {};
          if (!shouldSyncWorkerSubscription(data)) {
            continue;
          }

          try {
            const result = await buildSubscriptionUpdate({
              androidPublisher,
              userData: data,
            });

            if (!result) {
              continue;
            }

            if (result.source === "google_play") {
              playVerified += 1;
            }

            if (!shouldApplySubscriptionUpdate(data, result.updates)) {
              continue;
            }

            updates.push({ref: doc.ref, data: result.updates});
            updated += 1;
            if (result.updates.isSubscribed === false) {
              deactivated += 1;
            }
          } catch (error) {
            failures += 1;
            logger.error("Failed to sync worker subscription", {
              userId: doc.id,
              error: error.message || String(error),
            });
          }
        }

        await commitSubscriptionUpdates(db, updates);
        lastDoc = snap.docs[snap.docs.length - 1];

        if (snap.size < pageSize) {
          break;
        }
      }

      logger.info("Worker subscription lifecycle sync completed", {
        scanned,
        updated,
        deactivated,
        playVerified,
        failures,
      });
    },
);

async function createAndroidPublisherClient() {
  const auth = new google.auth.GoogleAuth({
    scopes: [PLAY_ANDROID_PUBLISHER_SCOPE],
  });
  return google.androidpublisher({
    version: "v3",
    auth,
  });
}

async function syncGooglePlayPurchaseToken({
  androidPublisher,
  purchaseToken,
  notificationType,
  eventId,
}) {
  const playState = await fetchGooglePlaySubscription({
    androidPublisher,
    purchaseToken,
  });

  if (!playState) {
    throw new Error(`No Google Play subscription found for token ${purchaseToken}`);
  }

  const accountToken = (
    playState.externalAccountIdentifiers?.obfuscatedExternalAccountId ||
    ""
  ).trim();

  const userDoc = accountToken ?
    await findUserBySubscriptionAccountToken(accountToken) :
    await findUserByPurchaseToken(purchaseToken);

  if (!userDoc) {
    throw new Error(
        `No user found for Google Play token ${purchaseToken} and account token ${accountToken}`,
    );
  }

  const updates = createPlaySubscriptionUpdates(playState, userDoc.data());
  await applyUserSubscriptionUpdates(userDoc.ref, userDoc.data(), updates);

  await storeNotificationAudit("google_play", eventId || purchaseToken, {
    userId: userDoc.id,
    notificationType: notificationType || null,
    purchaseToken,
    accountToken: accountToken || null,
    subscriptionState: playState.subscriptionState || null,
  });

  return {
    userId: userDoc.id,
    purchaseToken,
    accountToken: accountToken || null,
    notificationType: notificationType || null,
    subscriptionState: playState.subscriptionState || null,
  };
}

function shouldSyncWorkerSubscription(data) {
  if ((data.role || "").toString().toLowerCase() !== "worker") {
    return false;
  }

  const hasToken = typeof data.subscriptionPurchaseToken === "string" &&
    data.subscriptionPurchaseToken.trim().length > 0;
  const status = (data.subscriptionStatus || "").toString().toLowerCase();

  if (hasToken) {
    return true;
  }

  return data.isSubscribed === true || status === "active" ||
    status === "active_canceled";
}

async function buildSubscriptionUpdate({androidPublisher, userData}) {
  const purchaseToken = userData.subscriptionPurchaseToken?.trim();
  if (purchaseToken) {
    const playState = await fetchGooglePlaySubscription({
      androidPublisher,
      purchaseToken,
    });

    if (playState) {
      return {
        source: "google_play",
        updates: createPlaySubscriptionUpdates(playState, userData),
      };
    }
  }

  return {
    source: "firestore",
    updates: createFallbackSubscriptionUpdates(userData),
  };
}

async function fetchGooglePlaySubscription({androidPublisher, purchaseToken}) {
  try {
    const response = await androidPublisher.purchases.subscriptionsv2.get({
      packageName: GOOGLE_PLAY_PACKAGE_NAME,
      token: purchaseToken,
    });

    return response.data || null;
  } catch (error) {
    const status = error?.response?.status;
    if (status === 404 || status === 410) {
      return {
        subscriptionState: "SUBSCRIPTION_STATE_EXPIRED",
        lineItems: [],
      };
    }
    throw error;
  }
}

function createPlaySubscriptionUpdates(playState, userData) {
  const now = new Date();
  const expiry = getLatestExpiry(playState.lineItems);
  const entitledStates = new Set([
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    "SUBSCRIPTION_STATE_CANCELED",
  ]);
  const isEntitled = Boolean(
      expiry &&
      expiry > now &&
      entitledStates.has(playState.subscriptionState || ""),
  );
  const autoRenewEnabled = hasEnabledAutoRenew(playState.lineItems);
  const status = isEntitled ?
    autoRenewEnabled ? "active" : "active_canceled" :
    "inactive";
  const latestLineItem = getLatestLineItem(playState.lineItems);

  return withCommonSubscriptionFields(userData, {
    isSubscribed: isEntitled,
    subscriptionStatus: status,
    subscriptionCanceled: !autoRenewEnabled,
    subscriptionExpiresAt: expiry ?
      admin.firestore.Timestamp.fromDate(expiry) :
      null,
    subscriptionProductId:
      latestLineItem?.productId || userData.subscriptionProductId || null,
    subscriptionPurchaseOrderId:
      playState.latestOrderId || userData.subscriptionPurchaseOrderId || null,
    subscriptionPlatform: "android_play",
    subscriptionProviderState: playState.subscriptionState || null,
    subscriptionAccountToken:
      playState.externalAccountIdentifiers?.obfuscatedExternalAccountId ||
      userData.subscriptionAccountToken ||
      null,
  });
}

function createAppleSubscriptionUpdates({
  notification,
  transaction,
  renewalInfo,
  userData,
  accountToken,
}) {
  const now = new Date();
  const statusValue = notification.data?.status;
  const expiry = firstValidDate(
      transaction?.expiresDate,
      renewalInfo?.gracePeriodExpiresDate,
      renewalInfo?.renewalDate,
  );
  const autoRenewStatus = renewalInfo?.autoRenewStatus;
  const notificationType = String(notification.notificationType || "");

  const isEntitled = Boolean(
      expiry &&
      expiry > now &&
      statusValue !== Status.EXPIRED &&
      statusValue !== Status.REVOKED &&
      notificationType !== "EXPIRED" &&
      notificationType !== "REVOKE" &&
      notificationType !== "REFUND",
  );

  const willRenew = autoRenewStatus === AutoRenewStatus.ON;
  const mappedStatus = isEntitled ?
    willRenew ? "active" : "active_canceled" :
    "inactive";

  return withCommonSubscriptionFields(userData, {
    isSubscribed: isEntitled,
    subscriptionStatus: mappedStatus,
    subscriptionCanceled: !willRenew,
    subscriptionExpiresAt: expiry ?
      admin.firestore.Timestamp.fromDate(expiry) :
      null,
    subscriptionProductId:
      transaction?.productId ||
      renewalInfo?.productId ||
      renewalInfo?.autoRenewProductId ||
      userData.subscriptionProductId ||
      null,
    subscriptionPlatform: "app_store",
    subscriptionProviderState: notificationType || null,
    subscriptionAccountToken: accountToken,
    subscriptionOriginalTransactionId:
      transaction?.originalTransactionId ||
      renewalInfo?.originalTransactionId ||
      userData.subscriptionOriginalTransactionId ||
      null,
    subscriptionTransactionId:
      transaction?.transactionId ||
      userData.subscriptionTransactionId ||
      null,
  });
}

function createFallbackSubscriptionUpdates(userData) {
  const now = new Date();
  const expiry = resolveFirestoreExpiry(userData);
  const entitled = Boolean(expiry && expiry > now);
  const currentStatus = (userData.subscriptionStatus || "")
      .toString()
      .toLowerCase();
  const nextStatus = entitled && currentStatus === "active_canceled" ?
    "active_canceled" :
    entitled ? "active" : "inactive";

  return withCommonSubscriptionFields(userData, {
    isSubscribed: entitled,
    subscriptionStatus: nextStatus,
    subscriptionCanceled: entitled ? currentStatus === "active_canceled" : true,
    subscriptionExpiresAt: expiry ?
      admin.firestore.Timestamp.fromDate(expiry) :
      null,
  });
}

function withCommonSubscriptionFields(userData, nextValues) {
  const updates = {
    ...nextValues,
    subscriptionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (nextValues.isSubscribed === false &&
      typeof userData.subscriptionPurchaseToken === "string" &&
      userData.subscriptionPurchaseToken.trim()) {
    updates.subscriptionCanceled = true;
  }

  return updates;
}

function shouldApplySubscriptionUpdate(previous, nextValues) {
  return (
    previous.isSubscribed !== nextValues.isSubscribed ||
    normalizeString(previous.subscriptionStatus) !==
      normalizeString(nextValues.subscriptionStatus) ||
    Boolean(previous.subscriptionCanceled) !==
      Boolean(nextValues.subscriptionCanceled) ||
    normalizeString(previous.subscriptionProviderState) !==
      normalizeString(nextValues.subscriptionProviderState) ||
    normalizeString(previous.subscriptionProductId) !==
      normalizeString(nextValues.subscriptionProductId) ||
    normalizeString(previous.subscriptionPurchaseOrderId) !==
      normalizeString(nextValues.subscriptionPurchaseOrderId) ||
    normalizeString(previous.subscriptionAccountToken) !==
      normalizeString(nextValues.subscriptionAccountToken) ||
    normalizeString(previous.subscriptionOriginalTransactionId) !==
      normalizeString(nextValues.subscriptionOriginalTransactionId) ||
    normalizeString(previous.subscriptionTransactionId) !==
      normalizeString(nextValues.subscriptionTransactionId) ||
    !datesEqual(
        toDate(previous.subscriptionExpiresAt),
        toDate(nextValues.subscriptionExpiresAt),
    )
  );
}

async function applyUserSubscriptionUpdates(userRef, previousData, updates) {
  if (!shouldApplySubscriptionUpdate(previousData, updates)) {
    return false;
  }

  await userRef.set(updates, {merge: true});
  return true;
}

async function commitSubscriptionUpdates(db, updates) {
  if (updates.length === 0) {
    return;
  }

  for (let index = 0; index < updates.length; index += 450) {
    const chunk = updates.slice(index, index + 450);
    const batch = db.batch();
    for (const item of chunk) {
      batch.set(item.ref, item.data, {merge: true});
    }
    await batch.commit();
  }
}

async function findUserBySubscriptionAccountToken(accountToken) {
  if (!accountToken) return null;

  const snap = await admin.firestore()
      .collection("users")
      .where("subscriptionAccountToken", "==", accountToken)
      .limit(1)
      .get();
  return snap.docs[0] || null;
}

async function findUserByPurchaseToken(purchaseToken) {
  if (!purchaseToken) return null;

  const snap = await admin.firestore()
      .collection("users")
      .where("subscriptionPurchaseToken", "==", purchaseToken)
      .limit(1)
      .get();
  return snap.docs[0] || null;
}

async function storeNotificationAudit(provider, eventId, payload) {
  if (!eventId) return;

  await admin.firestore()
      .collection("subscriptionNotificationEvents")
      .doc(`${provider}_${eventId}`)
      .set({
        provider,
        payload,
        receivedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
}

function parsePubSubMessage(message) {
  const raw = message?.json || message?.data;
  if (!raw) return null;

  if (typeof raw === "object") {
    return raw;
  }

  const decoded = Buffer.from(String(raw), "base64").toString("utf8");
  return JSON.parse(decoded);
}

async function verifyAppleNotification(signedPayload) {
  const verifiers = buildAppleNotificationVerifiers();
  let lastError = null;

  for (const verifierInfo of verifiers) {
    try {
      const notification =
        await verifierInfo.verifier.verifyAndDecodeNotification(signedPayload);
      const transaction = notification.data?.signedTransactionInfo ?
        await verifierInfo.verifier.verifyAndDecodeTransaction(
            notification.data.signedTransactionInfo,
        ) :
        null;
      const renewalInfo = notification.data?.signedRenewalInfo ?
        await verifierInfo.verifier.verifyAndDecodeRenewalInfo(
            notification.data.signedRenewalInfo,
        ) :
        null;

      return {notification, transaction, renewalInfo};
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError || new Error("Unable to verify App Store notification");
}

function buildAppleNotificationVerifiers() {
  const rootCertificates = loadAppleRootCertificates();
  const appAppleId = process.env.APPLE_APPLE_ID ?
    Number(process.env.APPLE_APPLE_ID) :
    undefined;
  const verifiers = [
    new SignedDataVerifier(
        rootCertificates,
        true,
        Environment.SANDBOX,
        APPLE_BUNDLE_ID,
    ),
  ];

  if (Number.isFinite(appAppleId)) {
    verifiers.push(
        new SignedDataVerifier(
            rootCertificates,
            true,
            Environment.PRODUCTION,
            APPLE_BUNDLE_ID,
            appAppleId,
        ),
    );
  }

  return verifiers.map((verifier) => ({verifier}));
}

function loadAppleRootCertificates() {
  const certDir = path.join(__dirname, "certs", "apple");
  const fileNames = [
    "AppleRootCAG2.cer",
    "AppleRootCAG3.cer",
  ];

  return fileNames.map((fileName) => {
    const fullPath = path.join(certDir, fileName);
    return fs.readFileSync(fullPath);
  });
}

function toDate(value) {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === "number") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function firstValidDate(...values) {
  for (const value of values) {
    const parsed = toDate(value);
    if (parsed) {
      return parsed;
    }
  }
  return null;
}

function resolveFirestoreExpiry(data) {
  const directExpiry = toDate(data.subscriptionExpiresAt);
  if (directExpiry) {
    return directExpiry;
  }

  const subscriptionDate = toDate(data.subscriptionDate);
  if (!subscriptionDate) {
    return null;
  }

  return addDays(subscriptionDate, 30);
}

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function getLatestLineItem(lineItems) {
  if (!Array.isArray(lineItems) || lineItems.length === 0) {
    return null;
  }

  let latest = null;
  let latestExpiry = null;

  for (const item of lineItems) {
    const expiry = toDate(item?.expiryTime);
    if (!expiry) {
      continue;
    }

    if (!latestExpiry || expiry > latestExpiry) {
      latest = item;
      latestExpiry = expiry;
    }
  }

  return latest;
}

function getLatestExpiry(lineItems) {
  const latest = getLatestLineItem(lineItems);
  return latest ? toDate(latest.expiryTime) : null;
}

function hasEnabledAutoRenew(lineItems) {
  const latest = getLatestLineItem(lineItems);
  return latest?.autoRenewingPlan?.autoRenewEnabled === true;
}

function normalizeString(value) {
  return value == null ? "" : String(value);
}

function datesEqual(left, right) {
  if (!left && !right) return true;
  if (!left || !right) return false;
  return left.getTime() === right.getTime();
}

function defaultTitleForType(type) {
  switch (type) {
    case "work_request":
      return "New work request";
    case "quote_request":
      return "New quote request";
    case "request_accepted":
      return "Request accepted";
    case "request_declined":
      return "Request declined";
    case "quote_response":
      return "New quote response";
    case "chat_message":
    default:
      return "New message";
  }
}

function defaultBodyForType(type) {
  switch (type) {
    case "work_request":
      return "You received a new work request";
    case "quote_request":
      return "You received a new quote request";
    case "request_accepted":
      return "Your request was accepted";
    case "request_declined":
      return "Your request was declined";
    case "quote_response":
      return "You received a new quote response";
    case "chat_message":
    default:
      return "You received a new message";
  }
}

function dataTypeForNotification(type) {
  switch (type) {
    case "work_request":
    case "quote_request":
      return "job_request";
    case "request_accepted":
    case "request_declined":
    case "quote_response":
      return "request_update";
    case "chat_message":
    default:
      return "chat";
  }
}
