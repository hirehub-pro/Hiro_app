const fs = require("fs");
const path = require("path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} = require("firebase/firestore");

const emulatorAvailable = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
let testEnv;

test.before(async () => {
  if (!emulatorAvailable) return;
  testEnv = await initializeTestEnvironment({
    projectId: "hire-hub-fe6c4",
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "firestore.rules"),
          "utf8",
      ),
    },
  });
});

test.after(async () => {
  if (testEnv) await testEnv.cleanup();
});

async function seed(pathValue, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), pathValue), data);
  });
}

function validUser(uid, role = "customer") {
  return {
    uid,
    name: "Test User",
    role,
    createdAt: serverTimestamp(),
    email: "test@example.com",
    phone: "+972500000000",
  };
}

function validInvoice(invoiceId, sequenceNumber = 1) {
  return {
    type: "invoice",
    docType: "invoice",
    invoiceDocId: invoiceId,
    invoiceNumber: `2026-${String(sequenceNumber).padStart(4, "0")}`,
    sequenceNumber,
    amount: 118,
    vatAmount: 18,
    createdAt: serverTimestamp(),
  };
}

test("denies public and cross-user private account reads", {
  skip: !emulatorAvailable,
}, async () => {
  await seed("users/alice-user-id-000001", {
    uid: "alice-user-id-000001",
    name: "Alice",
    role: "customer",
    email: "alice@example.com",
    createdAt: new Date(),
  });
  const unauth = testEnv.unauthenticatedContext().firestore();
  const bob = testEnv.authenticatedContext("bob-user-id-00000002").firestore();
  await assertFails(getDoc(doc(unauth, "users/alice-user-id-000001")));
  await assertFails(getDoc(doc(bob, "users/alice-user-id-000001")));
});

test("exposes visible profiles while protecting server-managed fields", {
  skip: !emulatorAvailable,
}, async () => {
  await seed("publicWorkerProfiles/visible-worker", {
    uid: "visible-worker",
    name: "Visible Worker",
    professions: ["Electrician"],
    isSearchVisible: true,
  });
  await seed("publicWorkerProfiles/hidden-worker", {
    uid: "hidden-worker",
    name: "Hidden Worker",
    professions: ["Electrician"],
    isSearchVisible: false,
  });
  await seed("publicWorkerProfiles/schedule-hidden-worker", {
    uid: "schedule-hidden-worker",
    name: "Schedule Hidden Worker",
    professions: ["Electrician"],
    isSearchVisible: true,
  });
  await seed("publicWorkerProfiles/visible-worker/Schedule/info", {
    hideSchedule: false,
    disabledDays: [6, 7],
    availableDates: [],
    vacations: [],
  });
  await seed("publicWorkerProfiles/hidden-worker/Schedule/info", {
    hideSchedule: true,
    disabledDays: [7],
  });
  await seed("publicWorkerProfiles/schedule-hidden-worker/Schedule/info", {
    hideSchedule: true,
    disabledDays: [7],
  });
  await seed("publicWorkerProfiles/visible-worker/reviews/reviewer-1", {
    userId: "reviewer-user-id-00001",
    profession: "Electrician",
    rating: 5,
    priceRating: 5,
    workRating: 5,
    professionalismRating: 5,
    comment: "Great",
    imageUrls: [],
    timestamp: new Date(),
  });
  await seed("publicWorkerProfiles/visible-worker/projects/project-1", {
    description: "A public portfolio project",
    imageUrl: "https://example.com/project.jpg",
    imageUrls: ["https://example.com/project.jpg"],
    mediaTypes: ["image"],
    hasVideo: false,
    likesCount: 0,
    commentsCount: 1,
    timestamp: new Date(),
  });
  await seed(
      "publicWorkerProfiles/visible-worker/projects/project-1/comments/comment-1",
      {
        userId: "commenter-user-id-00001",
        userName: "Commenter",
        userImage: "",
        text: "Public comment",
        timestamp: new Date(),
      },
  );
  await seed("publicWorkerProfiles/hidden-worker/projects/project-1", {
    description: "Hidden portfolio project",
    timestamp: new Date(),
  });

  const unauth = testEnv.unauthenticatedContext().firestore();
  const customer = testEnv.authenticatedContext(
      "customer-user-id-00001",
  ).firestore();
  await assertSucceeds(getDoc(
      doc(unauth, "publicWorkerProfiles/visible-worker"),
  ));
  await assertSucceeds(getDoc(doc(
      unauth,
      "publicWorkerProfiles/visible-worker/projects/project-1",
  )));
  await assertSucceeds(getDocs(collection(
      unauth,
      "publicWorkerProfiles/visible-worker/projects",
  )));
  await assertSucceeds(getDoc(doc(
      unauth,
      "publicWorkerProfiles/visible-worker/reviews/reviewer-1",
  )));
  await assertSucceeds(getDocs(collection(
      unauth,
      "publicWorkerProfiles/visible-worker/reviews",
  )));
  await assertSucceeds(getDoc(doc(
      unauth,
      "publicWorkerProfiles/visible-worker/projects/project-1/comments/comment-1",
  )));
  await assertFails(getDoc(doc(
      unauth,
      "publicWorkerProfiles/hidden-worker/projects/project-1",
  )));
  await assertSucceeds(getDoc(
      doc(customer, "publicWorkerProfiles/visible-worker"),
  ));
  await assertFails(getDoc(
      doc(customer, "publicWorkerProfiles/hidden-worker"),
  ));
  await assertSucceeds(getDocs(query(
      collection(customer, "publicWorkerProfiles"),
      where("isSearchVisible", "==", true),
  )));
  await assertFails(getDocs(collection(customer, "publicWorkerProfiles")));
  await assertSucceeds(getDoc(doc(
      customer,
      "publicWorkerProfiles/visible-worker/Schedule/info",
  )));
  await assertFails(getDoc(doc(
      customer,
      "publicWorkerProfiles/hidden-worker/Schedule/info",
  )));
  await assertFails(getDoc(doc(
      customer,
      "publicWorkerProfiles/schedule-hidden-worker/Schedule/info",
  )));
  await assertSucceeds(getDoc(doc(
      customer,
      "publicWorkerProfiles/visible-worker/reviews/reviewer-1",
  )));
  await assertFails(updateDoc(
      doc(customer, "publicWorkerProfiles/visible-worker"),
      {avgRating: 5},
  ));
  await assertSucceeds(setDoc(doc(
      customer,
      "publicWorkerProfiles/visible-worker/projects/project-1/comments/customer-comment",
  ), {
    userId: "customer-user-id-00001",
    userName: "Customer",
    userImage: "",
    text: "Looks great",
    timestamp: serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(
      customer,
      "publicWorkerProfiles/visible-worker/projects/project-1/likes/customer-user-id-00001",
  ), {
    userId: "customer-user-id-00001",
    timestamp: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(
      customer,
      "publicWorkerProfiles/visible-worker/projects/forged-project",
  ), {
    description: "Not my project",
    timestamp: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(
      customer,
      "publicWorkerProfiles/visible-worker/projects/project-1/comments/customer-comment",
  ), {
    userId: "different-user-id-00001",
  }));
});

test("allows guests to read blogs and profession catalogs only", {
  skip: !emulatorAvailable,
}, async () => {
  await seed("blog_posts/public-post", {
    authorUid: "author-user-id-000001",
    text: "Public community post",
    timestamp: new Date(),
  });
  await seed("blog_posts/public-post/blog_comments/public-comment", {
    authorUid: "author-user-id-000001",
    text: "Public comment",
    timestamp: new Date(),
  });
  await seed("metadata/professions", {
    items: [{en: "Electrician"}],
  });
  await seed("metadata/system", {privateSetting: true});

  const guest = testEnv.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(guest, "blog_posts/public-post")));
  await assertSucceeds(getDoc(doc(
      guest,
      "blog_posts/public-post/blog_comments/public-comment",
  )));
  await assertSucceeds(getDoc(doc(guest, "metadata/professions")));
  await assertFails(getDoc(doc(guest, "metadata/system")));
  await assertFails(updateDoc(doc(guest, "blog_posts/public-post"), {
    text: "Guest edit",
  }));
});

test("allows an owner account but blocks self-assigned privilege", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "owner-user-id-0000001";
  const db = testEnv.authenticatedContext(uid).firestore();
  await assertSucceeds(setDoc(doc(db, `users/${uid}`), validUser(uid)));
  await assertSucceeds(updateDoc(doc(db, `users/${uid}`), {name: "Updated User"}));
  await assertSucceeds(updateDoc(doc(db, `users/${uid}`), {
    socialLinks: [{
      type: "website",
      name: "Website",
      url: "https://example.com",
    }, {
      type: "instagram",
      name: "",
      url: "https://instagram.com/example",
    }],
  }));
  await assertFails(updateDoc(doc(db, `users/${uid}`), {role: "admin"}));
  await assertFails(updateDoc(doc(db, `users/${uid}`), {
    isSubscribed: true,
    subscriptionStatus: "active",
  }));
  await assertFails(setDoc(
      doc(db, `users/${uid}/verification_info/latest`),
      {
        userId: uid,
        businessId: "515283737",
        businessVerificationStatus: "pending",
        timestamp: serverTimestamp(),
      },
  ));

  const attackerUid = "attacker-user-id-0001";
  const attacker = testEnv.authenticatedContext(attackerUid).firestore();
  await assertFails(setDoc(
      doc(attacker, `users/${attackerUid}`),
      validUser(attackerUid, "admin"),
  ));
});

test("allows inactive worker registration but rejects forged entitlement", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "new-worker-id-00000001";
  const db = testEnv.authenticatedContext(uid).firestore();
  const workerAccount = {
    uid,
    role: "worker",
    createdAt: serverTimestamp(),
  };
  const publicWorker = {
    uid,
    role: "worker",
    name: "Test Worker",
    email: "worker@example.com",
    phone: "+972500000000",
    town: "Tel Aviv-Yafo",
    lat: 32.0852999,
    lng: 34.7817676,
    profileImageUrl: "",
    professions: ["Electrician", "Plumber", "Air Conditioning"],
    spokenLanguages: ["Hebrew", "Arabic", "English"],
    optionalPhone: "",
    description: "Residential electrical services and installations",
    workRadius: 15000,
    updatedAt: serverTimestamp(),
  };

  await assertSucceeds(setDoc(doc(db, `users/${uid}`), workerAccount));
  await assertSucceeds(setDoc(
      doc(db, `publicWorkerProfiles/${uid}`),
      publicWorker,
  ));
  await assertSucceeds(updateDoc(doc(db, `publicWorkerProfiles/${uid}`), {
    optionalPhone: "+972511111111",
    lat: 32.085312345,
    lng: 34.781812345,
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(db, `publicWorkerProfiles/${uid}`), {
    socialLinks: [{
      type: "website",
      name: "My website",
      url: "https://worker.example.com",
    }, {
      type: "instagram",
      name: "",
      url: "https://instagram.com/test-worker",
    }],
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(db, `publicWorkerProfiles/${uid}`), {
    socialLinks: [{
      type: "website",
      name: "Insecure website",
      url: "http://worker.example.com",
    }],
  }));
  await assertFails(updateDoc(doc(db, `publicWorkerProfiles/${uid}`), {
    isSearchVisible: true,
  }));
  await assertFails(updateDoc(doc(db, `publicWorkerProfiles/${uid}`), {
    hideSchedule: false,
  }));
  await assertFails(updateDoc(doc(db, `publicWorkerProfiles/${uid}`), {
    isInsured: true,
  }));
  await assertSucceeds(setDoc(doc(db, `publicWorkerProfiles/${uid}/Schedule/info`), {
    hideSchedule: false,
    disabledDays: [6, 7],
    defaultWorkingHours: {from: "08:00", to: "16:00"},
  }));

  const attackerUid = "forged-worker-id-000001";
  const attacker = testEnv.authenticatedContext(attackerUid).firestore();
  await assertFails(setDoc(doc(attacker, `users/${attackerUid}`), {
    uid: attackerUid,
    role: "worker",
    createdAt: serverTimestamp(),
    isSubscribed: true,
    subscriptionStatus: "active",
  }));
});

test("stores favorites only as the owner's private bookmark", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "favorite-owner-id-000001";
  const targetUid = "favorite-worker-id-00001";
  const db = testEnv.authenticatedContext(uid).firestore();

  await assertSucceeds(setDoc(
      doc(db, `users/${uid}/favorites/${targetUid}`),
      {
        targetUid,
        addedAt: serverTimestamp(),
        name: "Favorite Worker",
        profileImageUrl: "https://example.com/worker.jpg",
        professions: ["Electrician"],
        spokenLanguages: ["Hebrew"],
      },
  ));
  await assertFails(setDoc(
      doc(db, `users/${targetUid}/likedBy/${uid}`),
      {addedAt: serverTimestamp(), sourceUserId: uid},
  ));
  await assertFails(setDoc(
      doc(db, `users/${uid}/favorites/${targetUid}`),
      {addedAt: serverTimestamp(), name: "Missing identity"},
  ));
});

test("blocks cross-user invoices and protected allocation fields", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "invoice-owner-id-00001";
  const otherUid = "other-user-id-00000001";
  const owner = testEnv.authenticatedContext(uid).firestore();
  const other = testEnv.authenticatedContext(otherUid).firestore();
  const invoiceId = "invoice_2026-0001";
  const ref = doc(owner, `users/${uid}/invoices/${invoiceId}`);
  await seed(`users/${uid}/invoices/${invoiceId}`, validInvoice(invoiceId));
  await assertFails(getDoc(doc(other, `users/${uid}/invoices/${invoiceId}`)));
  await assertFails(updateDoc(ref, {documentStatus: "finalized"}));
  await assertFails(updateDoc(ref, {allocationNumber: "FAKE-1"}));
  await assertFails(updateDoc(ref, {
    taxInvoicePresentation: {clientEmail: "attacker@example.com"},
  }));
  await assertFails(updateDoc(ref, {
    taxAuthorityDecision: {decision: "continue", status: "accepted"},
  }));

  const fakeId = "invoice_2026-0002";
  await assertFails(setDoc(doc(owner, `users/${uid}/invoices/${fakeId}`), {
    ...validInvoice(fakeId, 2),
    taxAuthorityAllocationRequest: {status: "approved"},
  }));
  await assertFails(setDoc(doc(owner, `users/${uid}/invoices/quote_fake`), {
    type: "quote",
    docType: "quote",
    invoiceDocId: "quote_fake",
    createdAt: serverTimestamp(),
    serverDocument: {status: "finalized", generatedBy: "server"},
  }));

  const finalizedId = "invoice_2026-0003";
  await seed(`users/${uid}/invoices/${finalizedId}`, {
    ...validInvoice(finalizedId, 3),
    documentStatus: "finalized",
    taxAuthorityAllocationRequest: {status: "finalized"},
    allocationNumber: "SERVER-ALLOCATION",
    serverDocument: {status: "finalized", generatedBy: "server"},
    storagePath: `invoices/${uid}/tax_invoice_2026-0003.pdf`,
    fileName: "tax_invoice_2026-0003.pdf",
    url: "https://example.com/server-document.pdf",
  });
  await assertFails(updateDoc(
      doc(owner, `users/${uid}/invoices/${finalizedId}`),
      {storagePath: `invoices/${uid}/replacement.pdf`},
  ));
});

test("rejects foreign invoice storage paths", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "storage-owner-id-00001";
  const db = testEnv.authenticatedContext(uid).firestore();
  const invoiceId = "quote_2026-0001";
  await assertFails(setDoc(doc(db, `users/${uid}/invoices/${invoiceId}`), {
    type: "quote",
    docType: "quote",
    invoiceDocId: invoiceId,
    storagePath: "invoices/another-user/stolen.pdf",
    createdAt: serverTimestamp(),
  }));
});

test("denies client document creation and all counter changes", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "counter-owner-id-00001";
  const db = testEnv.authenticatedContext(uid).firestore();
  const counterPath = `users/${uid}/counters/document_counter_invoice`;
  await assertFails(setDoc(doc(db, counterPath), {
    value: 1,
    docType: "invoice",
    updatedAt: serverTimestamp(),
  }));
  await seed(counterPath, {
    value: 1,
    docType: "invoice",
    updatedAt: new Date(),
    initializedAt: new Date(),
  });
  await assertFails(updateDoc(doc(db, counterPath), {
    value: 5000,
    updatedAt: serverTimestamp(),
  }));

  const invoiceId = "invoice_2026-0001";
  const batch = writeBatch(db);
  batch.set(
      doc(db, `users/${uid}/invoices/${invoiceId}`),
      validInvoice(invoiceId),
  );
  batch.update(doc(db, counterPath), {
    value: 2,
    docType: "invoice",
    lastInvoiceDocId: invoiceId,
    lastSequenceNumber: 1,
    updatedAt: serverTimestamp(),
  });
  await assertFails(batch.commit());
  await assertFails(updateDoc(doc(db, counterPath), {
    value: 3,
    docType: "invoice",
    lastInvoiceDocId: invoiceId,
    lastSequenceNumber: 2,
    updatedAt: serverTimestamp(),
  }));
});

test("keeps OAuth and verification secrets inaccessible to clients", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "secret-owner-id-000001";
  const db = testEnv.authenticatedContext(uid).firestore();
  await assertFails(getDoc(doc(db, `users/${uid}/tax_authority/oauth`)));
  await assertFails(getDoc(doc(db, `taxAuthorityOAuthTokens/${uid}`)));
  await assertFails(getDoc(doc(db, `taxAuthorityUniformOAuthTokens/${uid}`)));
  await assertFails(setDoc(doc(db, `users/${uid}/invoiceBuilderVerifications/emailCode`), {
    codeHash: "fake",
  }));
});

test("allows owners to read but not forge uniform submission status", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "uniform-owner-id-000001";
  const otherUid = "uniform-other-id-000001";
  const pathValue = `users/${uid}/uniformTaxSubmissions/submission-1`;
  await seed(pathValue, {
    status: "approved",
    authorityUniqueId: "123456789012345678901",
  });
  const ownerDb = testEnv.authenticatedContext(uid).firestore();
  const otherDb = testEnv.authenticatedContext(otherUid).firestore();
  await assertSucceeds(getDoc(doc(ownerDb, pathValue)));
  await assertFails(getDoc(doc(otherDb, pathValue)));
  await assertFails(setDoc(doc(ownerDb, pathValue), {status: "approved"}));
});

test("enforces invoice-builder lock ownership and expiry", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "lock-owner-id-000000001";
  const db = testEnv.authenticatedContext(uid).firestore();
  const lockRef = doc(db, `users/${uid}/invoice_builder_lock/active`);
  const futureExpiry = () => Timestamp.fromMillis(Date.now() + 60000);

  await assertSucceeds(setDoc(lockRef, {
    ownerUid: uid,
    sessionId: "session-a-0000000000000001",
    deviceId: "device-a-0000000000000001",
    acquiredAt: serverTimestamp(),
    expiresAt: futureExpiry(),
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(lockRef, {
    expiresAt: futureExpiry(),
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(lockRef, {
    sessionId: "session-b-0000000000000002",
    deviceId: "device-b-0000000000000002",
    acquiredAt: serverTimestamp(),
    expiresAt: futureExpiry(),
    updatedAt: serverTimestamp(),
  }));

  await assertSucceeds(updateDoc(lockRef, {
    sessionId: "session-c-0000000000000003",
    deviceId: "device-a-0000000000000001",
    acquiredAt: serverTimestamp(),
    expiresAt: futureExpiry(),
    updatedAt: serverTimestamp(),
  }));

  await assertFails(updateDoc(lockRef, {
    sessionId: "session-d-0000000000000004",
    deviceId: "device-b-0000000000000002",
    acquiredAt: serverTimestamp(),
    expiresAt: futureExpiry(),
    updatedAt: serverTimestamp(),
  }));

  await seed(`users/${uid}/invoice_builder_lock/active`, {
    ownerUid: uid,
    sessionId: "expired-session-00000000001",
    deviceId: "expired-device-00000000001",
    acquiredAt: new Date(Date.now() - 120000),
    expiresAt: new Date(Date.now() - 60000),
    updatedAt: new Date(Date.now() - 60000),
  });
  await assertSucceeds(setDoc(lockRef, {
    ownerUid: uid,
    sessionId: "session-b-0000000000000002",
    deviceId: "device-b-0000000000000002",
    acquiredAt: serverTimestamp(),
    expiresAt: futureExpiry(),
    updatedAt: serverTimestamp(),
  }));
});

test("allows chat participants and denies outsiders", {
  skip: !emulatorAvailable,
}, async () => {
  const alice = "chat-alice-id-0000001";
  const bob = "chat-bob-id-000000003";
  const eve = "chat-eve-id-000000003";
  const roomId = "room-alice-bob";
  const aliceDb = testEnv.authenticatedContext(alice).firestore();
  await assertSucceeds(setDoc(doc(aliceDb, `chat_rooms/${roomId}`), {
    users: [alice, bob],
    lastMessage: "",
  }));
  await assertSucceeds(setDoc(
      doc(aliceDb, `chat_rooms/${roomId}/messages/message-1`),
      {senderId: alice, receiverId: bob, text: "Hello", timestamp: serverTimestamp()},
  ));
  const eveDb = testEnv.authenticatedContext(eve).firestore();
  await assertFails(getDoc(doc(eveDb, `chat_rooms/${roomId}`)));
});

test("allows chat presence fields and the app review payload", {
  skip: !emulatorAvailable,
}, async () => {
  const reviewer = "reviewer-user-id-00001";
  const worker = "review-worker-id-000001";
  const reviewerDb = testEnv.authenticatedContext(reviewer).firestore();
  await seed(`users/${reviewer}`, {
    uid: reviewer,
    name: "Reviewer",
    role: "customer",
    createdAt: new Date(),
  });
  await seed(`users/${worker}`, {
    uid: worker,
    name: "Worker",
    role: "worker",
    createdAt: new Date(),
  });

  await assertSucceeds(updateDoc(doc(reviewerDb, `users/${reviewer}`), {
    activeChatWith: worker,
    activeChatUpdatedAt: serverTimestamp(),
    isInChatPage: true,
  }));
  await assertSucceeds(setDoc(
      doc(reviewerDb, `publicWorkerProfiles/${worker}/reviews/${reviewer}`),
      {
        userId: reviewer,
        userName: "Reviewer",
        profession: "Electrician",
        rating: 4.5,
        priceRating: 4,
        workRating: 5,
        professionalismRating: 4.5,
        comment: "Excellent work",
        imageUrls: [],
        timestamp: serverTimestamp(),
      },
  ));
  await assertFails(setDoc(
      doc(reviewerDb, `publicWorkerProfiles/${worker}/reviews/forged-review-id`),
      {
        userId: reviewer,
        userName: "Reviewer",
        profession: "Electrician",
        rating: 5,
        priceRating: 5,
        workRating: 5,
        professionalismRating: 5,
        comment: "Forged duplicate",
        imageUrls: [],
        timestamp: serverTimestamp(),
      },
  ));
});

test("allows reporters to list only their own reports", {
  skip: !emulatorAvailable,
}, async () => {
  const alice = "report-alice-id-000001";
  const bob = "report-bob-id-00000003";
  await seed("reports/alice-report", {
    reporterId: alice,
    reportedId: "app",
    reportType: "user_report",
    reason: "Login problem",
    status: "open",
    timestamp: new Date(),
  });
  await seed("reports/bob-report", {
    reporterId: bob,
    reportedId: "app",
    reportType: "user_report",
    reason: "Payment problem",
    status: "open",
    timestamp: new Date(),
  });

  const aliceDb = testEnv.authenticatedContext(alice).firestore();
  await assertSucceeds(getDoc(doc(aliceDb, "reports/alice-report")));
  await assertFails(getDoc(doc(aliceDb, "reports/bob-report")));
  await assertSucceeds(getDocs(query(
      collection(aliceDb, "reports"),
      where("reporterId", "==", alice),
  )));
  await assertFails(getDocs(collection(aliceDb, "reports")));
});

test("allows a customer to create a validated work request for its worker", {
  skip: !emulatorAvailable,
}, async () => {
  const customer = "request-customer-id-001";
  const worker = "request-worker-id-00001";
  const requestId = "request-document-1";
  const incomingId = "incoming-document-1";
  const customerDb = testEnv.authenticatedContext(customer).firestore();
  const workerDb = testEnv.authenticatedContext(worker).firestore();
  const requestData = {
    requestId,
    workerId: worker,
    workerName: "Worker",
    workerNotificationId: "worker-notification-1",
    workerRequestToMeId: incomingId,
    type: "work_request",
    fromId: customer,
    fromName: "Customer",
    jobDescription: "Install a light fixture",
    images: [],
    timestamp: serverTimestamp(),
    status: "pending",
    title: "Work Request",
    body: "A customer sent a work request.",
  };

  const batch = writeBatch(customerDb);
  batch.set(
      doc(customerDb, `users/${customer}/requests/${requestId}`),
      requestData,
  );
  batch.set(
      doc(customerDb, `users/${worker}/RequestToMe/${incomingId}`),
      requestData,
  );
  await assertSucceeds(batch.commit());
  await assertSucceeds(getDoc(
      doc(workerDb, `users/${worker}/RequestToMe/${incomingId}`),
  ));
});

test("allows a customer to notify a worker after editing a reviewed request", {
  skip: !emulatorAvailable,
}, async () => {
  const customer = "edit-customer-id-000001";
  const worker = "edit-worker-id-000000001";
  const requestId = "reviewed-request-1";
  const incomingId = "reviewed-incoming-1";
  const originalNotificationId = "reviewed-notification-1";
  const editedNotificationId = "edited-notification-1";
  const reviewedAt = new Date();
  const requestData = {
    requestId,
    workerId: worker,
    workerName: "Worker",
    workerNotificationId: originalNotificationId,
    workerRequestToMeId: incomingId,
    type: "work_request",
    fromId: customer,
    fromName: "Customer",
    jobDescription: "Original details",
    images: [],
    date: "2026-8-25",
    requestedFrom: "08:00",
    requestedTo: "16:00",
    timestamp: new Date(),
    status: "pending",
    title: "Work Request",
    body: "A customer sent a work request.",
    reviewedAt,
    reviewedBy: worker,
  };
  await seed(`users/${customer}/requests/${requestId}`, requestData);
  await seed(`users/${worker}/RequestToMe/${incomingId}`, requestData);
  await seed(
      `users/${worker}/notifications/${originalNotificationId}`,
      requestData,
  );

  const customerDb = testEnv.authenticatedContext(customer).firestore();
  const updates = {
    jobDescription: "Edited details",
    updatedAt: serverTimestamp(),
  };
  const batch = writeBatch(customerDb);
  batch.update(
      doc(customerDb, `users/${customer}/requests/${requestId}`),
      updates,
  );
  batch.update(
      doc(customerDb, `users/${worker}/RequestToMe/${incomingId}`),
      updates,
  );
  batch.update(
      doc(customerDb, `users/${worker}/notifications/${originalNotificationId}`),
      updates,
  );
  batch.set(
      doc(customerDb, `users/${worker}/notifications/${editedNotificationId}`),
      {
        ...requestData,
        jobDescription: "Edited details",
        type: "request_edited",
        requestType: "work_request",
        title: "בקשה שצפית בה עודכנה",
        body: "הלקוח ערך את פרטי הבקשה לאחר שצפית בה.",
        isRead: false,
        timestamp: serverTimestamp(),
        updatedAt: serverTimestamp(),
      },
  );
  await assertSucceeds(batch.commit());
});

test("validates community author identity and content size", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "blog-author-id-0000001";
  const db = testEnv.authenticatedContext(uid).firestore();
  await assertSucceeds(setDoc(doc(db, "blog_posts/post-1"), {
    authorUid: uid,
    title: "A valid post",
    content: "Hello",
    likes: 0,
    likedBy: {},
    timestamp: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(db, "blog_posts/post-2"), {
    authorUid: "someone-else",
    title: "Spoofed",
    content: "Hello",
    timestamp: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(db, "blog_posts/post-3"), {
    authorUid: uid,
    title: "Oversized",
    content: "x".repeat(10001),
    timestamp: serverTimestamp(),
  }));

  const likerUid = "blog-liker-id-00000001";
  const likerDb = testEnv.authenticatedContext(likerUid).firestore();
  await assertSucceeds(updateDoc(doc(likerDb, "blog_posts/post-1"), {
    likes: 1,
    likedBy: {[likerUid]: true},
  }));
  await assertFails(updateDoc(doc(likerDb, "blog_posts/post-1"), {
    content: "A liker cannot edit the author's post",
  }));
  await assertFails(updateDoc(doc(likerDb, "blog_posts/post-1"), {
    likes: 99,
    likedBy: {[likerUid]: true},
  }));

  const commentRef = doc(db, "blog_posts/post-1/blog_comments/comment-1");
  await assertSucceeds(setDoc(commentRef, {
    authorUid: uid,
    authorName: "Author",
    text: "A valid comment",
    isBid: false,
    timestamp: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(commentRef, {
    text: "An edited comment",
    updatedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(
      doc(db, "blog_posts/post-1/blog_comments/null-fields"),
      {
        authorUid: uid,
        text: "Invalid null bid",
        bidPrice: null,
        timestamp: serverTimestamp(),
      },
  ));
  await assertFails(setDoc(
      doc(db, "blog_posts/post-1/blog_comments/string-bid"),
      {
        authorUid: uid,
        text: "Invalid string bid",
        bidPrice: "250",
        timestamp: serverTimestamp(),
      },
  ));
  await assertSucceeds(setDoc(
      doc(db, "blog_posts/post-1/blog_comments/numeric-bid"),
      {
        authorUid: uid,
        text: "Valid numeric bid",
        bidPrice: 250,
        isBid: true,
        timestamp: serverTimestamp(),
      },
  ));
});

test("permits custom-claim admins without trusting a user role field", {
  skip: !emulatorAvailable,
}, async () => {
  await seed("users/private-user-id-0001", {
    uid: "private-user-id-0001",
    name: "Private",
    role: "customer",
    createdAt: new Date(),
  });
  const adminDb = testEnv.authenticatedContext(
      "admin-user-id-0000001",
      {admin: true},
  ).firestore();
  await assertSucceeds(getDoc(doc(adminDb, "users/private-user-id-0001")));
  assert.ok(true);
});

test("permits protected admin-panel reads for a server-assigned admin role", {
  skip: !emulatorAvailable,
}, async () => {
  const adminUid = "stored-admin-id-00000001";
  await seed(`users/${adminUid}`, {
    uid: adminUid,
    name: "Stored Admin",
    role: "admin",
    createdAt: new Date(),
  });
  await seed("users/customer-for-admin-001", {
    uid: "customer-for-admin-001",
    name: "Customer",
    role: "customer",
    createdAt: new Date(),
  });
  await seed("users/worker-for-admin-0001", {
    uid: "worker-for-admin-0001",
    role: "worker",
    createdAt: new Date(),
  });
  await seed("publicWorkerProfiles/worker-for-admin-0001", {
    uid: "worker-for-admin-0001",
    role: "worker",
    name: "Worker",
    isSearchVisible: false,
  });
  await seed("users/worker-for-admin-0001/verification_info/latest", {
    userId: "worker-for-admin-0001",
    businessVerificationStatus: "pending",
    timestamp: new Date(),
  });

  const adminDb = testEnv.authenticatedContext(adminUid).firestore();
  await assertSucceeds(getDocs(query(
      collection(adminDb, "users"),
      where("role", "==", "customer"),
  )));
  await assertSucceeds(getDocs(query(
      collection(adminDb, "users"),
      where("role", "==", "worker"),
  )));
  await assertSucceeds(getDoc(doc(
      adminDb,
      "publicWorkerProfiles/worker-for-admin-0001",
  )));
  await assertSucceeds(getDoc(doc(
      adminDb,
      "users/worker-for-admin-0001/verification_info/latest",
  )));
});
