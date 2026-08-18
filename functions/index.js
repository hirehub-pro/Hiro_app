const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const fontkit = require("@pdf-lib/fontkit");
const {PDFDocument, rgb} = require("pdf-lib");

const admin = require("firebase-admin");
const {
  onDocumentCreated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError, onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {onMessagePublished} = require("firebase-functions/v2/pubsub");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const {google} = require("googleapis");
const {Resend} = require("resend");
const {
  buildFailedInvoiceEmailUpdate,
  buildInvoiceEmailDeliveries,
  buildSentInvoiceEmailUpdate,
  isTerminalInvoiceEmailStatus,
  sendInvoiceEmailDeliveries,
} = require("./email_saved_invoice");
const {ownedInvoicePdfPath} = require("./document_security");
const {
  taxAuthorityFailureState,
  taxInvoiceDraftSignature,
  taxInvoicePayloadHash,
  validTaxInvoiceDraftSignature,
  validateTaxInvoiceAllocation,
} = require("./tax_invoice_security");
const {
  AppStoreServerAPIClient,
  AutoRenewStatus,
  Environment,
  SignedDataVerifier,
  Status,
} = require("@apple/app-store-server-library");

admin.initializeApp();

const TAX_AUTH_CLIENT_ID = defineSecret("TAX_AUTH_CLIENT_ID");
const TAX_AUTH_CLIENT_SECRET = defineSecret("TAX_AUTH_CLIENT_SECRET");
const RESEND_API_KEY = defineSecret("RESEND_API_KEY");
const RESEND_FROM_EMAIL = defineSecret("RESEND_FROM_EMAIL");

const GOOGLE_PLAY_PACKAGE_NAME = "com.hirehub.app";
const APPLE_BUNDLE_ID = "com.hiro.hiroapp";
const GOOGLE_PLAY_RTDN_TOPIC = "play-subscription-notifications";
const PLAY_ANDROID_PUBLISHER_SCOPE =
  "https://www.googleapis.com/auth/androidpublisher";
const SUBSCRIPTION_NOTIFICATION_RETENTION_DAYS = 30;
const SUBSCRIPTION_VERIFICATION_RETENTION_HOURS = 36;
const DEVICE_TOKEN_RETENTION_DAYS = 90;
const TAX_AUTH_OAUTH_CODE_RETENTION_HOURS = 2;
const TAX_AUTH_SANDBOX_AUTH_URL =
  "https://openapi.taxes.gov.il/shaam/tsandbox/longtimetoken/oauth2/authorize";
const TAX_AUTH_SANDBOX_TOKEN_URL =
  "https://openapi.taxes.gov.il/shaam/tsandbox/longtimetoken/oauth2/token";
const TAX_AUTH_SANDBOX_TOKEN_FALLBACK_URL =
  "https://ita-api.taxes.gov.il/shaam/tsandbox/longtimetoken/oauth2/token";
const TAX_AUTH_SANDBOX_MULTI_APPROVAL_URL =
  "https://openapi.taxes.gov.il/shaam/tsandbox/Multi-invoices/v2/MultiApproval";
const TAX_AUTH_SANDBOX_ACCOUNTING_SOFTWARE_NUMBER = 987654321;
const TAX_AUTH_REDIRECT_URI =
  "https://me-west1-hire-hub-fe6c4.cloudfunctions.net/taxesOAuthCallback";
const TAX_AUTH_APP_RETURN_URI = "hiro://tax-authority-connected";
const TAX_AUTH_SCOPE = "scope";
const APPLE_SUBSCRIPTION_PRODUCT_ID = "HIRO_SUBSCRIPTION";
const GOOGLE_PLAY_SUBSCRIPTION_PRODUCT_IDS = new Set([
  "pro_worker_monthly",
  "com-hiro-app-pro-worker-monthly",
]);
const PUBLIC_APP_ORIGIN = "https://hiro-services.com";
const SIGNING_REQUEST_LIFETIME_DAYS = 30;
const SIGNING_FONT_PATH = path.join(
    __dirname,
    "assets",
    "fonts",
    "Rubik-VariableFont_wght.ttf",
);
const EMAIL_APP_ICON_STORAGE_PATH = "email-assets/app_icon-Photoroom.png";
const EMAIL_APP_STORE_BADGE_STORAGE_PATH =
  "email-assets/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg";
const EMAIL_GOOGLE_PLAY_BADGE_STORAGE_PATH =
  "email-assets/Google_Play_Store_badge_EN.svg.png";

const REQUEST_EXPIRY_TIME_ZONE = "Asia/Jerusalem";
const INVOICE_BUILDER_EMAIL_CODE_TTL_MS = 10 * 60 * 1000;
const INVOICE_BUILDER_EMAIL_CODE_RESEND_DELAY_MS = 60 * 1000;
const INVOICE_BUILDER_EMAIL_CODE_MAX_ATTEMPTS = 5;

function assertOwnedInvoicePdfPath(storagePath, userId) {
  const path = ownedInvoicePdfPath(storagePath, userId);
  if (!path) {
    throw new HttpsError(
        "permission-denied",
        "The document file does not belong to the authenticated user.",
    );
  }
  return path;
}

function invoiceBuilderEmailCodeHash(code) {
  return crypto.createHash("sha256").update(code).digest("hex");
}

function isPendingRequestExpired(request, now = new Date()) {
  const status = normalizeString(request.status).trim().toLowerCase();
  if (status !== "pending" && status !== "waiting_for_approval") return false;

  const date = normalizeString(request.date).trim();
  const time = normalizeString(
      request.requestedTo || request.requestedFrom,
  ).trim();
  if (!/^\d{4}-\d{1,2}-\d{1,2}$/.test(date) ||
      !/^\d{1,2}:\d{2}$/.test(time)) {
    return false;
  }

  const [year, month, day] = date.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  if (month < 1 || month > 12 || day < 1 || day > 31 ||
      hour > 23 || minute > 59) {
    return false;
  }

  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: REQUEST_EXPIRY_TIME_ZONE,
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
    hourCycle: "h23",
  }).formatToParts(now).reduce((values, part) => {
    if (part.type !== "literal") values[part.type] = Number(part.value);
    return values;
  }, {});
  const deadline = [year, month, day, hour, minute];
  const current = [
    parts.year,
    parts.month,
    parts.day,
    parts.hour,
    parts.minute,
  ];
  for (let index = 0; index < deadline.length; index += 1) {
    if (deadline[index] !== current[index]) {
      return deadline[index] < current[index];
    }
  }
  return false;
}

exports.expireUnansweredRequests = onSchedule(
    {schedule: "every 15 minutes", timeZone: REQUEST_EXPIRY_TIME_ZONE},
    async () => {
      const db = admin.firestore();
      const now = new Date();
      let expiredCount = 0;

      for (const collectionId of [
        "requests",
        "notifications",
        "RequestToMe",
      ]) {
        const snapshot = await db.collectionGroup(collectionId)
            .where("status", "in", ["pending", "waiting_for_approval"])
            .get();
        const expiredDocs = snapshot.docs.filter(
            (doc) => isPendingRequestExpired(doc.data(), now),
        );
        for (let index = 0; index < expiredDocs.length; index += 450) {
          const batch = db.batch();
          for (const doc of expiredDocs.slice(index, index + 450)) {
            batch.update(doc.ref, {
              status: "expired",
              expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
          expiredCount += Math.min(450, expiredDocs.length - index);
        }
      }
      logger.info("Expired unanswered requests", {expiredCount});
    },
);

exports.createDocumentSigningRequest = onCall(
    {region: "us-central1"},
    async (request) => {
      const workerId = request.auth?.uid;
      if (!workerId) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      const invoiceDocId =
        normalizeString(request.data?.invoiceDocId).trim();
      const receiverId = normalizeString(request.data?.receiverId).trim();
      if (!invoiceDocId) {
        throw new HttpsError(
            "invalid-argument",
            "A saved document ID is required.",
        );
      }

      const db = admin.firestore();
      const invoiceRef = db
          .collection("users")
          .doc(workerId)
          .collection("invoices")
          .doc(invoiceDocId);
      const invoiceSnap = await invoiceRef.get();
      if (!invoiceSnap.exists) {
        throw new HttpsError("not-found", "Saved document not found.");
      }

      const invoice = invoiceSnap.data() || {};
      const docType = normalizeString(invoice.docType || invoice.type);
      const rawStoragePath = normalizeString(invoice.storagePath).trim();
      if (!["quote", "work_order"].includes(docType) || !rawStoragePath) {
        throw new HttpsError(
            "failed-precondition",
            "Only saved quotes and work orders can be sent for signature.",
        );
      }
      const storagePath = assertOwnedInvoicePdfPath(
          rawStoragePath,
          workerId,
      );

      if (receiverId) {
        const roomId = [workerId, receiverId].sort().join("_");
        const roomSnap = await db.collection("chat_rooms").doc(roomId).get();
        const users = roomSnap.data()?.users;
        if (!roomSnap.exists ||
            !Array.isArray(users) ||
            !users.includes(workerId) ||
            !users.includes(receiverId)) {
          throw new HttpsError(
              "permission-denied",
              "The selected Hiro conversation was not found.",
          );
        }
      }

      const token = crypto.randomBytes(32).toString("base64url");
      const requestId = hashSigningToken(token);
      const now = new Date();
      const expiresAt = new Date(
          now.getTime() +
          SIGNING_REQUEST_LIFETIME_DAYS * 24 * 60 * 60 * 1000,
      );
      await db.collection("documentSigningRequests").doc(requestId).set({
        workerId,
        invoiceDocId,
        receiverId: receiverId || null,
        docType,
        documentName: normalizeString(invoice.name || invoice.fileName),
        documentNumber: normalizeString(invoice.invoiceNumber),
        documentDate: normalizeString(invoice.date),
        amount: Number(invoice.amount) || 0,
        fileName: normalizeString(invoice.fileName) || "document.pdf",
        storagePath,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
        signedAt: null,
      });

      await invoiceRef.set({
        signatureStatus: "pending",
        signingRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      return {
        url: `${PUBLIC_APP_ORIGIN}/sign/${token}`,
        expiresAt: expiresAt.toISOString(),
      };
    },
);

exports.publicDocumentSigning = onRequest(
    {region: "us-central1", cors: false, timeoutSeconds: 60},
    async (req, res) => {
      try {
        const token = signingTokenFromRequest(req);
        if (!token) {
          res.status(404).send(renderSigningMessage(
              "הקישור אינו תקין",
              "לא נמצא מסמך לחתימה.",
          ));
          return;
        }

        const requestRef = admin.firestore()
            .collection("documentSigningRequests")
            .doc(hashSigningToken(token));
        const requestSnap = await requestRef.get();
        if (!requestSnap.exists) {
          res.status(404).send(renderSigningMessage(
              "הקישור אינו תקין",
              "לא נמצא מסמך לחתימה.",
          ));
          return;
        }

        const signingRequest = requestSnap.data() || {};
        const expiresAt = toDate(signingRequest.expiresAt);
        if (!expiresAt || expiresAt.getTime() < Date.now()) {
          res.status(410).send(renderSigningMessage(
              "תוקף הקישור פג",
              "יש לבקש מבעל המקצוע קישור חדש.",
          ));
          return;
        }

        if (req.method === "GET" && req.query.pdf === "1") {
          await streamSigningPdf(res, signingRequest);
          return;
        }

        if (req.method === "GET") {
          res.set("Cache-Control", "no-store");
          res.status(200).send(renderSigningPage(token, signingRequest));
          return;
        }

        if (req.method !== "POST") {
          res.status(405).send("Method Not Allowed");
          return;
        }

        if (signingRequest.status === "signed") {
          res.status(409).json({error: "המסמך כבר נחתם."});
          return;
        }

        const signatureData = normalizeString(req.body?.signature).trim();
        const signerName = normalizeString(req.body?.signerName)
            .trim()
            .slice(0, 100);
        if (!signerName || !signatureData.startsWith("data:image/png;base64,")) {
          res.status(400).json({error: "יש להזין שם ולצייר חתימה."});
          return;
        }
        const signatureBytes = Buffer.from(
            signatureData.substring("data:image/png;base64,".length),
            "base64",
        );
        if (signatureBytes.length === 0 || signatureBytes.length > 1500000) {
          res.status(400).json({error: "החתימה אינה תקינה."});
          return;
        }

        const signedResult = await signAndReplacePdf(
            signingRequest,
            signatureBytes,
            signerName,
        );
        const signedAt = admin.firestore.Timestamp.now();
        const db = admin.firestore();
        const invoiceRef = db
            .collection("users")
            .doc(signingRequest.workerId)
            .collection("invoices")
            .doc(signingRequest.invoiceDocId);
        const batch = db.batch();
        batch.set(requestRef, {
          status: "signed",
          signerName,
          signedAt,
          signedUrl: signedResult.url,
        }, {merge: true});
        batch.set(invoiceRef, {
          url: signedResult.url,
          signatureStatus: "signed",
          signerName,
          signedAt,
        }, {merge: true});
        await batch.commit();

        await publishSignedDocument(signingRequest, {
          signerName,
          signedUrl: signedResult.url,
          signedAt,
        });

        res.status(200).json({
          ok: true,
          message: "המסמך נחתם ונשלח לבעל המקצוע.",
          shareUrl: `${PUBLIC_APP_ORIGIN}/sign/${token}`,
        });
      } catch (error) {
        logger.error("Public document signing failed", {error});
        res.status(500).json({error: "לא ניתן היה לחתום על המסמך."});
      }
    },
);

exports.createTaxAuthorityAuthorizationUrl = onCall(
    {
      region: "me-west1",
      secrets: [TAX_AUTH_CLIENT_ID],
    },
    async (request) => {
      const userId = request.auth?.uid;
      if (!userId) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      const businessId = await getVerifiedTaxAuthorityBusinessId(userId);
      const state = crypto.randomUUID();
      const now = admin.firestore.Timestamp.now();
      const expiresAt = admin.firestore.Timestamp.fromDate(
          addHours(now.toDate(), TAX_AUTH_OAUTH_CODE_RETENTION_HOURS),
      );
      await admin.firestore()
          .collection("taxAuthorityOAuthStates")
          .doc(state)
          .set({
            userId,
            businessId,
            createdAt: now,
            expiresAt,
            usedAt: null,
          });

      const authorizationUrl = new URL(TAX_AUTH_SANDBOX_AUTH_URL);
      authorizationUrl.searchParams.set("response_type", "code");
      authorizationUrl.searchParams.set(
          "client_id",
          TAX_AUTH_CLIENT_ID.value(),
      );
      authorizationUrl.searchParams.set("redirect_uri", TAX_AUTH_REDIRECT_URI);
      authorizationUrl.searchParams.set("scope", TAX_AUTH_SCOPE);
      authorizationUrl.searchParams.set("state", state);

      return {authorizationUrl: authorizationUrl.toString()};
    },
);

exports.taxesOAuthStart = onRequest(
    {region: "me-west1"},
    (_req, res) => {
      res.status(410).send(renderOAuthCallbackPage({
        title: "App update required",
        message:
          "Open the latest version of Hiro to connect your Tax Authority account.",
      }));
    },
);

exports.taxesOAuthCallback = onRequest(
    {
      region: "me-west1",
      secrets: [TAX_AUTH_CLIENT_ID, TAX_AUTH_CLIENT_SECRET],
    },
    async (req, res) => {
      if (req.method !== "GET") {
        res.status(405).send("Method Not Allowed");
        return;
      }

      const code = normalizeString(req.query.code).trim();
      const state = normalizeString(req.query.state).trim();
      const error = normalizeString(req.query.error).trim();
      const errorDescription =
        normalizeString(req.query.error_description).trim();

      if (error) {
        logger.warn("Tax Authority OAuth callback returned an error", {
          error,
          errorDescription,
          state: maskOAuthState(state),
        });
        res.status(400).send(renderOAuthCallbackPage({
          title: "Authorization was not completed",
          message: errorDescription || error,
        }));
        return;
      }

      if (!code) {
        res.status(400).send(renderOAuthCallbackPage({
          title: "Missing authorization code",
          message: "The Tax Authority did not return an OAuth code.",
        }));
        return;
      }

      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();
      const expiresAt = admin.firestore.Timestamp.fromDate(
          addHours(now.toDate(), TAX_AUTH_OAUTH_CODE_RETENTION_HOURS),
      );
      if (!state) {
        res.status(400).send(renderOAuthCallbackPage({
          title: "Missing authorization state",
          message: "Please start the Tax Authority connection again.",
        }));
        return;
      }

      const stateRef = db.collection("taxAuthorityOAuthStates").doc(state);
      const oauthOwner = await db.runTransaction(async (transaction) => {
        const stateSnap = await transaction.get(stateRef);
        if (!stateSnap.exists) return null;

        const stateData = stateSnap.data() || {};
        const stateUserId = normalizeString(stateData.userId).trim();
        const stateBusinessId = normalizeBusinessId(stateData.businessId);
        const stateExpiresAt = toDate(stateData.expiresAt);
        if (!stateUserId ||
            !stateBusinessId ||
            stateData.usedAt ||
            !stateExpiresAt ||
            stateExpiresAt < new Date()) {
          return null;
        }

        transaction.update(stateRef, {usedAt: now});
        return {
          userId: stateUserId,
          businessId: stateBusinessId,
        };
      });
      if (!oauthOwner) {
        res.status(400).send(renderOAuthCallbackPage({
          title: "Invalid authorization state",
          message: "Please start the Tax Authority connection again.",
        }));
        return;
      }
      const {userId, businessId} = oauthOwner;

      let currentBusinessId;
      try {
        currentBusinessId = await getVerifiedTaxAuthorityBusinessId(userId);
      } catch (error) {
        res.status(400).send(renderOAuthCallbackPage({
          title: "Business verification changed",
          message:
            "Your verified business details changed during authorization. " +
            "Return to Hiro and start the connection again.",
        }));
        return;
      }
      if (currentBusinessId !== businessId) {
        res.status(400).send(renderOAuthCallbackPage({
          title: "Business verification changed",
          message:
            "Your verified business ID changed during authorization. " +
            "Return to Hiro and start the connection again.",
        }));
        return;
      }

      let tokenResponse;
      try {
        tokenResponse = await exchangeTaxAuthorityCodeForTokens(code);
      } catch (error) {
        logger.error("Tax Authority OAuth token exchange crashed", {
          message: normalizeString(error.message),
          cause: normalizeString(error.cause?.message),
          code: normalizeString(error.cause?.code || error.code),
        });
        res.status(502).send(renderOAuthCallbackPage({
          title: "Authorization could not be completed",
          message:
            "Hiro received the authorization code, but could not exchange it " +
            "for a Tax Authority token. Please try connecting again in a few " +
            "minutes.",
        }));
        return;
      }

      // The OAuth identity can belong to an authorized representative and is
      // not necessarily the business VAT number. The single-use OAuth state
      // binds this token to the verified Hiro business; the allocation request
      // below always sends that VAT number, and the Tax Authority enforces
      // whether this token may act for it.

      const docRef = await db
          .collection("taxAuthorityOAuthCallbacks")
          .add({
            userId,
            businessId,
            code,
            state,
            createdAt: now,
            expiresAt,
            consumedAt: null,
            userAgent: normalizeString(req.get("user-agent")).slice(0, 500),
            ip: normalizeString(req.ip).slice(0, 80),
          });

      const tokenRecord = {
        ...tokenResponse,
        connected: true,
        userId,
        businessId,
        callbackId: docRef.id,
        updatedAt: now,
        environment: "sandbox",
        disconnectedAt: admin.firestore.FieldValue.delete(),
        disconnectReason: admin.firestore.FieldValue.delete(),
        expiresAt: tokenResponse.expires_in ?
          admin.firestore.Timestamp.fromDate(
              addSeconds(new Date(), Number(tokenResponse.expires_in)),
          ) :
          null,
      };
      const tokenRefs = taxAuthorityTokenRefs(userId);
      const tokenBatch = db.batch();
      tokenBatch.set(tokenRefs.userOAuthRef, tokenRecord, {merge: true});
      tokenBatch.set(tokenRefs.secureTokenRef, tokenRecord, {merge: true});
      await tokenBatch.commit();
      await docRef.update({consumedAt: admin.firestore.Timestamp.now()});

      logger.info("Stored Tax Authority OAuth callback code", {
        userId,
        callbackId: docRef.id,
        state: maskOAuthState(state),
      });

      res.status(200).send(renderOAuthCallbackPage({
        title: "Authorization received",
        message: "You can return to Hiro. The authorization code was received.",
      }));
    },
);

exports.createTaxInvoiceDraft = onCall(
    {
      region: "me-west1",
      secrets: [TAX_AUTH_CLIENT_ID, TAX_AUTH_CLIENT_SECRET],
    },
    async (request) => {
      const auth = request.auth;
      if (!auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      const payload = normalizeTaxInvoiceAllocationPayload(request.data || {});
      const businessId = await getVerifiedTaxAuthorityBusinessId(auth.uid);
      const payloadBusinessId = normalizeBusinessId(payload.vat_number);
      if (payloadBusinessId !== businessId) {
        throw new HttpsError(
            "permission-denied",
            "The invoice VAT ID does not match your verified business ID.",
        );
      }
      payload.vat_number = Number(businessId);
      payload.invoices_list[0].vat_number = Number(businessId);
      payload.invoices_list[0].accounting_software_number =
        TAX_AUTH_SANDBOX_ACCOUNTING_SOFTWARE_NUMBER;

      const invoiceDocId = normalizeString(request.data?.invoiceDocId).trim();
      let reservation;
      try {
        reservation = validateTaxInvoiceAllocation({
          payload,
          invoiceDocId,
          currentYear: Number(new Intl.DateTimeFormat("en", {
            year: "numeric",
            timeZone: REQUEST_EXPIRY_TIME_ZONE,
          }).format(new Date())),
        });
      } catch (error) {
        throw new HttpsError("invalid-argument", error.message);
      }

      const db = admin.firestore();
      const userRef = db.collection("users").doc(auth.uid);
      const invoiceRef = userRef.collection("invoices").doc(invoiceDocId);
      const counterRef = userRef.collection("counters")
          .doc(`document_counter_${reservation.docType}`);
      const payloadHash = taxInvoicePayloadHash(payload);
      const serverSignature = taxInvoiceDraftSignature({
        secret: TAX_AUTH_CLIENT_SECRET.value(),
        userId: auth.uid,
        reservation,
        payloadHash,
      });
      // Verify the OAuth connection before consuming an official document
      // number. The allocation callable will verify it again before use.
      await getTaxAuthorityTokenData(auth.uid, businessId);
      const now = admin.firestore.Timestamp.now();

      const claim = await db.runTransaction(async (transaction) => {
        const [counterSnap, invoiceSnap] = await Promise.all([
          transaction.get(counterRef),
          transaction.get(invoiceRef),
        ]);
        const existing = invoiceSnap.data() || {};
        const existingRequest = existing.taxAuthorityAllocationRequest || {};
        if (existingRequest.payloadHash) {
          if (existingRequest.payloadHash !== payloadHash) {
            throw new HttpsError(
                "already-exists",
                "This document number is already reserved for different invoice data.",
            );
          }
          if (existingRequest.serverSignature !== serverSignature) {
            throw new HttpsError(
                "failed-precondition",
                "The stored Tax Authority draft failed integrity verification.",
            );
          }
          return {
            status: normalizeString(existing.documentStatus).trim(),
            allocation: existing.taxAuthorityAllocation || null,
          };
        }

        if (invoiceSnap.exists) {
          throw new HttpsError(
              "already-exists",
              "This document number has already been saved.",
          );
        }
        const storedNextNumber = Number(counterSnap.data()?.value);
        if (!Number.isSafeInteger(storedNextNumber) || storedNextNumber < 1) {
          throw new HttpsError(
              "failed-precondition",
              "Set the starting document number before requesting an allocation.",
          );
        }
        if (storedNextNumber !== reservation.sequenceNumber) {
          throw new HttpsError(
              "failed-precondition",
              "The document number changed. Refresh the invoice and try again.",
          );
        }

        transaction.set(counterRef, {
          value: reservation.sequenceNumber + 1,
          docType: reservation.docType,
          updatedAt: now,
        }, {merge: true});
        transaction.create(invoiceRef, {
          type: reservation.docType,
          docType: reservation.docType,
          invoiceDocId,
          invoiceNumber: reservation.documentNumber,
          sequenceNumber: reservation.sequenceNumber,
          documentStatus: "reserved",
          authoritativeTaxInvoice: payload,
          taxAuthorityAllocationRequest: {
            payloadHash,
            serverSignature,
            status: "reserved",
            attempts: 0,
            reservedAt: now,
            environment: "sandbox",
          },
          createdAt: now,
        });
        return {status: "reserved", allocation: null};
      });

      return {
        draftId: invoiceDocId,
        reservation,
        payloadHash,
        status: claim.status,
        allocation: claim.allocation,
      };
    },
);

exports.initializeDocumentCounter = onCall(
    {region: "me-west1"},
    async (request) => {
      const userId = request.auth?.uid;
      if (!userId) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }
      const docType = requiredString(request.data?.docType, "docType");
      const allowedDocTypes = new Set([
        "invoice",
        "invoice_receipt",
        "receipt",
        "credit_note",
        "transaction_account",
      ]);
      if (!allowedDocTypes.has(docType)) {
        throw new HttpsError("invalid-argument", "Unsupported document type.");
      }
      const startNumber = requiredInt(
          request.data?.startNumber,
          "startNumber",
      );
      if (startNumber < 1 || startNumber > 999999999) {
        throw new HttpsError(
            "invalid-argument",
            "The starting document number is outside the allowed range.",
        );
      }
      const counterId = docType === "transaction_account" ?
        "document_counter_transaction_account" :
        `document_counter_${docType}`;
      const counterRef = admin.firestore().collection("users").doc(userId)
          .collection("counters").doc(counterId);
      const value = await admin.firestore().runTransaction(
          async (transaction) => {
            const snap = await transaction.get(counterRef);
            const existingValue = Number(snap.data()?.value);
            if (snap.exists && Number.isSafeInteger(existingValue) &&
                existingValue > 0) {
              return existingValue;
            }
            transaction.create(counterRef, {
              value: startNumber,
              docType,
              initializedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return startNumber;
          },
      );
      return {value, docType, alreadyInitialized: value !== startNumber};
    },
);

exports.requestTaxInvoiceAllocation = onCall(
    {
      region: "me-west1",
      secrets: [TAX_AUTH_CLIENT_ID, TAX_AUTH_CLIENT_SECRET],
    },
    async (request) => {
      const auth = request.auth;
      if (!auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }
      const draftId = requiredString(request.data?.draftId, "draftId");
      if (draftId.includes("/") || draftId.length > 180) {
        throw new HttpsError("invalid-argument", "Invalid Tax Authority draft ID.");
      }

      const db = admin.firestore();
      const invoiceRef = db.collection("users").doc(auth.uid)
          .collection("invoices").doc(draftId);
      const businessId = await getVerifiedTaxAuthorityBusinessId(auth.uid);
      const tokenData = await getTaxAuthorityTokenData(auth.uid, businessId);
      const now = admin.firestore.Timestamp.now();

      const claim = await db.runTransaction(async (transaction) => {
        const invoiceSnap = await transaction.get(invoiceRef);
        if (!invoiceSnap.exists) {
          throw new HttpsError("not-found", "Tax Authority draft not found.");
        }
        const draft = invoiceSnap.data() || {};
        const payload = draft.authoritativeTaxInvoice;
        const allocationRequest = draft.taxAuthorityAllocationRequest || {};
        const reservation = {
          docType: draft.docType,
          documentNumber: draft.invoiceNumber,
          sequenceNumber: draft.sequenceNumber,
          invoiceDocId: draftId,
        };
        if (!payload || !allocationRequest.payloadHash ||
            taxInvoicePayloadHash(payload) !== allocationRequest.payloadHash ||
            !validTaxInvoiceDraftSignature({
              secret: TAX_AUTH_CLIENT_SECRET.value(),
              userId: auth.uid,
              reservation,
              payloadHash: allocationRequest.payloadHash,
            }, allocationRequest.serverSignature)) {
          throw new HttpsError(
              "failed-precondition",
              "The authoritative Tax Authority draft is invalid.",
          );
        }
        if (normalizeBusinessId(payload.vat_number) !== businessId) {
          throw new HttpsError(
              "permission-denied",
              "The draft VAT ID does not match your verified business ID.",
          );
        }
        if (["allocation_approved", "finalized"].includes(
          normalizeString(draft.documentStatus).trim(),
        ) && draft.taxAuthorityAllocation?.approved === true) {
          return {
            cached: true,
            payload,
            payloadHash: allocationRequest.payloadHash,
            allocation: draft.taxAuthorityAllocation,
            reservation,
          };
        }
        if (allocationRequest.status === "allocating") {
          throw new HttpsError(
              "aborted",
              "An allocation request for this document is already in progress.",
          );
        }
        if (!["reserved", "failed"].includes(allocationRequest.status)) {
          throw new HttpsError(
              "failed-precondition",
              "This draft cannot request an allocation in its current state.",
          );
        }
        transaction.update(invoiceRef, {
          documentStatus: "allocating",
          "taxAuthorityAllocationRequest.status": "allocating",
          "taxAuthorityAllocationRequest.lastAttemptAt": now,
          "taxAuthorityAllocationRequest.attempts":
            admin.firestore.FieldValue.increment(1),
        });
        return {
          cached: false,
          payload,
          payloadHash: allocationRequest.payloadHash,
          allocation: null,
          reservation,
        };
      });

      if (claim.cached) {
        return {
          ...claim.allocation,
          reservation: claim.reservation,
          payloadHash: claim.payloadHash,
          cached: true,
        };
      }

      try {
        const response = await callTaxAuthorityMultiApproval({
          accessToken: tokenData.accessToken,
          payload: claim.payload,
        });
        const approval = extractTaxAuthorityApproval(response, claim.payload);
        if (approval.approved !== true || !approval.confirmationNumber) {
          throw new HttpsError(
              "failed-precondition",
              "The Tax Authority did not approve an allocation number.",
              {definitive: true, errors: approval.errors},
          );
        }
        const storedAllocation = {
          ...approval,
          rawResponse: response,
          requestedAt: admin.firestore.Timestamp.now(),
          environment: "sandbox",
        };
        await invoiceRef.update({
          documentStatus: "allocation_approved",
          taxAuthorityAllocation: storedAllocation,
          "taxAuthorityAllocationRequest.status": "approved",
          "taxAuthorityAllocationRequest.completedAt":
            admin.firestore.Timestamp.now(),
        });

        return {
          ...approval,
          response,
          reservation: claim.reservation,
          payloadHash: claim.payloadHash,
          cached: false,
        };
      } catch (error) {
        const failureState = taxAuthorityFailureState(error);
        await invoiceRef.update({
          documentStatus: failureState === "failed" ?
            "allocation_failed" : "needs_reconciliation",
          "taxAuthorityAllocationRequest.status": failureState,
          "taxAuthorityAllocationRequest.failedAt":
            admin.firestore.Timestamp.now(),
          "taxAuthorityAllocationRequest.lastError":
            normalizeString(error?.message).slice(0, 500),
        });
        throw error;
      }
    },
);

exports.finalizeTaxInvoiceDocument = onCall(
    {
      region: "me-west1",
      secrets: [TAX_AUTH_CLIENT_SECRET],
    },
    async (request) => {
      const userId = request.auth?.uid;
      if (!userId) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }
      const draftId = requiredString(request.data?.draftId, "draftId");
      if (draftId.includes("/") || draftId.length > 180) {
        throw new HttpsError("invalid-argument", "Invalid Tax Authority draft ID.");
      }
      const storagePath = assertOwnedInvoicePdfPath(
          request.data?.storagePath,
          userId,
      );
      const bucket = admin.storage().bucket();
      let metadata;
      try {
        [metadata] = await bucket.file(storagePath).getMetadata();
      } catch (error) {
        throw new HttpsError(
            "failed-precondition",
            "The final invoice PDF has not been uploaded.",
        );
      }
      const size = Number(metadata.size);
      if (metadata.contentType !== "application/pdf" ||
          !Number.isFinite(size) || size < 1 || size > 25 * 1024 * 1024) {
        throw new HttpsError(
            "invalid-argument",
            "The final document must be a PDF no larger than 25 MB.",
        );
      }

      const invoiceRef = admin.firestore().collection("users").doc(userId)
          .collection("invoices").doc(draftId);
      const result = await admin.firestore().runTransaction(
          async (transaction) => {
            const snap = await transaction.get(invoiceRef);
            if (!snap.exists) {
              throw new HttpsError("not-found", "Tax Authority draft not found.");
            }
            const invoice = snap.data() || {};
            const allocationRequest =
              invoice.taxAuthorityAllocationRequest || {};
            const reservation = {
              docType: invoice.docType,
              documentNumber: invoice.invoiceNumber,
              sequenceNumber: invoice.sequenceNumber,
              invoiceDocId: draftId,
            };
            if (!invoice.authoritativeTaxInvoice ||
                taxInvoicePayloadHash(invoice.authoritativeTaxInvoice) !==
                  allocationRequest.payloadHash ||
                !validTaxInvoiceDraftSignature({
                  secret: TAX_AUTH_CLIENT_SECRET.value(),
                  userId,
                  reservation,
                  payloadHash: allocationRequest.payloadHash,
                }, allocationRequest.serverSignature)) {
              throw new HttpsError(
                  "failed-precondition",
                  "The Tax Authority draft failed integrity verification.",
              );
            }
            if (invoice.documentStatus === "finalized") {
              if (invoice.storagePath !== storagePath) {
                throw new HttpsError(
                    "already-exists",
                    "This invoice was finalized with a different PDF.",
                );
              }
              return {alreadyFinalized: true};
            }
            if (invoice.documentStatus !== "allocation_approved" ||
                invoice.taxAuthorityAllocation?.approved !== true ||
                !invoice.taxAuthorityAllocation?.confirmationNumber) {
              throw new HttpsError(
                  "failed-precondition",
                  "The invoice must have an approved allocation before finalization.",
              );
            }
            transaction.update(invoiceRef, {
              documentStatus: "finalized",
              storagePath,
              fileName: path.posix.basename(storagePath),
              finalizedAt: admin.firestore.FieldValue.serverTimestamp(),
              finalPdf: {
                storagePath,
                size,
                contentType: metadata.contentType,
                generation: normalizeString(metadata.generation),
              },
            });
            return {alreadyFinalized: false};
          },
      );
      return {finalized: true, draftId, storagePath, ...result};
    },
);

exports.getTaxAuthorityConnectionStatus = onCall(
    {
      region: "me-west1",
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      let businessId;
      try {
        businessId = await getVerifiedTaxAuthorityBusinessId(request.auth.uid);
      } catch (error) {
        return {
          connected: false,
          environment: "sandbox",
          expiresAt: null,
          reason: "business-verification-required",
        };
      }

      const tokenDocuments = await loadTaxAuthorityTokenDocuments(
          request.auth.uid,
      );
      const tokenSnap = tokenDocuments.activeSnap;
      const data = tokenSnap.data() || {};
      const hasAccessToken =
        normalizeString(data.access_token).trim().length > 0;
      const tokenBusinessId = normalizeBusinessId(data.businessId);
      const expiresAtDate = toDate(data.expiresAt);
      const expiresAt = expiresAtDate?.toISOString() || null;
      const expiryMissing = !expiresAtDate;
      const expired = expiresAtDate != null &&
        expiresAtDate.getTime() <= Date.now();
      const businessIdMismatch =
        tokenSnap.exists && tokenBusinessId !== businessId;
      const connected =
        tokenSnap.exists &&
        !businessIdMismatch &&
        hasAccessToken &&
        !expiryMissing &&
        !expired;
      const connectionFlagNeedsUpdate =
        (tokenDocuments.userOAuthSnap.exists &&
          tokenDocuments.userOAuthSnap.data()?.connected !== false) ||
        (tokenDocuments.secureTokenSnap.exists &&
          tokenDocuments.secureTokenSnap.data()?.connected !== false);

      if (tokenSnap.exists && !connected && connectionFlagNeedsUpdate) {
        const disconnectedUpdate = {
          connected: false,
          disconnectedAt: admin.firestore.FieldValue.serverTimestamp(),
          disconnectReason: expired ?
            "token-expired" :
            expiryMissing ?
              "token-expiry-missing" :
              businessIdMismatch ?
                "business-id-mismatch" :
                "access-token-missing",
        };
        const batch = admin.firestore().batch();
        if (tokenDocuments.userOAuthSnap.exists) {
          batch.set(
              tokenDocuments.userOAuthRef,
              disconnectedUpdate,
              {merge: true},
          );
        }
        if (tokenDocuments.secureTokenSnap.exists) {
          batch.set(
              tokenDocuments.secureTokenRef,
              disconnectedUpdate,
              {merge: true},
          );
        }
        await batch.commit();
      }

      return {
        connected,
        environment: "sandbox",
        expiresAt,
        reason: !tokenSnap.exists ?
          "not-connected" :
          expired ?
            "token-expired" :
            expiryMissing ?
              "token-expiry-missing" :
              businessIdMismatch ?
                "business-id-mismatch" :
                !hasAccessToken ?
                  "access-token-missing" :
                  null,
      };
    },
);

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
        "document_signed",
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

exports.syncReceivedInvoices = onCall(
    {
      region: "us-central1",
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      const db = admin.firestore();
      const userDoc = await db.collection("users").doc(uid).get();
      const userData = userDoc.data() || {};
      const phoneValues = [
        request.auth?.token?.phone_number,
        userData.phone,
        userData.phoneNumber,
      ];
      const candidates = [...new Set(
          phoneValues.flatMap((phone) => phoneCandidates(phone)),
      )];

      if (candidates.length === 0) {
        return {synced: 0};
      }

      const mirrorIds = new Set();
      const writer = new BatchWriter(db);

      for (const chunk of chunkArray(candidates, 30)) {
        const snapshot = await db.collectionGroup("invoices")
            .where("clientPhone", "in", chunk)
            .get();

        for (const doc of snapshot.docs) {
          const senderUserRef = doc.ref.parent.parent;
          if (!senderUserRef || senderUserRef.id === uid) continue;

          const mirrorId = `${senderUserRef.id}_${doc.id}`;
          mirrorIds.add(mirrorId);
          const data = doc.data() || {};
          if (data.taxAuthorityAllocationRequest &&
              data.documentStatus !== "finalized") {
            continue;
          }
          writer.set(db.collection("users")
              .doc(uid)
              .collection("receivedInvoices")
              .doc(mirrorId), {
            ...data,
            sourceUserId: senderUserRef.id,
            sourceInvoiceId: doc.id,
            invoiceDocId: data.invoiceDocId || doc.id,
            mirroredAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      }

      const existingMirrors = await db.collection("users")
          .doc(uid)
          .collection("receivedInvoices")
          .limit(500)
          .get();
      for (const doc of existingMirrors.docs) {
        if (!mirrorIds.has(doc.id)) {
          writer.delete(doc.ref);
        }
      }

      await writer.commit();
      return {synced: mirrorIds.size};
    },
);

exports.mirrorReceivedInvoice = onDocumentWritten(
    {
      document: "users/{senderUserId}/invoices/{invoiceId}",
      region: "us-central1",
    },
    async (event) => {
      const beforeData = event.data?.before?.data() || null;
      const afterData = event.data?.after?.data() || null;
      const senderUserId = event.params.senderUserId;
      const invoiceId = event.params.invoiceId;

      const visibleBeforeData = beforeData?.taxAuthorityAllocationRequest &&
        beforeData.documentStatus !== "finalized" ? null : beforeData;
      const visibleAfterData = afterData?.taxAuthorityAllocationRequest &&
        afterData.documentStatus !== "finalized" ? null : afterData;
      const beforeRecipients = visibleBeforeData ?
        await findInvoiceRecipientUserIds(
            visibleBeforeData.clientPhone,
            senderUserId,
        ) :
        [];
      const afterRecipients = visibleAfterData ?
        await findInvoiceRecipientUserIds(
            visibleAfterData.clientPhone,
            senderUserId,
        ) :
        [];

      const db = admin.firestore();
      const mirrorId = `${senderUserId}_${invoiceId}`;
      const beforeSet = new Set(beforeRecipients);
      const afterSet = new Set(afterRecipients);
      const batch = db.batch();
      let writeCount = 0;

      for (const recipientId of beforeSet) {
        if (afterSet.has(recipientId)) continue;
        batch.delete(db.collection("users")
            .doc(recipientId)
            .collection("receivedInvoices")
            .doc(mirrorId));
        writeCount += 1;
      }

      if (visibleAfterData) {
        const mirrorData = {
          ...visibleAfterData,
          sourceUserId: senderUserId,
          sourceInvoiceId: invoiceId,
          invoiceDocId: afterData.invoiceDocId || invoiceId,
          mirroredAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        for (const recipientId of afterSet) {
          batch.set(db.collection("users")
              .doc(recipientId)
              .collection("receivedInvoices")
              .doc(mirrorId), mirrorData, {merge: true});
          writeCount += 1;
        }
      }

      if (writeCount > 0) {
        await batch.commit();
      }
    },
);

// Sends an invoice only after its PDF has been uploaded and its Storage path
// has been written to Firestore. The delivery state acts as a lease so retries
// and later document updates do not create duplicate emails.
exports.sendInvoiceBuilderEmailCode = onCall(
    {
      region: "me-west1",
      secrets: [RESEND_API_KEY, RESEND_FROM_EMAIL],
    },
    async (request) => {
      const userId = request.auth?.uid;
      if (!userId) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      const authUser = await admin.auth().getUser(userId);
      const email = normalizeEmail(authUser.email);
      if (!email || !authUser.emailVerified) {
        throw new HttpsError(
            "failed-precondition",
            "A verified email address is required for this verification.",
        );
      }

      const db = admin.firestore();
      const verificationRef = db.collection("users").doc(userId)
          .collection("invoiceBuilderVerifications").doc("emailCode");
      const now = Date.now();
      const code = crypto.randomInt(0, 1000000).toString().padStart(6, "0");
      const requestId = crypto.randomUUID();
      const expiresAt = new Date(now + INVOICE_BUILDER_EMAIL_CODE_TTL_MS);

      await db.runTransaction(async (transaction) => {
        const current = await transaction.get(verificationRef);
        const lastSentAt = current.data()?.sentAt?.toDate?.();
        if (lastSentAt &&
            now - lastSentAt.getTime() <
              INVOICE_BUILDER_EMAIL_CODE_RESEND_DELAY_MS) {
          throw new HttpsError(
              "resource-exhausted",
              "Please wait one minute before requesting another code.",
          );
        }
        transaction.set(verificationRef, {
          codeHash: invoiceBuilderEmailCodeHash(code),
          requestId,
          attempts: 0,
          sentAt: admin.firestore.Timestamp.fromMillis(now),
          expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
        });
      });

      try {
        const {data, error} = await new Resend(RESEND_API_KEY.value())
            .emails.send({
              from: RESEND_FROM_EMAIL.value(),
              to: [email],
              subject: "קוד אימות ליוצר החשבוניות של הירו",
              text: `קוד האימות שלך בהירו הוא: ${code}\n\n` +
                "הקוד תקף ל-10 דקות. אם לא ביקשת את הקוד, אפשר להתעלם מהודעה זו.",
              html: "<div dir=\"rtl\" style=\"font-family:Arial,sans-serif;" +
                "color:#1f2937;line-height:1.6\">" +
                "<p>קוד האימות שלך בהירו הוא:</p>" +
                `<p dir="ltr" style="font-size:28px;font-weight:700;letter-spacing:4px">${code}</p>` +
                "<p>הקוד תקף ל-10 דקות. אם לא ביקשת את הקוד, אפשר להתעלם מהודעה זו.</p>" +
                "</div>",
            }, {idempotencyKey: `invoice-builder-email-code/${userId}/${requestId}`});
        if (error) {
          throw new Error(error.message || "Resend rejected the email.");
        }
        return {sent: true, expiresAt: expiresAt.toISOString(), emailId: data?.id || null};
      } catch (error) {
        await verificationRef.delete().catch(() => undefined);
        logger.error("Could not send invoice builder email code", {
          userId,
          error: error instanceof Error ? error.message : String(error),
        });
        throw new HttpsError("internal", "Unable to send the verification email.");
      }
    },
);

exports.verifyInvoiceBuilderEmailCode = onCall(
    {region: "me-west1"},
    async (request) => {
      const userId = request.auth?.uid;
      const code = normalizeString(request.data?.code).trim();
      if (!userId) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }
      if (!/^\d{6}$/.test(code)) {
        throw new HttpsError("invalid-argument", "Enter the six-digit code.");
      }

      const db = admin.firestore();
      const verificationRef = db.collection("users").doc(userId)
          .collection("invoiceBuilderVerifications").doc("emailCode");
      const result = await db.runTransaction(async (transaction) => {
        const verification = await transaction.get(verificationRef);
        const data = verification.data();
        const expiresAt = data?.expiresAt?.toDate?.();
        if (!verification.exists || !expiresAt || expiresAt.getTime() <= Date.now()) {
          transaction.delete(verificationRef);
          return "expired";
        }
        if ((Number(data.attempts) || 0) >= INVOICE_BUILDER_EMAIL_CODE_MAX_ATTEMPTS) {
          transaction.delete(verificationRef);
          return "locked";
        }

        const expected = Buffer.from(data.codeHash || "", "hex");
        const actual = Buffer.from(invoiceBuilderEmailCodeHash(code), "hex");
        const matches = expected.length === actual.length &&
          crypto.timingSafeEqual(expected, actual);
        if (!matches) {
          transaction.update(verificationRef, {
            attempts: admin.firestore.FieldValue.increment(1),
          });
          return "incorrect";
        }
        transaction.delete(verificationRef);
        return "verified";
      });
      if (result === "expired") {
        throw new HttpsError("deadline-exceeded", "This code has expired. Request a new one.");
      }
      if (result === "locked") {
        throw new HttpsError("permission-denied", "Too many incorrect attempts. Request a new code.");
      }
      if (result !== "verified") {
        throw new HttpsError("permission-denied", "That code is incorrect.");
      }
      return {verified: true};
    },
);

exports.emailSavedInvoice = onDocumentWritten(
    {
      document: "users/{userId}/invoices/{invoiceId}",
      region: "us-central1",
      secrets: [RESEND_API_KEY, RESEND_FROM_EMAIL],
    },
    async (event) => {
      const invoice = event.data?.after?.data();
      if (!invoice) return;
      if (invoice.taxAuthorityAllocationRequest &&
          invoice.documentStatus !== "finalized") {
        return;
      }

      const rawStoragePath = normalizeString(invoice.storagePath).trim();
      if (!rawStoragePath) return;

      const db = admin.firestore();
      const invoiceRef = event.data.after.ref;
      const userId = event.params.userId;
      const storagePath = ownedInvoicePdfPath(rawStoragePath, userId);
      if (!storagePath) {
        if (normalizeString(invoice.invoiceEmailStatus).trim() !== "failed") {
          await invoiceRef.update({
            invoiceEmailStatus: "failed",
            invoiceEmailError: "Invalid document storage path.",
          });
        }
        logger.warn("Rejected invoice email with an invalid storage path", {
          userId,
          invoiceId: event.params.invoiceId,
        });
        return;
      }
      const claimed = await db.runTransaction(async (transaction) => {
        const latest = await transaction.get(invoiceRef);
        const status = normalizeString(
            latest.data()?.invoiceEmailStatus,
        ).trim();
        if (isTerminalInvoiceEmailStatus(status)) {
          return false;
        }
        transaction.update(invoiceRef, {
          invoiceEmailStatus: "sending",
          invoiceEmailAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (!claimed) return;

      try {
        const userSnap = await db.collection("users").doc(userId).get();
        const verificationSnap = await userSnap.ref
            .collection("verification_info").doc("latest").get();
        let ownerEmail = normalizeEmail(userSnap.get("email"));
        let userName = normalizeString(userSnap.get("name")).trim();
        if (!ownerEmail || !userName) {
          const authUser = await admin.auth().getUser(userId);
          ownerEmail = ownerEmail || normalizeEmail(authUser.email);
          userName = userName || normalizeString(authUser.displayName).trim();
        }
        userName = userName || "משתמש יקר";
        const clientEmail = normalizeEmail(invoice.clientEmail);
        const businessName = normalizeString(
            verificationSnap.get("businessName") ||
            userSnap.get("businessName") ||
            userSnap.get("name"),
        ).trim() || "הירו";
        const clientName =
          normalizeString(invoice.clientName).trim() || "לקוח";
        const deliveries = buildInvoiceEmailDeliveries({
          ownerEmail,
          clientEmail,
          clientName,
          businessName,
        });
        if (deliveries.length === 0) {
          await invoiceRef.update({
            invoiceEmailStatus: "skipped",
            invoiceEmailError: "No valid recipient email address.",
          });
          return;
        }

        const bucket = admin.storage().bucket();
        const fileName = normalizeString(invoice.fileName).trim() || "invoice.pdf";
        const pdfFile = bucket.file(storagePath);
        await pdfFile.setMetadata({
          contentDisposition: `attachment; filename="${downloadFileName(fileName)}"`,
        });
        const [pdfBytes] = await pdfFile.download();
        const [[appIconBytes], [appStoreBadgeBytes], [googlePlayBadgeBytes]] =
          await Promise.all([
            bucket.file(EMAIL_APP_ICON_STORAGE_PATH).download(),
            bucket.file(EMAIL_APP_STORE_BADGE_STORAGE_PATH).download(),
            bucket.file(EMAIL_GOOGLE_PLAY_BADGE_STORAGE_PATH).download(),
          ]);
        const downloadUrl = normalizeString(invoice.url).trim();
        const resend = new Resend(RESEND_API_KEY.value());
        const emailIds = await sendInvoiceEmailDeliveries(
            deliveries,
            async (delivery) => {
              const emailText = delivery.type === "client" ?
                buildClientInvoiceEmailText(invoice, clientName, businessName) :
                clientEmail ?
                  buildOwnerInvoiceEmailText(
                      invoice, userName, clientName, clientEmail,
                  ) :
                  buildOwnerInvoiceWithoutClientEmailText(invoice, userName);
              const emailHtml = delivery.type === "client" ?
                buildClientInvoiceEmailHtml(
                    invoice, clientName, businessName, downloadUrl, fileName,
                ) :
                clientEmail ?
                  buildOwnerInvoiceEmailHtml(
                      invoice, userName, clientName, clientEmail,
                      downloadUrl, fileName,
                  ) :
                  buildOwnerInvoiceWithoutClientEmailHtml(
                      invoice, userName, downloadUrl, fileName,
                  );
              const {data, error} = await resend.emails.send({
                from: RESEND_FROM_EMAIL.value(),
                to: [delivery.email],
                subject: buildInvoiceEmailSubject(
                    invoice, delivery.subjectName, delivery.subjectPreposition,
                ),
                text: emailText,
                html: emailHtml,
                attachments: [
                  {filename: fileName, content: pdfBytes},
                  {
                    filename: "hiro-app-icon.png",
                    content: appIconBytes,
                    contentId: "hiro-app-icon",
                  },
                  {
                    filename: "app-store-badge.svg",
                    content: appStoreBadgeBytes,
                    contentId: "app-store-badge",
                  },
                  {
                    filename: "google-play-badge.png",
                    content: googlePlayBadgeBytes,
                    contentId: "google-play-badge",
                  },
                ],
              }, {
                idempotencyKey:
                  `invoice-email/${userId}/${event.params.invoiceId}/${delivery.type}`,
              });
              if (error) {
                throw new Error(error.message || "Resend rejected the email.");
              }
              return data?.id || null;
            },
        );

        await invoiceRef.update(buildSentInvoiceEmailUpdate(
            emailIds,
            admin.firestore.FieldValue.serverTimestamp(),
            admin.firestore.FieldValue.delete(),
        ));
        logger.info("Invoice email sent", {
          invoiceId: event.params.invoiceId,
          recipientCount: deliveries.length,
        });
      } catch (error) {
        logger.error("Could not send saved invoice email", {
          invoiceId: event.params.invoiceId,
          error: error instanceof Error ? error.message : String(error),
        });
        await invoiceRef.update(buildFailedInvoiceEmailUpdate(error));
      }
    },
);

// Receives short-lived BKMV export files uploaded by the signed-in worker and
// sends them through Resend. The files are removed after a successful send.
exports.sendUniformFilesEmail = onCall(
    {
      region: "us-central1",
      secrets: [RESEND_API_KEY, RESEND_FROM_EMAIL],
    },
    async (request) => {
      const userId = request.auth?.uid;
      if (!userId) {
        throw new HttpsError("unauthenticated", "Authentication required.");
      }

      const recipientEmail = normalizeEmail(request.data?.recipientEmail);
      const filePaths = request.data?.filePaths;
      if (!recipientEmail || !Array.isArray(filePaths) ||
          filePaths.length === 0 || filePaths.length > 3) {
        throw new HttpsError(
            "invalid-argument",
            "A recipient email and one to three export files are required.",
        );
      }

      const allowedPrefix = `users/${userId}/uniform_exports/`;
      const paths = filePaths.map((value) => normalizeString(value).trim());
      if (paths.some((value) => !value.startsWith(allowedPrefix))) {
        throw new HttpsError(
            "permission-denied",
            "Export files must belong to the signed-in user.",
        );
      }

      const bucket = admin.storage().bucket();
      const files = paths.map((filePath) => bucket.file(filePath));
      const metadata = await Promise.all(files.map(async (file) => {
        const [exists] = await file.exists();
        if (!exists) {
          throw new HttpsError("not-found", "An export file was not found.");
        }
        const [fileMetadata] = await file.getMetadata();
        return fileMetadata;
      }));
      const totalSize = metadata.reduce(
          (total, item) => total + (Number(item.size) || 0), 0,
      );
      // Resend's 40 MB attachment limit is measured after Base64 encoding.
      if (totalSize > 28 * 1024 * 1024) {
        throw new HttpsError(
            "resource-exhausted",
            "The generated files are too large to send by email.",
        );
      }

      const contents = await Promise.all(files.map(async (file) => {
        const [content] = await file.download();
        return content;
      }));
      const attachments = contents.map((content, index) => ({
        filename: paths[index].split("/").pop() || `uniform-export-${index + 1}`,
        content,
      }));
      const {data, error} = await new Resend(RESEND_API_KEY.value())
          .emails.send({
            from: RESEND_FROM_EMAIL.value(),
            to: [recipientEmail],
            subject: "קבצים במבנה אחיד מהירו",
            text: "שלום,\n\nמצורפים קבצי המבנה האחיד שהופקו באמצעות הירו.\n\nבברכה,\nצוות הירו",
            attachments,
          });
      if (error) {
        throw new HttpsError(
            "internal", error.message || "Resend rejected the email.",
        );
      }

      await Promise.all(files.map(async (file) => {
        await file.delete().catch((error) => {
          logger.warn("Unable to delete emailed uniform export", {
            path: file.name,
            error: error.message,
          });
        });
      }));
      return {sent: true, emailId: data?.id || null};
    },
);

// Emails the short-lived Hashavshevet MOVEIN and HESHIN files uploaded by the
// authenticated worker. The Firebase ID token uses a dedicated header because
// some Cloud Run clients interpret an Authorization bearer as a Google IAM
// token before it reaches the Firebase Functions runtime.
exports.sendAccountingExportEmailHttp = onRequest(
    {
      region: "us-central1",
      secrets: [RESEND_API_KEY, RESEND_FROM_EMAIL],
      invoker: "public",
    },
    async (request, response) => {
      try {
        if (request.method !== "POST") {
          response.status(405).json({error: "POST is required."});
          return;
        }

        const firebaseToken = normalizeString(
            request.get("X-Firebase-Auth"),
        ).trim();
        if (!firebaseToken) {
          response.status(401).json({error: "Authentication required."});
          return;
        }
        const decodedToken = await admin.auth().verifyIdToken(firebaseToken);
        const userId = decodedToken.uid;

        const recipientEmail = normalizeEmail(request.body?.recipientEmail);
        const rawPaths = request.body?.filePaths;
        const validFileCount = Array.isArray(rawPaths) &&
          (rawPaths.length === 2 || rawPaths.length === 4);
        if (!recipientEmail || !validFileCount) {
          response.status(400).json({
            error: "A recipient email and the accounting export files are required.",
          });
          return;
        }

        const allowedPrefix = `users/${userId}/accounting_exports/`;
        const paths = rawPaths.map((value) => normalizeString(value).trim());
        if (paths.some((value) => !value.startsWith(allowedPrefix))) {
          response.status(403).json({
            error: "Accounting export files must belong to the signed-in user.",
          });
          return;
        }

        const names = paths.map((value) => value.split("/").pop()?.toUpperCase());
        const expectedMoveinNames = new Set(["MOVEIN.DOC", "MOVEIN.PRM"]);
        const expectedAllNames = new Set([
          ...expectedMoveinNames,
          "HESHIN.DAT",
          "HESHIN.PRM",
        ]);
        const expectedNames = names.length === 4 ? expectedAllNames :
          expectedMoveinNames;
        if (new Set(names).size !== expectedNames.size ||
            names.some((name) => !expectedNames.has(name))) {
          response.status(400).json({
            error: names.length === 4 ?
              "The attachments must be MOVEIN.DOC, MOVEIN.PRM, HESHIN.DAT, and HESHIN.PRM." :
              "The attachments must be MOVEIN.DOC and MOVEIN.PRM.",
          });
          return;
        }

        const bucket = admin.storage().bucket();
        const files = paths.map((filePath) => bucket.file(filePath));
        const metadata = await Promise.all(files.map(async (file) => {
          const [exists] = await file.exists();
          if (!exists) {
            const error = new Error("An accounting export file was not found.");
            error.statusCode = 404;
            throw error;
          }
          const [fileMetadata] = await file.getMetadata();
          return fileMetadata;
        }));
        const totalSize = metadata.reduce(
            (total, item) => total + (Number(item.size) || 0), 0,
        );
        if (totalSize > 28 * 1024 * 1024) {
          response.status(413).json({
            error: "The generated accounting files are too large to email.",
          });
          return;
        }

        const contents = await Promise.all(files.map(async (file) => {
          const [content] = await file.download();
          return content;
        }));
        const attachments = contents.map((content, index) => ({
          filename: names[index],
          content,
        }));
        const {data, error} = await new Resend(RESEND_API_KEY.value())
            .emails.send({
              from: RESEND_FROM_EMAIL.value(),
              to: [recipientEmail],
              subject: names.length === 4 ?
                "קובצי MOVEIN ו-HESHIN מהירו" : "קובצי MOVEIN מהירו",
              text: names.length === 4 ?
                "שלום,\n\nמצורפים קובצי HESHIN.DAT ו-HESHIN.PRM לייבוא כרטיסי החשבון, וקובצי MOVEIN.DOC ו-MOVEIN.PRM לייבוא פקודות היומן. יש לייבא תחילה את קובצי HESHIN ולאחר מכן את קובצי MOVEIN.\n\nבברכה,\nצוות הירו" :
                "שלום,\n\nמצורפים קובצי MOVEIN.DOC ו-MOVEIN.PRM לייבוא בהנהלת החשבונות.\n\nבברכה,\nצוות הירו",
              attachments,
            });
        if (error) {
          throw new Error(error.message || "Resend rejected the email.");
        }

        await Promise.all(files.map(async (file) => {
          await file.delete().catch((deleteError) => {
            logger.warn("Unable to delete emailed accounting export", {
              path: file.name,
              error: deleteError.message,
            });
          });
        }));
        response.json({sent: true, emailId: data?.id || null});
      } catch (error) {
        const statusCode = error?.statusCode ||
          (error?.code?.startsWith?.("auth/") ? 401 : 500);
        logger.error("Could not email accounting export", {
          error: error instanceof Error ? error.message : String(error),
        });
        response.status(statusCode).json({
          error: statusCode === 500 ?
            "Unable to send the accounting export files." :
            (error.message || "Authentication failed."),
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

        updates = createPlaySubscriptionUpdates(playState, userData, {
          purchaseToken: purchaseProof.verificationToken,
        });
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

  let userDoc = accountToken ?
    await findUserBySubscriptionAccountToken(accountToken) :
    await findUserByPurchaseToken(purchaseToken);

  if (!userDoc && playState?.linkedPurchaseToken) {
    userDoc = await findUserByPurchaseToken(playState.linkedPurchaseToken);
  }

  if (!userDoc) {
    throw new Error(
        `No user found for Google Play token ${purchaseToken} and account token ${accountToken}`,
    );
  }

  const updates = createPlaySubscriptionUpdates(playState, userDoc.data(), {
    purchaseToken,
  });
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
        updates: createPlaySubscriptionUpdates(playState, userData, {
          purchaseToken,
        }),
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

function createPlaySubscriptionUpdates(playState, userData, options = {}) {
  const purchaseToken = normalizeString(options.purchaseToken).trim();
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
    subscriptionPurchaseToken:
      purchaseToken || userData.subscriptionPurchaseToken || null,
    subscriptionPlatform: "google_play",
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

function addSeconds(date, seconds) {
  return new Date(date.getTime() + seconds * 1000);
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

async function findInvoiceRecipientUserIds(rawPhone, senderUserId) {
  const candidates = phoneCandidates(rawPhone);
  if (candidates.length === 0) return [];

  const db = admin.firestore();
  const recipientIds = new Set();

  for (const field of ["phone", "phoneNumber"]) {
    for (const chunk of chunkArray(candidates, 30)) {
      const snapshot = await db.collection("users")
          .where(field, "in", chunk)
          .limit(30)
          .get();

      for (const doc of snapshot.docs) {
        if (doc.id !== senderUserId) {
          recipientIds.add(doc.id);
        }
      }
    }
  }

  return [...recipientIds];
}

function phoneCandidates(input) {
  const normalized = normalizeString(input).trim().replace(/[\s\-()]/g, "");
  const digits = normalized.replace(/\D/g, "");
  const candidates = new Set();

  if (normalized) candidates.add(normalized);
  if (digits) candidates.add(digits);

  if (digits.startsWith("0") && digits.length === 10) {
    candidates.add(`+972${digits.slice(1)}`);
  }
  if (digits.length === 9) {
    candidates.add(`0${digits}`);
    candidates.add(`+972${digits}`);
  }
  if (digits.startsWith("972")) {
    candidates.add(`+${digits}`);
    if (digits.length === 12) {
      candidates.add(`0${digits.slice(3)}`);
    }
    if (digits.length > 4 && digits[3] === "0") {
      candidates.add(`+972${digits.slice(4)}`);
    }
  }
  if (normalized.startsWith("+9720") && normalized.length > 5) {
    candidates.add(`+972${normalized.slice(5)}`);
  }

  return [...candidates].filter(Boolean);
}

function chunkArray(values, size) {
  const chunks = [];
  for (let i = 0; i < values.length; i += size) {
    chunks.push(values.slice(i, i + size));
  }
  return chunks;
}

class BatchWriter {
  constructor(db) {
    this.db = db;
    this.batch = db.batch();
    this.writeCount = 0;
    this.commits = [];
  }

  set(ref, data, options) {
    this.batch.set(ref, data, options);
    this.writeCount += 1;
    this.flushIfNeeded();
  }

  delete(ref) {
    this.batch.delete(ref);
    this.writeCount += 1;
    this.flushIfNeeded();
  }

  flushIfNeeded() {
    if (this.writeCount < 450) return;
    this.commits.push(this.batch.commit());
    this.batch = this.db.batch();
    this.writeCount = 0;
  }

  async commit() {
    if (this.writeCount > 0) {
      this.commits.push(this.batch.commit());
    }
    await Promise.all(this.commits);
  }
}

function normalizeString(value) {
  return value == null ? "" : String(value);
}

function normalizeEmail(value) {
  const email = normalizeString(value).trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

function downloadFileName(fileName) {
  return normalizeString(fileName).replace(/[\\"\r\n]/g, "_") || "document.pdf";
}

function buildInvoiceEmailSubject(invoice, name, preposition = "ל") {
  const documentType = hebrewDocumentType(invoice.docType || invoice.type);
  const documentNumber = normalizeString(
      invoice.sequenceNumber || invoice.invoiceNumber || invoice.documentNumber,
  ).trim();
  const introduction = `${documentType} חדשה ${preposition}${name}`;
  return documentNumber ?
    `${introduction}: ${documentType} מספר ${documentNumber}` : introduction;
}

function buildClientInvoiceEmailText(invoice, clientName, businessName) {
  const documentType = hebrewDocumentType(invoice.docType || invoice.type);
  const documentNumber = normalizeString(
      invoice.sequenceNumber || invoice.invoiceNumber || invoice.documentNumber,
  ).trim();
  const documentReference = documentNumber ?
    `${documentType} מספר ${documentNumber}` : documentType;
  return `שלום ${clientName},\n\n` +
    `מצורף ${documentReference} שהופק עבורכם.\n\n` +
    "תודה שבחרתם לעבוד איתנו.\n\n" +
    `בברכה,\n${businessName}\n\n` +
    "מסמך זה נשלח באופן אוטומטי באמצעות מערכת הירו.\n" +
    "נא לא להשיב להודעה זו.";
}

function buildOwnerInvoiceEmailText(
    invoice, userName, clientName, clientEmail,
) {
  const documentType = hebrewDocumentType(invoice.docType || invoice.type);
  const documentNumber = normalizeString(
      invoice.sequenceNumber || invoice.invoiceNumber || invoice.documentNumber,
  ).trim();
  const documentReference = documentNumber ?
    `${documentType} מספר ${documentNumber}` : documentType;
  const recipient = clientEmail || "לא הוזנה כתובת דוא״ל ללקוח";
  return `שלום ${userName},\n\n` +
    `זהו אישור כי ${documentReference} נשלח בהצלחה ל${clientName} לכתובת:\n` +
    `${recipient}\n\n` +
    "המסמך מצורף להודעה זו.\n\n" +
    "בברכה,\nצוות הירו";
}

function buildOwnerInvoiceWithoutClientEmailText(invoice, userName) {
  const documentType = hebrewDocumentType(invoice.docType || invoice.type);
  const documentNumber = normalizeString(
      invoice.sequenceNumber || invoice.invoiceNumber || invoice.documentNumber,
  ).trim();
  const documentReference = documentNumber ?
    `${documentType} מספר ${documentNumber}` : documentType;
  return `שלום ${userName},\n\n` +
    `מצורף ${documentReference}.\n\n` +
    "תודה שבחרתם ב-הירו.\n\n" +
    "בברכה,\nצוות הירו";
}

function invoiceDocumentReference(invoice) {
  const documentType = hebrewDocumentType(invoice.docType || invoice.type);
  const documentNumber = normalizeString(
      invoice.sequenceNumber || invoice.invoiceNumber || invoice.documentNumber,
  ).trim();
  return documentNumber ? `${documentType} מספר ${documentNumber}` : documentType;
}

function escapeHtml(value) {
  return normalizeString(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[character]));
}

function buildInvoiceEmailHtml({name, heading, content, footer}) {
  return `<!doctype html>
<html lang="he" dir="rtl">
  <body style="margin:0;padding:0;background:#f4f7fb;font-family:Arial,Helvetica,sans-serif;color:#182230;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f7fb;padding:32px 12px;">
      <tr><td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#ffffff;border:1px solid #d9e3ef;border-radius:24px;overflow:hidden;">
          <tr><td style="padding:32px 32px 18px;text-align:center;">
            ${hiroBrandLogo()}
            <div style="margin-top:8px;font-size:13px;color:#718096;">ניהול עסק פשוט</div>
          </td></tr>
          <tr><td style="padding:12px 32px 32px;text-align:right;">
            <p style="margin:0 0 18px;font-size:17px;font-weight:700;">שלום ${escapeHtml(name)},</p>
            <h1 style="margin:0 0 20px;font-size:25px;line-height:1.35;color:#162f65;">${escapeHtml(heading)}</h1>
            ${content}
          </td></tr>
          <tr><td style="padding:22px 32px;background:#f8fafc;border-top:1px solid #e7edf4;text-align:center;font-size:12px;line-height:1.7;color:#758194;">
            ${footer}
            <p style="margin:0 0 14px;">הודעה זו נשלחה באופן אוטומטי באמצעות מערכת הירו. נא לא להשיב להודעה זו.</p>
            ${hiroBrandLogo()}
            <div style="margin:8px 0 18px;font-size:12px;color:#718096;">ניהול עסק פשוט</div>
            <table role="presentation" align="center" cellspacing="0" cellpadding="0"><tr>
              <td style="padding:0 4px 8px;"><a href="https://apps.apple.com/us/app/hiro-%D7%94%D7%99%D7%A8%D7%95/id6763238120" target="_blank" style="display:inline-block;text-decoration:none;"><img src="cid:app-store-badge" width="150" height="50" alt="Download on the App Store" style="display:block;border:0;width:150px;height:50px;"></a></td>
              <td style="padding:0 4px 8px;"><a href="https://play.google.com/store/apps/details?id=com.hirehub.app" target="_blank" style="display:inline-block;text-decoration:none;"><img src="cid:google-play-badge" width="167" height="50" alt="Get it on Google Play" style="display:block;border:0;width:167px;height:50px;"></a></td>
            </tr></table>
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`;
}

function documentCard(documentReference, downloadUrl, fileName) {
  const downloadButton = downloadUrl ?
    `<a href="${escapeHtml(downloadUrl)}" target="_blank" download="${escapeHtml(fileName)}" style="display:inline-block;margin-top:12px;padding:8px 18px;background:#27caaa;border-radius:999px;color:#073b34;font-size:14px;font-weight:700;text-decoration:none;">להורדת המסמך</a>` :
    '<div style="display:inline-block;margin-top:12px;padding:8px 18px;background:#27caaa;border-radius:999px;color:#073b34;font-size:14px;font-weight:700;">המסמך מצורף למייל</div>';
  return `<div style="margin:22px 0;padding:18px 20px;background:#eefbf8;border:1px solid #b7eee1;border-radius:14px;text-align:center;">
    <div style="font-size:13px;color:#39746b;margin-bottom:5px;">המסמך שלך</div>
    <div style="font-size:20px;font-weight:700;color:#123d38;">${escapeHtml(documentReference)}</div>
    ${downloadButton}
  </div>`;
}

function hiroBrandLogo() {
  return `<a href="https://hiro-services.com/" target="_blank" style="display:inline-block;text-decoration:none;direction:ltr;">
    <img src="cid:hiro-app-icon" width="32" height="32" alt="Hiro" style="display:inline-block;width:32px;height:32px;margin-right:7px;border-radius:9px;object-fit:cover;vertical-align:middle;">
    <span style="color:#111111;font-family:Arial,Helvetica,sans-serif;font-size:31px;font-weight:800;letter-spacing:-1.5px;line-height:32px;vertical-align:middle;">hiro</span>
  </a>`;
}

function buildClientInvoiceEmailHtml(
    invoice, clientName, businessName, downloadUrl, fileName,
) {
  const documentReference = invoiceDocumentReference(invoice);
  return buildInvoiceEmailHtml({
    name: clientName,
    heading: "מסמך חדש הופק עבורך",
    content: `<p style="margin:0;font-size:16px;line-height:1.7;">מצורף ${escapeHtml(documentReference)} שהופק עבורכם.</p>` +
      documentCard(documentReference, downloadUrl, fileName) +
      `<p style="margin:0;font-size:16px;line-height:1.7;">תודה שבחרתם לעבוד איתנו.</p><p style="margin:20px 0 0;font-size:16px;font-weight:700;">בברכה,<br>${escapeHtml(businessName)}</p>`,
    footer: "",
  });
}

function buildOwnerInvoiceEmailHtml(
    invoice, userName, clientName, clientEmail, downloadUrl, fileName,
) {
  const documentReference = invoiceDocumentReference(invoice);
  return buildInvoiceEmailHtml({
    name: userName,
    heading: "המסמך נשלח בהצלחה",
    content: `<p style="margin:0;font-size:16px;line-height:1.7;">${escapeHtml(documentReference)} נשלח בהצלחה ל${escapeHtml(clientName)}.</p>` +
      documentCard(documentReference, downloadUrl, fileName) +
      `<div style="padding:14px 16px;background:#f8fafc;border-radius:12px;font-size:14px;line-height:1.7;"><strong>כתובת הלקוח:</strong><br>${escapeHtml(clientEmail)}</div><p style="margin:20px 0 0;font-size:16px;font-weight:700;">בברכה,<br>צוות הירו</p>`,
    footer: "",
  });
}

function buildOwnerInvoiceWithoutClientEmailHtml(
    invoice, userName, downloadUrl, fileName,
) {
  const documentReference = invoiceDocumentReference(invoice);
  return buildInvoiceEmailHtml({
    name: userName,
    heading: "מסמך חדש נשמר בהצלחה",
    content: `<p style="margin:0;font-size:16px;line-height:1.7;">מצורף ${escapeHtml(documentReference)}.</p>` +
      documentCard(documentReference, downloadUrl, fileName) +
      `<p style="margin:0;font-size:16px;line-height:1.7;">תודה שבחרתם ב-הירו.</p><p style="margin:20px 0 0;font-size:16px;font-weight:700;">בברכה,<br>צוות הירו</p>`,
    footer: "",
  });
}

function hebrewDocumentType(docType) {
  switch (normalizeString(docType).trim()) {
    case "invoice": return "חשבונית מס";
    case "receipt": return "קבלה";
    case "invoice_receipt": return "חשבונית מס קבלה";
    case "credit_note": return "חשבונית זיכוי";
    case "quote": return "הצעת מחיר";
    case "work_order": return "הזמנת עבודה";
    case "transaction_account": return "חשבון עסקה";
    default: return "מסמך";
  }
}

function normalizeBusinessId(value) {
  const digits = normalizeString(value).replace(/\D/g, "");
  return /^\d{9}$/.test(digits) ? digits : null;
}

function maskBusinessId(value) {
  const businessId = normalizeBusinessId(value);
  return businessId ? `*****${businessId.slice(-4)}` : null;
}

async function getVerifiedTaxAuthorityBusinessId(userId) {
  const db = admin.firestore();
  const userRef = db.collection("users").doc(userId);
  const verificationRef = userRef
      .collection("verification_info")
      .doc("latest");
  const [userSnap, verificationSnap] = await Promise.all([
    userRef.get(),
    verificationRef.get(),
  ]);
  const userData = userSnap.data() || {};
  const verificationData = verificationSnap.data() || {};
  const businessId = normalizeBusinessId(
      verificationData.businessId || userData.businessId,
  );
  const dealerType = normalizeString(verificationData.dealerType).trim();
  const isApproved =
    userData.isapproved === true &&
    normalizeString(verificationData.status).trim() === "approved";

  if (!isApproved ||
      !businessId ||
      !["licensed", "company"].includes(dealerType)) {
    throw new HttpsError(
        "failed-precondition",
        "An approved licensed business is required before connecting " +
        "to the Tax Authority.",
    );
  }

  return businessId;
}

function maskOAuthState(state) {
  if (!state) return null;
  return state.length <= 8 ? "set" : `${state.slice(0, 4)}...${state.slice(-4)}`;
}

async function exchangeTaxAuthorityCodeForTokens(code) {
  const params = new URLSearchParams();
  params.set("grant_type", "authorization_code");
  params.set("client_id", TAX_AUTH_CLIENT_ID.value());
  params.set("client_secret", TAX_AUTH_CLIENT_SECRET.value());
  params.set("code", code);
  params.set("redirect_uri", TAX_AUTH_REDIRECT_URI);
  params.set("scope", TAX_AUTH_SCOPE);

  return await postTaxAuthorityTokenForm(params, "token exchange");
}

async function postTaxAuthorityTokenForm(params, operationName) {
  const urls = [
    TAX_AUTH_SANDBOX_TOKEN_URL,
    TAX_AUTH_SANDBOX_TOKEN_FALLBACK_URL,
  ];
  let lastError = null;

  for (const tokenUrl of urls) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 25000);
    let response;
    try {
      response = await fetch(tokenUrl, {
        method: "POST",
        headers: {
          "content-type": "application/x-www-form-urlencoded",
          "accept": "application/json",
          "user-agent": "Hiro/1.0 FirebaseFunctions",
        },
        body: params.toString(),
        signal: controller.signal,
      });
    } catch (error) {
      lastError = error;
      logger.warn(`Tax Authority ${operationName} network failure`, {
        tokenUrl,
        message: normalizeString(error.message),
        cause: normalizeString(error.cause?.message),
        code: normalizeString(error.cause?.code || error.code),
      });
      clearTimeout(timeout);
      continue;
    }
    clearTimeout(timeout);
    const payload = await parseJsonResponse(response);

    if (!response.ok) {
      logger.error(`Tax Authority ${operationName} failed`, {
        tokenUrl,
        status: response.status,
        payload: maskTokenPayload(payload),
      });
      throw new Error(
          `Tax Authority ${operationName} failed: ${response.status}`,
      );
    }

    return payload;
  }

  throw lastError || new Error(`Tax Authority ${operationName} failed.`);
}

async function getTaxAuthorityTokenData(userId, businessId) {
  const tokenDocuments = await loadTaxAuthorityTokenDocuments(userId);
  const tokenSnap = tokenDocuments.activeSnap;
  if (!tokenSnap.exists) {
    throw new HttpsError(
        "failed-precondition",
        "Tax Authority OAuth authorization has not been completed.",
    );
  }

  const tokenData = tokenSnap.data() || {};
  const tokenBusinessId = normalizeBusinessId(tokenData.businessId);
  if (!tokenBusinessId || tokenBusinessId !== businessId) {
    throw new HttpsError(
        "failed-precondition",
        "Reconnect the Tax Authority account for your verified business ID.",
    );
  }

  const accessToken = normalizeString(tokenData.access_token).trim();
  if (!accessToken) {
    throw new HttpsError(
        "failed-precondition",
        "Tax Authority access token is missing.",
    );
  }

  const expiresAt = toDate(tokenData.expiresAt);
  if (!expiresAt || expiresAt.getTime() <= Date.now()) {
    const disconnectedUpdate = {
      connected: false,
      disconnectedAt: admin.firestore.FieldValue.serverTimestamp(),
      disconnectReason: expiresAt ?
        "token-expired" :
        "token-expiry-missing",
    };
    const batch = admin.firestore().batch();
    if (tokenDocuments.userOAuthSnap.exists) {
      batch.set(
          tokenDocuments.userOAuthRef,
          disconnectedUpdate,
          {merge: true},
      );
    }
    if (tokenDocuments.secureTokenSnap.exists) {
      batch.set(
          tokenDocuments.secureTokenRef,
          disconnectedUpdate,
          {merge: true},
      );
    }
    await batch.commit();
    throw new HttpsError(
        "failed-precondition",
        "Tax Authority OAuth authorization has expired. " +
        "Reconnect your account.",
    );
  }

  return {accessToken, tokenData};
}

function taxAuthorityTokenRefs(userId) {
  const db = admin.firestore();
  const userOAuthRef = db
      .collection("users")
      .doc(userId)
      .collection("tax_authority")
      .doc("oauth");
  const secureTokenRef = db
      .collection("taxAuthorityOAuthTokens")
      .doc(userId);
  return {userOAuthRef, secureTokenRef};
}

async function loadTaxAuthorityTokenDocuments(userId) {
  const {userOAuthRef, secureTokenRef} = taxAuthorityTokenRefs(userId);
  const [userOAuthSnap, secureTokenSnap] = await Promise.all([
    userOAuthRef.get(),
    secureTokenRef.get(),
  ]);
  return {
    userOAuthRef,
    secureTokenRef,
    userOAuthSnap,
    secureTokenSnap,
    activeSnap: userOAuthSnap.exists ? userOAuthSnap : secureTokenSnap,
  };
}

async function callTaxAuthorityMultiApproval({accessToken, payload}) {
  const response = await fetch(TAX_AUTH_SANDBOX_MULTI_APPROVAL_URL, {
    method: "POST",
    headers: {
      "authorization": `Bearer ${accessToken}`,
      "content-type": "application/json",
      "accept": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const responsePayload = await parseJsonResponse(response);
  if (!response.ok) {
    const authorityMessage =
      summarizeTaxAuthorityErrorMessages(responsePayload) ||
      "Tax Authority invoice allocation request failed.";
    logger.error("Tax Authority MultiApproval failed", {
      status: response.status,
      payload: responsePayload,
    });
    throw new HttpsError(
        "failed-precondition",
        authorityMessage,
        {
          authorityStatus: response.status,
          authorityResponse: responsePayload,
        },
    );
  }

  return responsePayload;
}

function normalizeTaxInvoiceAllocationPayload(data) {
  const invoice = data.invoice || data;
  const invoiceId = requiredString(invoice.invoice_id || invoice.invoiceId,
      "invoice_id");
  const vatNumber = requiredInt(invoice.vat_number || invoice.vatNumber,
      "vat_number");
  const invoiceReferenceNumber = requiredString(
      invoice.invoice_reference_number || invoice.invoiceReferenceNumber,
      "invoice_reference_number",
  );
  const customerVatNumber = requiredInt(
      invoice.customer_vat_number || invoice.customerVatNumber,
      "customer_vat_number",
  );
  const invoiceDate = requiredString(
      invoice.invoice_date || invoice.invoiceDate,
      "invoice_date",
  );
  const invoiceIssuanceDate = normalizeString(
      invoice.invoice_issuance_date || invoice.invoiceIssuanceDate ||
      invoiceDate,
  ).trim();
  const paymentAmount = requiredNumber(
      invoice.payment_amount || invoice.paymentAmount,
      "payment_amount",
  );
  const vatAmount = requiredNumber(
      invoice.vat_amount || invoice.vatAmount,
      "vat_amount",
  );
  const amountBeforeDiscount = numberOrDefault(
      invoice.amount_before_discount || invoice.amountBeforeDiscount,
      paymentAmount,
  );
  const discount = numberOrDefault(invoice.discount, 0);
  const paymentAmountIncludingVat = numberOrDefault(
      invoice.payment_amount_including_vat ||
      invoice.paymentAmountIncludingVat,
      paymentAmount + vatAmount,
  );
  const accountingSoftwareNumber = requiredInt(
      invoice.accounting_software_number || invoice.accountingSoftwareNumber,
      "accounting_software_number",
  );
  const invoiceType = intOrDefault(
      invoice.invoice_type || invoice.invoiceType,
      305,
  );

  const invoiceRequest = omitNullish({
    invoice_id: invoiceId,
    invoice_type: invoiceType,
    vat_number: vatNumber,
    union_vat_number: intOrNull(
        invoice.union_vat_number || invoice.unionVatNumber,
    ),
    authorized_company: intOrNull(
        invoice.authorized_company || invoice.authorizedCompany,
    ),
    user_id: intOrNull(invoice.user_id || invoice.userId),
    user_name: stringOrNull(invoice.user_name || invoice.userName, 25),
    invoice_reference_number: invoiceReferenceNumber,
    customer_vat_number: customerVatNumber,
    customer_name: stringOrNull(
        invoice.customer_name || invoice.customerName,
        25,
    ),
    customer_country_code: stringOrNull(
        invoice.customer_country_code || invoice.customerCountryCode,
        3,
    ),
    invoice_date: invoiceDate,
    invoice_issuance_date: invoiceIssuanceDate,
    branch_id: stringOrNull(invoice.branch_id || invoice.branchId, 7),
    accounting_software_number: accountingSoftwareNumber,
    client_software_key: stringOrNull(
        invoice.client_software_key || invoice.clientSoftwareKey,
        50,
    ),
    amount_before_discount: roundMoney(amountBeforeDiscount),
    discount: roundMoney(discount),
    payment_amount: roundMoney(paymentAmount),
    vat_amount: roundMoney(vatAmount),
    payment_amount_including_vat: roundMoney(paymentAmountIncludingVat),
    invoice_note: stringOrNull(invoice.invoice_note || invoice.invoiceNote, 100),
    action: intOrDefault(invoice.action, 0),
    delivery_address: stringOrNull(
        invoice.delivery_address || invoice.deliveryAddress,
        60,
    ),
    items: normalizeTaxInvoiceItems(invoice.items),
  });

  return {
    vat_number: vatNumber,
    union_vat_number: intOrNull(data.union_vat_number || data.unionVatNumber),
    invoices_amount: 1,
    invoices_payment_amount: roundMoney(paymentAmount),
    invoices_vat_amount: roundMoney(vatAmount),
    invoices_list: [invoiceRequest],
  };
}

function normalizeTaxInvoiceItems(items) {
  if (!Array.isArray(items)) return null;
  return items.map((item, index) => {
    const quantity = numberOrDefault(item.quantity, 1);
    const pricePerUnit = numberOrDefault(
        item.price_per_unit || item.pricePerUnit ||
        item.unitPriceWithoutTax || item.price,
        0,
    );
    const totalAmount = numberOrDefault(
        item.total_amount || item.totalAmount,
        quantity * pricePerUnit,
    );
    const vatRate = numberOrDefault(item.vat_rate || item.vatRate, 17);
    const vatAmount = numberOrDefault(
        item.vat_amount || item.vatAmount || item.taxPaid,
        totalAmount * (vatRate / 100),
    );

    return omitNullish({
      index: intOrDefault(item.index, index + 1),
      catalog_id: stringOrNull(item.catalog_id || item.catalogId, 13),
      category: intOrDefault(item.category, 200000),
      description: stringOrNull(item.description, 30),
      measure_unit_description: stringOrNull(
          item.measure_unit_description || item.measureUnitDescription,
          20,
      ),
      quantity: roundMoney(quantity),
      price_per_unit: roundMoney(pricePerUnit),
      discount: roundMoney(numberOrDefault(item.discount, 0)),
      total_amount: roundMoney(totalAmount),
      vat_rate: roundMoney(vatRate),
      vat_amount: roundMoney(vatAmount),
    });
  });
}

function extractTaxAuthorityApproval(response, requestPayload) {
  const message = response?.message || {};
  const success = Array.isArray(message.success) ? message.success : [];
  const errors = Array.isArray(message.errors) ? message.errors : [];
  const invoiceId = requestPayload.invoices_list?.[0]?.invoice_id || null;
  const successItem = success.find((item) => item.invoice_id === invoiceId) ||
    success[0] ||
    null;
  const errorItem = errors.find((item) => item.invoice_id === invoiceId) ||
    errors[0] ||
    null;

  return {
    approved: successItem?.approved === true,
    invoiceId,
    confirmationNumber: successItem?.confirmation_number ||
      errorItem?.confirmation_number ||
      null,
    transactionId: response?.transaction_id || null,
    errors: errorItem?.message?.errors || [],
  };
}

function summarizeTaxAuthorityErrorMessages(payload) {
  const messages = [];
  const seen = new Set();

  function collect(value) {
    if (messages.length >= 3 || value == null) return;
    if (typeof value === "string") {
      const message = value.trim();
      if (message && !seen.has(message)) {
        seen.add(message);
        messages.push(message);
      }
      return;
    }
    if (Array.isArray(value)) {
      for (const entry of value) collect(entry);
      return;
    }
    if (typeof value === "object") {
      if (typeof value.message === "string") {
        collect(value.message);
      } else if (value.message) {
        collect(value.message);
      }
      if (value.errors) collect(value.errors);
    }
  }

  collect(payload?.message?.errors);
  return messages.join("; ");
}

async function parseJsonResponse(response) {
  const responseText = await response.text();
  try {
    return responseText ? JSON.parse(responseText) : {};
  } catch (error) {
    return {rawResponse: responseText};
  }
}

function maskTokenPayload(payload) {
  if (!payload || typeof payload !== "object") {
    return payload;
  }

  return Object.fromEntries(Object.entries(payload).map(([key, value]) => {
    if (key.toLowerCase().includes("token")) {
      return [key, typeof value === "string" ? maskToken(value) : "set"];
    }
    return [key, value];
  }));
}

function requiredString(value, fieldName) {
  const normalized = normalizeString(value).trim();
  if (!normalized) {
    throw new HttpsError("invalid-argument", `Missing ${fieldName}.`);
  }
  return normalized;
}

function requiredInt(value, fieldName) {
  const parsed = intOrNull(value);
  if (parsed == null) {
    throw new HttpsError("invalid-argument", `Missing ${fieldName}.`);
  }
  return parsed;
}

function requiredNumber(value, fieldName) {
  const parsed = numberOrNull(value);
  if (parsed == null) {
    throw new HttpsError("invalid-argument", `Missing ${fieldName}.`);
  }
  return parsed;
}

function intOrDefault(value, fallback) {
  return intOrNull(value) ?? fallback;
}

function intOrNull(value) {
  if (value == null || value === "") return null;
  const parsed = Number.parseInt(String(value).replace(/\D/g, ""), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function numberOrDefault(value, fallback) {
  return numberOrNull(value) ?? fallback;
}

function numberOrNull(value) {
  if (value == null || value === "") return null;
  const parsed = Number(String(value).replace(/,/g, "."));
  return Number.isFinite(parsed) ? parsed : null;
}

function stringOrNull(value, maxLength) {
  const normalized = normalizeString(value).trim();
  if (!normalized) return null;
  return maxLength ? normalized.slice(0, maxLength) : normalized;
}

function roundMoney(value) {
  return Math.round(Number(value) * 100) / 100;
}

function omitNullish(value) {
  return Object.fromEntries(Object.entries(value).filter(([, entryValue]) => {
    if (entryValue == null) return false;
    if (Array.isArray(entryValue) && entryValue.length === 0) return false;
    return true;
  }));
}

function renderOAuthCallbackPage({title, message}) {
  const success = title === "Authorization received";
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <style>
    body {
      align-items: center;
      background: #f7f8fb;
      color: #10345c;
      display: flex;
      font-family: Arial, sans-serif;
      justify-content: center;
      margin: 0;
      min-height: 100vh;
      padding: 24px;
    }
    main {
      background: #fff;
      border: 1px solid #d8e0ea;
      border-radius: 8px;
      box-shadow: 0 12px 32px rgba(16, 52, 92, 0.08);
      max-width: 480px;
      padding: 32px;
      text-align: center;
    }
    h1 {
      font-size: 24px;
      margin: 0 0 12px;
    }
    p {
      line-height: 1.5;
      margin: 0;
    }
    a {
      background: #10345c;
      border-radius: 8px;
      color: #fff;
      display: ${success ? "inline-block" : "none"};
      font-weight: 700;
      margin-top: 20px;
      padding: 12px 18px;
      text-decoration: none;
    }
  </style>
  ${success ? `<script>
    window.setTimeout(function() {
      window.location.href = "${TAX_AUTH_APP_RETURN_URI}";
    }, 500);
  </script>` : ""}
</head>
<body>
  <main>
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(message)}</p>
    <a href="${TAX_AUTH_APP_RETURN_URI}">Open Hiro</a>
  </main>
</body>
</html>`;
}

function escapeHtml(value) {
  return normalizeString(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
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

function hashSigningToken(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
}

function signingTokenFromRequest(req) {
  const pathToken = normalizeString(req.path)
      .split("/")
      .filter(Boolean)
      .pop();
  const token = normalizeString(req.query.token || pathToken).trim();
  return /^[A-Za-z0-9_-]{40,60}$/.test(token) ? token : "";
}

async function streamSigningPdf(res, signingRequest) {
  const storagePath = assertOwnedInvoicePdfPath(
      signingRequest.storagePath,
      normalizeString(signingRequest.workerId).trim(),
  );
  const [bytes] = await admin.storage().bucket().file(storagePath).download();
  res.set({
    "Content-Type": "application/pdf",
    "Content-Disposition": `inline; filename="${
      safeHeaderFileName(signingRequest.fileName)
    }"`,
    "Cache-Control": "private, no-store",
  });
  res.status(200).send(bytes);
}

async function signAndReplacePdf(signingRequest, signatureBytes, signerName) {
  const bucket = admin.storage().bucket();
  const storagePath = assertOwnedInvoicePdfPath(
      signingRequest.storagePath,
      normalizeString(signingRequest.workerId).trim(),
  );
  const file = bucket.file(storagePath);
  const [originalBytes] = await file.download();
  const [existingMetadata] = await file.getMetadata();
  const pdfDocument = await PDFDocument.load(originalBytes);
  pdfDocument.registerFontkit(fontkit);
  const signature = await pdfDocument.embedPng(signatureBytes);
  const fontBytes = fs.readFileSync(SIGNING_FONT_PATH);
  const font = await pdfDocument.embedFont(fontBytes, {subset: true});
  const page = pdfDocument.getPages().at(-1);
  const pageWidth = page.getWidth();
  const maxWidth = Math.min(190, pageWidth - 100);
  const maxHeight = 62;
  const scale = Math.min(
      maxWidth / signature.width,
      maxHeight / signature.height,
      1,
  );
  const width = signature.width * scale;
  const height = signature.height * scale;
  const x = Math.max(40, (pageWidth - width) / 2);
  const y = 166;

  page.drawRectangle({
    x: 24,
    y: 24,
    width: pageWidth - 48,
    height: 210,
    color: rgb(1, 1, 1),
    opacity: 1,
  });
  page.drawImage(signature, {x, y, width, height});
  const signatureLineWidth = Math.min(260, pageWidth - 100);
  const signatureLineX = (pageWidth - signatureLineWidth) / 2;
  const signatureLabel = "חתימה:";
  const signatureLabelSize = 10;
  const signatureLabelWidth = font.widthOfTextAtSize(
      signatureLabel,
      signatureLabelSize,
  );
  const signatureLabelX =
    signatureLineX + signatureLineWidth - signatureLabelWidth;
  page.drawText(signatureLabel, {
    x: signatureLabelX,
    y: 151,
    size: signatureLabelSize,
    font,
    color: rgb(0.2, 0.24, 0.28),
  });
  page.drawLine({
    start: {x: signatureLineX, y: 153},
    end: {x: signatureLabelX - 6, y: 153},
    thickness: 0.8,
    color: rgb(0.2, 0.24, 0.28),
  });
  const signedAt = new Date();
  drawCenteredPdfParts(page, [
    {text: formatSigningDate(signedAt), direction: "ltr"},
    {text: "בתאריך", direction: "rtl"},
    {text: signerName, direction: "ltr"},
    {text: "נחתם על ידי", direction: "rtl"},
  ], {
    font,
    size: 8.5,
    y: 132,
    color: rgb(0.2, 0.22, 0.25),
  });

  page.drawLine({
    start: {x: 32, y: 112},
    end: {x: pageWidth - 32, y: 112},
    thickness: 1,
    color: rgb(0.08, 0.08, 0.08),
  });

  drawRightAlignedPdfText(
      page,
      "חתימה דיגיטלית מאובטחת",
      {
        font,
        size: 16,
        x: pageWidth - 32,
        y: 84,
        color: rgb(0.03, 0.03, 0.03),
      },
  );
  drawRightAlignedPdfText(
      page,
      "מסמך זה נחתם דיגיטלית באמצעות מערכת הירו",
      {
        font,
        size: 8.5,
        x: pageWidth - 32,
        y: 64,
        color: rgb(0.08, 0.08, 0.08),
      },
  );

  const documentLabel =
    normalizeString(signingRequest.documentName) ||
    normalizeString(signingRequest.fileName) ||
    "מסמך";
  const pageCount = pdfDocument.getPageCount();
  drawPdfParts(page, [
    {text: "הופק ב", direction: "rtl"},
    {text: formatSigningDate(signedAt), direction: "ltr"},
    {text: "|", direction: "ltr"},
    {text: documentLabel, direction: "ltr"},
    {text: "|", direction: "ltr"},
    {text: "עמוד", direction: "rtl"},
    {text: String(pageCount), direction: "ltr"},
    {text: "מתוך", direction: "rtl"},
    {text: String(pageCount), direction: "ltr"},
  ], {
    x: 32,
    y: 64,
    size: 8,
    font,
    color: rgb(0.08, 0.08, 0.08),
  });

  const signedBytes = await pdfDocument.save();
  const metadata = {...(existingMetadata.metadata || {})};
  if (!metadata.firebaseStorageDownloadTokens) {
    metadata.firebaseStorageDownloadTokens = crypto.randomUUID();
  }
  await file.save(Buffer.from(signedBytes), {
    resumable: false,
    contentType: "application/pdf",
    metadata: {metadata},
  });
  const token = metadata.firebaseStorageDownloadTokens;
  const encodedPath = encodeURIComponent(storagePath);
  return {
    url: `https://firebasestorage.googleapis.com/v0/b/${
      bucket.name
    }/o/${encodedPath}?alt=media&token=${encodeURIComponent(token)}`,
  };
}

async function publishSignedDocument(signingRequest, signed) {
  const db = admin.firestore();
  const workerId = normalizeString(signingRequest.workerId);
  const receiverId = normalizeString(signingRequest.receiverId);
  const documentName =
    normalizeString(signingRequest.documentName) || "מסמך";
  const notificationRef = db
      .collection("users")
      .doc(workerId)
      .collection("notifications")
      .doc();
  const batch = db.batch();

  batch.set(notificationRef, {
    type: "document_signed",
    title: "המסמך נחתם",
    body: `${signed.signerName} חתם/ה על ${documentName}`,
    message: `${signed.signerName} חתם/ה על ${documentName}`,
    fromId: receiverId,
    fromName: signed.signerName,
    chatPartnerId: receiverId,
    chatPartnerName: signed.signerName,
    invoiceDocId: signingRequest.invoiceDocId,
    isRead: false,
    timestamp: signed.signedAt,
  });

  if (receiverId) {
    const roomId = [workerId, receiverId].sort().join("_");
    const messageRef = db
        .collection("chat_rooms")
        .doc(roomId)
        .collection("messages")
        .doc();
    const text = `המסמך נחתם על ידי ${signed.signerName}`;
    batch.set(messageRef, {
      senderId: receiverId,
      receiverId: workerId,
      message: text,
      text,
      type: "file",
      url: signed.signedUrl,
      fileUrl: signed.signedUrl,
      fileName: `חתום - ${
        normalizeString(signingRequest.fileName) || "document.pdf"
      }`,
      invoiceDocId: signingRequest.invoiceDocId,
      signedDocument: true,
      timestamp: signed.signedAt,
      isRead: false,
    });
    batch.set(db.collection("chat_rooms").doc(roomId), {
      lastMessage: text,
      lastMessageTime: signed.signedAt,
      lastTimestamp: signed.signedAt,
      users: [workerId, receiverId],
      unreadCount: {
        [workerId]: admin.firestore.FieldValue.increment(1),
      },
    }, {merge: true});
  }

  await batch.commit();
}

function renderSigningPage(token, signingRequest) {
  const alreadySigned = signingRequest.status === "signed";
  const documentName = normalizeString(signingRequest.documentName)
      .replace(/^Quote\b/i, "הצעת מחיר");
  const title = escapeHtml(
      documentName || "מסמך לחתימה",
  );
  const pdfUrl = `/sign/${encodeURIComponent(token)}?pdf=1`;
  return `<!doctype html>
<html lang="he" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${title}</title>
  <style>
    *{box-sizing:border-box}html,body{min-height:100%}body{margin:0;
    background:#f4f7fb;color:#0f172a;font-family:Arial,sans-serif;display:flex;
    flex-direction:column}.site-header{padding:16px 4% 0;position:relative;z-index:1}
    .header-shell{width:min(1240px,100%);margin:auto;min-height:72px;padding:10px 14px;
    display:flex;align-items:center;justify-content:space-between;gap:20px;
    border:1px solid #ffffff99;border-radius:28px;background:#ffffffcc;
    box-shadow:0 10px 28px #0f172a12;backdrop-filter:blur(14px)}.brand{display:flex;
    align-items:center;gap:11px;color:#0f172a;text-decoration:none}.brand-mark{width:44px;
    height:44px;border-radius:16px;object-fit:cover;box-shadow:0 5px 14px #2563eb40}
    .brand-name{font-size:21px;font-weight:800;letter-spacing:-.4px}.brand-tagline{display:block;
    margin-top:2px;color:#2563eb99;font-size:10px;font-weight:700;letter-spacing:2.8px;
    text-transform:uppercase}.site-nav{display:flex;align-items:center;gap:4px;padding:5px;
    border-radius:18px;background:#f8fafccc}.site-nav a{padding:9px 12px;border-radius:13px;
    color:#475569;text-decoration:none;font-size:14px;font-weight:700;transition:.2s}.site-nav a:hover{
    background:#eff6ff;color:#2563eb}.header-action{padding:10px 16px;border-radius:15px;
    background:linear-gradient(135deg,#2563eb,#0ea5e9);color:#fff;text-decoration:none;
    font-size:14px;font-weight:800;box-shadow:0 6px 16px #2563eb42}.header-tools{display:flex;
    align-items:center;gap:12px}.language-switcher{display:flex;align-items:center;gap:2px;padding:5px;
    border-radius:18px;background:#f1f5f9}.language-switcher span{padding:7px 10px;border-radius:12px;
    color:#64748b;font-size:13px;font-weight:800}.language-switcher .active{background:#fff;color:#2563eb;
    box-shadow:0 1px 4px #0f172a12}.sign-in{padding:9px 5px;color:#334155;text-decoration:none;
    font-size:14px;font-weight:800}.page-content{flex:1}.wrap{
    width:min(1100px,94%);margin:20px auto 36px;display:grid;grid-template-columns:1.5fr 1fr;gap:18px}
    .card{background:#fff;border:1px solid #dbe3ee;border-radius:16px;
    overflow:hidden;box-shadow:0 8px 24px #0f172a12}.pdf{width:100%;height:72vh;
    border:0}.form{padding:20px}.form h2{margin-top:0}label{display:block;
    font-weight:700;margin:14px 0 6px}input{width:100%;padding:12px;
    border:1px solid #cbd5e1;border-radius:10px;font-size:16px}canvas{width:100%;
    height:180px;border:2px dashed #94a3b8;border-radius:10px;touch-action:none;
    background:#fff}button{width:100%;border:0;border-radius:10px;padding:13px;
    margin-top:12px;font-size:16px;font-weight:700;cursor:pointer}.primary{
    background:#7c3aed;color:#fff}.secondary{background:#e2e8f0;color:#0f172a}
    .status{padding:12px;border-radius:10px;background:#ecfdf5;color:#166534;
    margin-bottom:12px}.error{background:#fef2f2;color:#991b1b}
    .site-footer{position:relative;overflow:hidden;margin-top:auto;padding:42px 4% 30px;
    background:linear-gradient(135deg,#0e2236,#10283f 55%,#175181);color:#eff6ff}.site-footer:before,
    .site-footer:after{content:'';position:absolute;border-radius:50%;filter:blur(45px);opacity:.32}
    .site-footer:before{width:180px;height:180px;top:-90px;right:8%;background:#38bdf8}.site-footer:after{
    width:210px;height:210px;bottom:-125px;left:5%;background:#60a5fa}.footer-shell{position:relative;
    width:min(1240px,100%);margin:auto;padding:22px 24px;border:1px solid #ffffff26;border-radius:30px;
    background:#ffffff0f;box-shadow:0 12px 36px #02061733}.footer-top,.footer-bottom{display:flex;
    align-items:center;justify-content:space-between;gap:20px}.footer-brand{display:flex;align-items:center;
    gap:11px;color:#fff;text-decoration:none}.footer-brand .brand-name{color:#fff}.footer-brand .brand-tagline{
    color:#bae6fd}.footer-links{display:flex;flex-wrap:wrap;gap:18px}.footer-links a{color:#dbeafe;
    text-decoration:none;font-size:14px;font-weight:700}.footer-links a:hover{color:#fff}.store-links{display:flex;
    gap:9px}.store-links a{padding:8px 11px;border:1px solid #ffffff33;border-radius:14px;
    color:#eff6ff;text-decoration:none;font-size:12px;font-weight:700;background:#ffffff12}.footer-rule{
    height:1px;background:#ffffff33;margin:20px 0}.copyright{margin:0;color:#dbeafe;font-size:13px;font-weight:600}
    @media(max-width:800px){.site-header{padding:12px 12px 0}.header-shell{min-height:64px;border-radius:23px}
    .brand-mark{width:40px;height:40px}.site-nav,.language-switcher,.sign-in{display:none}.header-action{padding:9px 12px}.wrap{
    grid-template-columns:1fr;margin-top:16px}.pdf{height:58vh}.site-footer{padding:30px 12px 20px}
    .footer-shell{border-radius:24px;padding:20px}.footer-top,.footer-bottom{align-items:flex-start;
    flex-direction:column}.footer-bottom{gap:14px}.store-links{width:100%;flex-wrap:wrap}}
  </style>
</head>
<body>
  <header class="site-header">
    <div class="header-shell">
      <a class="brand" href="${PUBLIC_APP_ORIGIN}" aria-label="מעבר לאתר Hiro">
        <img class="brand-mark" src="${PUBLIC_APP_ORIGIN}/web-app-manifest-192x192.png" alt="Hiro">
        <span><span class="brand-name">Hiro</span><span class="brand-tagline">Trusted local pros</span></span>
      </a>
      <nav class="site-nav" aria-label="ניווט ראשי">
        <a href="${PUBLIC_APP_ORIGIN}/">Home</a>
        <a href="${PUBLIC_APP_ORIGIN}/search">Search</a>
        <a href="${PUBLIC_APP_ORIGIN}/community">Community</a>
        <a href="${PUBLIC_APP_ORIGIN}/messages">Messages</a>
      </nav>
      <div class="header-tools">
        <div class="language-switcher" aria-label="Language">
          <span class="active">EN</span><span>עב</span><span>ع</span>
        </div>
        <a class="sign-in" href="${PUBLIC_APP_ORIGIN}/auth/signin">Sign In</a>
        <a class="header-action" href="${PUBLIC_APP_ORIGIN}/auth/signup">Sign Up</a>
      </div>
    </div>
  </header>
  <main class="page-content"><div class="wrap">
    <section class="card"><iframe class="pdf" src="${pdfUrl}"></iframe></section>
    <section class="card form">
      ${alreadySigned ? `
        <div class="status">המסמך כבר נחתם ונשלח לבעל המקצוע.</div>
        <button class="primary" id="share">שלח מחדש את המסמך</button>
      ` : `
        <h2>חתימה על המסמך</h2>
        <p>יש לעיין במסמך, לכתוב שם מלא ולחתום בתיבה.</p>
        <div id="message"></div>
        <label for="name">שם מלא</label>
        <input id="name" maxlength="100" autocomplete="name">
        <label>חתימה</label>
        <canvas id="signature"></canvas>
        <button class="secondary" id="clear">נקה חתימה</button>
        <button class="primary" id="submit">חתום ושלח מחדש</button>
      `}
    </section>
  </div></main>
  <footer class="site-footer">
    <div class="footer-shell">
      <div class="footer-top">
        <a class="footer-brand" href="${PUBLIC_APP_ORIGIN}">
          <img class="brand-mark" src="${PUBLIC_APP_ORIGIN}/web-app-manifest-192x192.png" alt="Hiro">
          <span><span class="brand-name">Hiro</span><span class="brand-tagline">Local services</span></span>
        </a>
        <div class="store-links">
          <a href="https://play.google.com/store/apps/details?id=com.hirehub.app" target="_blank" rel="noreferrer">Google Play</a>
          <a href="https://apps.apple.com/us/app/hiro-%D7%94%D7%99%D7%A8%D7%95/id6763238120" target="_blank" rel="noreferrer">App Store</a>
        </div>
      </div>
      <div class="footer-rule"></div>
      <div class="footer-bottom">
        <p class="copyright">Hiro Ltd. Copyright 2012–2026</p>
        <nav class="footer-links" aria-label="קישורים משפטיים">
          <a href="${PUBLIC_APP_ORIGIN}/contact">יצירת קשר</a>
          <a href="${PUBLIC_APP_ORIGIN}/terms-of-service">תנאי שימוש</a>
          <a href="${PUBLIC_APP_ORIGIN}/privacy-policy">מדיניות פרטיות</a>
        </nav>
      </div>
    </div>
  </footer>
  <script>
  const shareDocument=async()=>{const data={title:${JSON.stringify(title)},
    text:'מסמך חתום',url:location.href};if(navigator.share){await navigator.share(data)}
    else{await navigator.clipboard.writeText(location.href);alert('הקישור הועתק')}}
  document.getElementById('share')?.addEventListener('click',shareDocument);
  const canvas=document.getElementById('signature');
  if(canvas){
    const ctx=canvas.getContext('2d');let drawing=false;
    const resize=()=>{const ratio=devicePixelRatio||1;const rect=canvas.getBoundingClientRect();
      canvas.width=rect.width*ratio;canvas.height=rect.height*ratio;ctx.scale(ratio,ratio);
      ctx.lineWidth=2.4;ctx.lineCap='round';ctx.strokeStyle='#111827'};resize();
    const point=e=>{const r=canvas.getBoundingClientRect();const p=e.touches?.[0]||e;
      return{x:p.clientX-r.left,y:p.clientY-r.top}};
    const start=e=>{e.preventDefault();drawing=true;const p=point(e);ctx.beginPath();
      ctx.moveTo(p.x,p.y)};const move=e=>{if(!drawing)return;e.preventDefault();
      const p=point(e);ctx.lineTo(p.x,p.y);ctx.stroke()};const stop=()=>drawing=false;
    canvas.addEventListener('pointerdown',start);canvas.addEventListener('pointermove',move);
    window.addEventListener('pointerup',stop);
    document.getElementById('clear').onclick=()=>ctx.clearRect(0,0,canvas.width,canvas.height);
    document.getElementById('submit').onclick=async()=>{
      const button=document.getElementById('submit');const message=document.getElementById('message');
      button.disabled=true;button.textContent='שולח...';
      try{const response=await fetch(location.pathname,{method:'POST',
        headers:{'Content-Type':'application/json'},body:JSON.stringify({
          signerName:document.getElementById('name').value,
          signature:canvas.toDataURL('image/png')})});
        const result=await response.json();if(!response.ok)throw new Error(result.error);
        message.className='status';message.textContent=result.message;
        button.textContent='שלח מחדש את המסמך';button.disabled=false;
        button.onclick=shareDocument;document.querySelector('.pdf').src='${pdfUrl}&v='+Date.now();
      }catch(error){message.className='status error';message.textContent=error.message;
        button.disabled=false;button.textContent='חתום ושלח מחדש'}}
  }
  </script>
</body></html>`;
}

function renderSigningMessage(title, message) {
  return `<!doctype html><html lang="he" dir="rtl"><meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <body style="font-family:Arial;padding:40px;text-align:center;background:#f4f7fb">
  <h1>${escapeHtml(title)}</h1><p>${escapeHtml(message)}</p></body></html>`;
}

function safeHeaderFileName(value) {
  const name = normalizeString(value).replace(/[^\x20-\x7E]/g, "_");
  return (name || "document.pdf").replace(/["\\]/g, "_");
}

function formatSigningDate(date) {
  const parts = new Intl.DateTimeFormat("he-IL", {
    timeZone: "Asia/Jerusalem",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const values = Object.fromEntries(
      parts.map((part) => [part.type, part.value]),
  );
  return `${values.hour}:${values.minute} ` +
    `${values.day}/${values.month}/${values.year}`;
}

function drawRightAlignedPdfText(page, text, options) {
  const width = options.font.widthOfTextAtSize(text, options.size);
  page.drawText(text, {
    x: options.x - width,
    y: options.y,
    size: options.size,
    font: options.font,
    color: options.color,
  });
}

function drawCenteredPdfText(page, text, options) {
  const width = options.font.widthOfTextAtSize(text, options.size);
  page.drawText(text, {
    x: (page.getWidth() - width) / 2,
    y: options.y,
    size: options.size,
    font: options.font,
    color: options.color,
  });
}

function drawPdfParts(page, parts, options) {
  let x = options.x;
  for (const part of parts) {
    const text = normalizeString(part.text);
    const width = options.font.widthOfTextAtSize(text, options.size);
    page.drawText(text, {
      x,
      y: options.y,
      size: options.size,
      font: options.font,
      color: options.color,
    });
    x += width + (options.gap ?? 4);
  }
}

function drawCenteredPdfParts(page, parts, options) {
  const gap = options.gap ?? 4;
  const widths = parts.map((part) =>
    options.font.widthOfTextAtSize(
        normalizeString(part.text),
        options.size,
    ),
  );
  const totalWidth = widths.reduce((sum, width) => sum + width, 0) +
    gap * Math.max(0, parts.length - 1);
  drawPdfParts(page, parts, {
    ...options,
    x: (page.getWidth() - totalWidth) / 2,
    gap,
  });
}

function datesEqual(left, right) {
  if (!left && !right) return true;
  if (!left || !right) return false;
  return left.getTime() === right.getTime();
}

function defaultTitleForType(type) {
  switch (type) {
    case "document_signed":
      return "המסמך נחתם";
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
    case "document_signed":
      return "הלקוח חתם על המסמך";
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
    case "document_signed":
      return "chat";
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
