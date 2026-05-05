const fs = require("fs");
const path = require("path");

const admin = require("firebase-admin");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError, onRequest} = require("firebase-functions/v2/https");
const {onMessagePublished} = require("firebase-functions/v2/pubsub");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const {google} = require("googleapis");
const {
  AppStoreServerAPIClient,
  AutoRenewStatus,
  Environment,
  SignedDataVerifier,
  Status,
} = require("@apple/app-store-server-library");

admin.initializeApp();

const GOOGLE_PLAY_PACKAGE_NAME = "com.hirehub.app";
const APPLE_BUNDLE_ID = "com.hiro.hiroapp";
const GOOGLE_PLAY_RTDN_TOPIC = "play-subscription-notifications";
const PLAY_ANDROID_PUBLISHER_SCOPE =
  "https://www.googleapis.com/auth/androidpublisher";
const SUBSCRIPTION_NOTIFICATION_RETENTION_DAYS = 30;
const SUBSCRIPTION_VERIFICATION_RETENTION_HOURS = 36;
const DEVICE_TOKEN_RETENTION_DAYS = 90;
const APPLE_SUBSCRIPTION_PRODUCT_ID = "HIRO_SUBSCRIPTION";
const GOOGLE_PLAY_SUBSCRIPTION_PRODUCT_IDS = new Set([
  "pro_worker_monthly",
  "com-hiro-app-pro-worker-monthly",
]);

exports.sendNotificationPush = onDocumentCreated(
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

      await cleanupStaleDeviceTokens(userDoc.ref);
      const fcmTokens = await getUserFcmTokens(userDoc);
      if (fcmTokens.length === 0) {
        logger.info("No device tokens for user", {userId});
        return;
      }

      const senderId = payload.fromId || "";
      const senderName = payload.fromName || "User";
      const requestDate = payload.date || "";
      const requestStatus = payload.status || "";
      const title = payload.type === "chat_message" ?
        (normalizeString(payload.title) || senderName || "New message") :
        (payload.title || defaultTitleForType(payload.type));
      const body = payload.type === "chat_message" ?
        chatMessageBody(payload) :
        (payload.body || defaultBodyForType(payload.type));

      const message = {
        tokens: fcmTokens,
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
        const response = await admin.messaging().sendEachForMulticast(message);
        await cleanupInvalidFcmTokens(userDoc.ref, fcmTokens, response.responses);
        const failureCodes = summarizeMessagingFailures(response.responses);
        const failureSamples = summarizeTokenFailures(fcmTokens, response.responses);
        const logPayload = {
          userId,
          notificationId: snap.id,
          type: payload.type,
          successCount: response.successCount,
          failureCount: response.failureCount,
          failureCodes,
          failureSamples,
        };
        if (response.successCount > 0) {
          logger.info("Notification push sent", logPayload);
        } else {
          logger.error("Notification push failed for all tokens", logPayload);
        }
      } catch (error) {
        logger.error("Failed to send notification push", {
          userId,
          type: payload.type,
          error,
        });
      }
    },
);

async function getUserFcmTokens(userDoc) {
  const tokens = new Set();
  const tokenSnap = await userDoc.ref.collection("deviceTokens").limit(100).get();
  tokenSnap.forEach((doc) => {
    const token = doc.get("token");
    if (typeof token === "string" && token.trim()) {
      tokens.add(token.trim());
    }
  });

  return Array.from(tokens).slice(0, 500);
}

async function cleanupStaleDeviceTokens(userRef) {
  const cutoff = Date.now() - (DEVICE_TOKEN_RETENTION_DAYS * 24 * 60 * 60 * 1000);
  const snapshot = await userRef.collection("deviceTokens").limit(500).get();
  const staleDocs = snapshot.docs.filter((doc) => {
    const updatedAt = doc.get("updatedAt");
    if (!updatedAt?.toMillis) return true;
    return updatedAt.toMillis() < cutoff;
  });

  if (staleDocs.length === 0) {
    return;
  }

  await Promise.all(staleDocs.map((doc) => doc.ref.delete()));
  logger.info("Removed stale device tokens", {
    userId: userRef.id,
    removedCount: staleDocs.length,
    retentionDays: DEVICE_TOKEN_RETENTION_DAYS,
  });
}

async function cleanupInvalidFcmTokens(userRef, tokens, responses) {
  const invalidCodes = new Set([
    "messaging/registration-token-not-registered",
    "messaging/invalid-registration-token",
  ]);
  const deletes = [];

  responses.forEach((response, index) => {
    const code = response.error?.code;
    if (!code || !invalidCodes.has(code)) return;
    deletes.push(
        userRef
            .collection("deviceTokens")
            .where("token", "==", tokens[index])
            .limit(10)
            .get()
            .then((snapshot) => Promise.all(
                snapshot.docs.map((doc) => doc.ref.delete()),
            )),
    );
  });

  await Promise.all(deletes);
}

function summarizeMessagingFailures(responses) {
  return responses.reduce((summary, response) => {
    const code = response.error?.code;
    if (!code) return summary;
    summary[code] = (summary[code] || 0) + 1;
    return summary;
  }, {});
}

function summarizeTokenFailures(tokens, responses) {
  return responses
      .map((response, index) => {
        const code = response.error?.code;
        if (!code) return null;
        return {
          code,
          tokenSuffix: maskToken(tokens[index]),
        };
      })
      .filter(Boolean)
      .slice(0, 10);
}

function maskToken(token) {
  if (typeof token !== "string" || !token) {
    return "unknown";
  }
  return token.length <= 8 ? token : token.slice(-8);
}

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

exports.verifySubscriptionPurchase = onCall(
    {
      region: "us-central1",
    },
    async (request) => {
      const auth = request.auth;
      if (!auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      const payload = request.data || {};
      const userRef = admin.firestore().collection("users").doc(auth.uid);
      const userSnap = await userRef.get();
      const userData = userSnap.data() || {};

      const purchaseProof = normalizePurchaseProof(payload);
      if (!purchaseProof.productId) {
        throw new HttpsError("invalid-argument", "Missing productId.");
      }

      let updates;
      if (GOOGLE_PLAY_SUBSCRIPTION_PRODUCT_IDS.has(purchaseProof.productId)) {
        if (!purchaseProof.verificationToken) {
          throw new HttpsError(
              "invalid-argument",
              "Missing Google Play verification token.",
          );
        }

        const androidPublisher = await createAndroidPublisherClient();
        const playState = await fetchGooglePlaySubscription({
          androidPublisher,
          purchaseToken: purchaseProof.verificationToken,
        });
        if (!playState) {
          throw new HttpsError(
              "not-found",
              "Google Play subscription could not be verified.",
          );
        }

        await assertNoConflictingSubscriptionOwner({
          currentUid: auth.uid,
          subscriptionOwnershipKey:
            purchaseProof.ownershipKey || `google_play:${purchaseProof.verificationToken}`,
          purchaseToken: purchaseProof.verificationToken,
          accountToken:
            playState.externalAccountIdentifiers?.obfuscatedExternalAccountId ||
            purchaseProof.applicationAccountToken,
        });

        updates = createPlaySubscriptionUpdates(playState, userData);
      } else if (purchaseProof.productId === APPLE_SUBSCRIPTION_PRODUCT_ID) {
        let appStoreState = null;
        try {
          appStoreState = await fetchAppStoreSubscription({
            appStoreClients: buildAppStoreApiClients(),
            originalTransactionId:
              purchaseProof.originalTransactionId || purchaseProof.purchaseId,
          });
        } catch (error) {
          logger.warn("Direct App Store verification failed", {
            userId: auth.uid,
            productId: purchaseProof.productId,
            purchaseId: purchaseProof.purchaseId || null,
            originalTransactionId: purchaseProof.originalTransactionId || null,
            error: error.message || String(error),
          });
        }

        if (!appStoreState) {
          const fallbackUserData = await waitForVerifiedAppleEntitlement(
              userRef,
              userData,
          );
          if (fallbackUserData) {
            logger.info(
                "Using App Store notification-backed entitlement after direct verification miss",
                {
                  userId: auth.uid,
                  productId: purchaseProof.productId,
                  purchaseId: purchaseProof.purchaseId || null,
                },
            );
            return buildSubscriptionVerificationResponse(fallbackUserData);
          }

          throw new HttpsError(
              "not-found",
              "App Store subscription could not be verified.",
          );
        }

        const originalTransactionId =
          appStoreState.transaction?.originalTransactionId ||
          appStoreState.renewalInfo?.originalTransactionId ||
          purchaseProof.originalTransactionId ||
          purchaseProof.purchaseId;
        const ownershipKey =
          purchaseProof.ownershipKey ||
          (originalTransactionId ? `appstore:${originalTransactionId}` : null);

        await assertNoConflictingSubscriptionOwner({
          currentUid: auth.uid,
          subscriptionOwnershipKey: ownershipKey,
          originalTransactionId,
          accountToken:
            appStoreState.transaction?.appAccountToken ||
            appStoreState.renewalInfo?.appAccountToken ||
            purchaseProof.applicationAccountToken,
        });

        updates = createAppleApiSubscriptionUpdates(appStoreState, userData);
      } else {
        throw new HttpsError(
            "invalid-argument",
            `Unsupported subscription product: ${purchaseProof.productId}`,
        );
      }

      await applyUserSubscriptionUpdates(userRef, userData, updates);
      const refreshed = (await userRef.get()).data() || {};
      return buildSubscriptionVerificationResponse(refreshed);
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
      const appStoreClients = buildAppStoreApiClients();

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
              appStoreClients,
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

exports.cleanupSubscriptionNotificationEvents = onSchedule(
    {
      schedule: "every day 02:00",
      region: "us-central1",
      timeZone: "UTC",
    },
    async () => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();
      const pageSize = 300;
      let deleted = 0;

      while (true) {
        const snap = await db
            .collection("subscriptionNotificationEvents")
            .where("expiresAt", "<=", now)
            .limit(pageSize)
            .get();

        if (snap.empty) break;

        const batch = db.batch();
        for (const doc of snap.docs) {
          batch.delete(doc.ref);
        }

        await batch.commit();
        deleted += snap.size;

        if (snap.size < pageSize) break;
      }

      logger.info("Cleaned up expired subscription notification events", {
        deleted,
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

function normalizePurchaseProof(payload) {
  return {
    productId: normalizeString(payload.productId).trim(),
    purchaseId: normalizeString(payload.purchaseId).trim(),
    verificationToken: normalizeString(payload.verificationToken).trim(),
    verificationSource: normalizeString(payload.verificationSource).trim(),
    transactionDate: normalizeString(payload.transactionDate).trim(),
    applicationAccountToken:
      normalizeString(payload.applicationAccountToken).trim(),
    ownershipKey: normalizeString(payload.ownershipKey).trim(),
    originalTransactionId:
      normalizeString(payload.originalTransactionId).trim(),
    appAccountToken: normalizeString(payload.appAccountToken).trim(),
  };
}

function buildAppStoreApiClients() {
  const keyId = process.env.APPLE_SUBSCRIPTION_KEY_ID?.trim();
  const issuerId = process.env.APPLE_SUBSCRIPTION_ISSUER_ID?.trim();
  const privateKey = normalizeApplePrivateKey(
      process.env.APPLE_SUBSCRIPTION_PRIVATE_KEY,
  );

  if (!keyId || !issuerId || !privateKey) {
    return [];
  }

  return [
    {
      environment: Environment.PRODUCTION,
      client: new AppStoreServerAPIClient(
          privateKey,
          keyId,
          issuerId,
          APPLE_BUNDLE_ID,
          Environment.PRODUCTION,
      ),
    },
    {
      environment: Environment.SANDBOX,
      client: new AppStoreServerAPIClient(
          privateKey,
          keyId,
          issuerId,
          APPLE_BUNDLE_ID,
          Environment.SANDBOX,
      ),
    },
  ];
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

async function assertNoConflictingSubscriptionOwner({
  currentUid,
  subscriptionOwnershipKey,
  purchaseToken,
  originalTransactionId,
  accountToken,
}) {
  const lookups = [
    ["subscriptionOwnershipKey", subscriptionOwnershipKey],
    ["subscriptionPurchaseToken", purchaseToken],
    ["subscriptionOriginalTransactionId", originalTransactionId],
    ["subscriptionAccountToken", accountToken],
  ];
  const seen = new Set();

  for (const [field, rawValue] of lookups) {
    const value = normalizeString(rawValue).trim();
    if (!value) continue;

    const signature = `${field}:${value}`;
    if (seen.has(signature)) continue;
    seen.add(signature);

    const snap = await admin.firestore()
        .collection("users")
        .where(field, "==", value)
        .limit(1)
        .get();
    if (!snap.empty && snap.docs[0].id !== currentUid) {
      throw new HttpsError(
          "already-exists",
          "This subscription is already linked to another account.",
      );
    }
  }
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

async function buildSubscriptionUpdate({
  androidPublisher,
  appStoreClients,
  userData,
}) {
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

  const originalTransactionId =
    userData.subscriptionOriginalTransactionId?.trim();
  if (originalTransactionId) {
    const appleState = await fetchAppStoreSubscription({
      appStoreClients,
      originalTransactionId,
    });

    if (appleState) {
      return {
        source: "app_store",
        updates: createAppleApiSubscriptionUpdates(appleState, userData),
      };
    }
  }

  return {
    source: "firestore",
    updates: createFallbackSubscriptionUpdates(userData),
  };
}

async function fetchAppStoreSubscription({
  appStoreClients,
  originalTransactionId,
}) {
  if (!Array.isArray(appStoreClients) || appStoreClients.length === 0) {
    return null;
  }

  let lastError = null;
  for (const clientInfo of appStoreClients) {
    try {
      const response = await clientInfo.client.getAllSubscriptionStatuses(
          originalTransactionId,
      );
      const lastTransactions = (response.data || [])
          .flatMap((group) => group.lastTransactions || []);
      if (lastTransactions.length === 0) {
        return null;
      }

      const decodedItems = [];
      for (const item of lastTransactions) {
        const decoded = await decodeAppleStatusItem(item);
        if (decoded) {
          decodedItems.push(decoded);
        }
      }

      if (decodedItems.length === 0) {
        return null;
      }

      decodedItems.sort((left, right) => {
        const leftExpiry = firstValidDate(
            left.transaction?.expiresDate,
            left.renewalInfo?.gracePeriodExpiresDate,
            left.renewalInfo?.renewalDate,
        ) || new Date(0);
        const rightExpiry = firstValidDate(
            right.transaction?.expiresDate,
            right.renewalInfo?.gracePeriodExpiresDate,
            right.renewalInfo?.renewalDate,
        ) || new Date(0);
        return rightExpiry - leftExpiry;
      });

      return {
        environment: clientInfo.environment,
        ...decodedItems[0],
      };
    } catch (error) {
      lastError = error;
    }
  }

  if (lastError) {
    throw lastError;
  }

  return null;
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
    subscriptionSource: "google_play",
    subscriptionProviderState: playState.subscriptionState || null,
    subscriptionAccountToken:
      playState.externalAccountIdentifiers?.obfuscatedExternalAccountId ||
      userData.subscriptionAccountToken ||
      null,
    subscriptionOwnershipKey:
      playState.externalAccountIdentifiers?.obfuscatedExternalAccountId ?
        `google_play:${playState.externalAccountIdentifiers.obfuscatedExternalAccountId}` :
        userData.subscriptionOwnershipKey || null,
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
    subscriptionSource: "app_store",
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

function createAppleApiSubscriptionUpdates(appleState, userData) {
  const now = new Date();
  const transaction = appleState.transaction;
  const renewalInfo = appleState.renewalInfo;
  const statusValue = appleState.status;
  const expiry = firstValidDate(
      transaction?.expiresDate,
      renewalInfo?.gracePeriodExpiresDate,
      renewalInfo?.renewalDate,
  );
  const autoRenewStatus = renewalInfo?.autoRenewStatus;

  const isEntitled = Boolean(
      expiry &&
      expiry > now &&
      statusValue !== Status.EXPIRED &&
      statusValue !== Status.REVOKED,
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
    subscriptionSource: "app_store",
    subscriptionProviderState: String(statusValue || "") || null,
    subscriptionAccountToken:
      transaction?.appAccountToken ||
      renewalInfo?.appAccountToken ||
      userData.subscriptionAccountToken ||
      null,
    subscriptionOwnershipKey:
      transaction?.originalTransactionId ?
        `appstore:${transaction.originalTransactionId}` :
        renewalInfo?.originalTransactionId ?
          `appstore:${renewalInfo.originalTransactionId}` :
          userData.subscriptionOwnershipKey || null,
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
    subscriptionSource: userData.subscriptionSource || null,
  });
}

function withCommonSubscriptionFields(userData, nextValues) {
  const updates = {
    ...nextValues,
    subscriptionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    subscriptionVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    subscriptionVerificationFreshUntil: admin.firestore.Timestamp.fromDate(
        addHours(new Date(), SUBSCRIPTION_VERIFICATION_RETENTION_HOURS),
    ),
  };

  if (nextValues.isSubscribed === false &&
      typeof userData.subscriptionPurchaseToken === "string" &&
      userData.subscriptionPurchaseToken.trim()) {
    updates.subscriptionCanceled = true;
  }

  return updates;
}

function buildSubscriptionVerificationResponse(userData) {
  return {
    isSubscribed: userData.isSubscribed === true,
    subscriptionStatus: normalizeString(userData.subscriptionStatus) || "inactive",
    subscriptionProductId: userData.subscriptionProductId || null,
    subscriptionPlatform: userData.subscriptionPlatform || null,
    subscriptionPurchaseId:
      userData.subscriptionPurchaseId ||
      userData.subscriptionTransactionId ||
      null,
    subscriptionPurchaseToken: userData.subscriptionPurchaseToken || null,
    subscriptionTransactionDate:
      normalizeString(userData.subscriptionTransactionDate) || null,
    subscriptionAccountToken: userData.subscriptionAccountToken || null,
    subscriptionOwnershipKey: userData.subscriptionOwnershipKey || null,
    subscriptionOriginalTransactionId:
      userData.subscriptionOriginalTransactionId || null,
    subscriptionDate: toIsoString(userData.subscriptionDate),
    subscriptionExpiresAt: toIsoString(userData.subscriptionExpiresAt),
  };
}

async function waitForVerifiedAppleEntitlement(userRef, initialUserData) {
  const firstSnapshot = await userRef.get();
  let candidate = firstSnapshot.data() || initialUserData || {};
  if (hasVerifiedActiveAppleEntitlement(candidate)) {
    return candidate;
  }

  for (let attempt = 0; attempt < 4; attempt += 1) {
    await sleep(1500);
    const snap = await userRef.get();
    candidate = snap.data() || {};
    if (hasVerifiedActiveAppleEntitlement(candidate)) {
      return candidate;
    }
  }

  return null;
}

function hasVerifiedActiveAppleEntitlement(userData) {
  if (!userData || userData.isSubscribed !== true) {
    return false;
  }

  const source = normalizeString(userData.subscriptionSource).toLowerCase();
  const platform = normalizeString(userData.subscriptionPlatform).toLowerCase();
  const productId = normalizeString(userData.subscriptionProductId);
  const status = normalizeString(userData.subscriptionStatus).toLowerCase();

  const verifiedAt = toDate(userData.subscriptionVerifiedAt);
  const freshUntil = toDate(userData.subscriptionVerificationFreshUntil);
  const now = new Date();
  const recentlyVerified = Boolean(
      (freshUntil && freshUntil > now) ||
      (verifiedAt && now.getTime() - verifiedAt.getTime() < 10 * 60 * 1000),
  );

  return (
    recentlyVerified &&
    (status === "active" || status === "active_canceled") &&
    productId === APPLE_SUBSCRIPTION_PRODUCT_ID &&
    (source === "app_store" || platform === "app_store")
  );
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
    normalizeString(previous.subscriptionSource) !==
      normalizeString(nextValues.subscriptionSource) ||
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

  const now = new Date();
  const expiresAt = new Date(now);
  expiresAt.setUTCDate(expiresAt.getUTCDate() + SUBSCRIPTION_NOTIFICATION_RETENTION_DAYS);

  await admin.firestore()
      .collection("subscriptionNotificationEvents")
      .doc(`${provider}_${eventId}`)
      .set({
        provider,
        payload,
        receivedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
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

async function decodeAppleStatusItem(item) {
  if (!item) return null;

  const verifiers = buildAppleNotificationVerifiers();
  let lastError = null;
  for (const verifierInfo of verifiers) {
    try {
      const transaction = item.signedTransactionInfo ?
        await verifierInfo.verifier.verifyAndDecodeTransaction(
            item.signedTransactionInfo,
        ) :
        null;
      const renewalInfo = item.signedRenewalInfo ?
        await verifierInfo.verifier.verifyAndDecodeRenewalInfo(
            item.signedRenewalInfo,
        ) :
        null;
      return {
        status: item.status,
        transaction,
        renewalInfo,
      };
    } catch (error) {
      lastError = error;
    }
  }

  if (lastError) {
    throw lastError;
  }

  return null;
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

function toIsoString(value) {
  const date = toDate(value);
  return date ? date.toISOString() : null;
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

function addHours(date, hours) {
  return new Date(date.getTime() + hours * 60 * 60 * 1000);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function normalizeApplePrivateKey(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  return raw.replace(/\\n/g, "\n");
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

function chatMessageBody(payload) {
  const genericBodies = new Set([
    "you have a new notification",
    "you received a new notification",
    "new notification",
    "you received a new message",
    "sent you a message",
  ]);
  const candidates = [
    payload.message,
    payload.text,
    payload.body,
    payload.lastMessage,
  ];

  for (const candidate of candidates) {
    const body = normalizeString(candidate).trim();
    if (!body || genericBodies.has(body.toLowerCase())) continue;
    return body;
  }

  return "Sent you a message";
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
