const admin = require("firebase-admin");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");

admin.initializeApp();

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

    // Only send push for chat notifications.
    if (payload.type !== "chat_message") {
      return;
    }

    const userDoc = await admin.firestore().collection("users").doc(userId).get();
    if (!userDoc.exists) {
      logger.warn("Target user doc not found", { userId });
      return;
    }

    const fcmToken = userDoc.get("fcmToken");
    if (!fcmToken || typeof fcmToken !== "string") {
      logger.info("No FCM token for user", { userId });
      return;
    }

    const title = payload.title || "New message";
    const body = payload.body || "You received a new message";
    const senderId = payload.fromId || "";
    const senderName = payload.fromName || "User";

    const message = {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: {
        type: "chat",
        senderId: String(senderId),
        senderName: String(senderName),
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
      logger.info("Chat push sent", { userId, notificationId: snap.id });
    } catch (error) {
      logger.error("Failed to send chat push", { userId, error });
    }
  }
);

exports.syncWorkerSubscriptionLifecycle = onSchedule(
  {
    schedule: "every 1 hours",
    region: "us-central1",
    timeZone: "UTC",
  },
  async () => {
    const db = admin.firestore();
    const now = new Date();
    const pageSize = 300;

    let lastDoc = null;
    let scanned = 0;
    let deactivated = 0;

    while (true) {
      let query = db
        .collection("users")
        .where("role", "==", "worker")
        .where("isSubscribed", "==", true)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(pageSize);

      if (lastDoc) {
        query = query.startAfter(lastDoc.id);
      }

      const snap = await query.get();
      if (snap.empty) break;

      const batch = db.batch();

      for (const doc of snap.docs) {
        scanned += 1;

        const data = doc.data() || {};
        const isSubscribed = data.isSubscribed === true;
        if (!isSubscribed) continue;

        const subscriptionDate = toDate(data.subscriptionDate);
        let expiry = toDate(data.subscriptionExpiresAt);
        if (!expiry && subscriptionDate) {
          expiry = addDays(subscriptionDate, 30);
        }

        if (!expiry || now < expiry) {
          continue;
        }

        batch.update(doc.ref, {
          isSubscribed: false,
          subscriptionStatus: "inactive",
          subscriptionCanceled: true,
          subscriptionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        deactivated += 1;
      }

      await batch.commit();
      lastDoc = snap.docs[snap.docs.length - 1];

      if (snap.size < pageSize) {
        break;
      }
    }

    logger.info("Worker subscription lifecycle sync completed", {
      scanned,
      deactivated,
    });
  }
);

function toDate(value) {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}
