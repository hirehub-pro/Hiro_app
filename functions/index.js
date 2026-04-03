const admin = require("firebase-admin");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
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
