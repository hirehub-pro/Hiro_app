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
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
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

test("allows an owner account but blocks self-assigned privilege", {
  skip: !emulatorAvailable,
}, async () => {
  const uid = "owner-user-id-0000001";
  const db = testEnv.authenticatedContext(uid).firestore();
  await assertSucceeds(setDoc(doc(db, `users/${uid}`), validUser(uid)));
  await assertSucceeds(updateDoc(doc(db, `users/${uid}`), {name: "Updated User"}));
  await assertFails(updateDoc(doc(db, `users/${uid}`), {role: "admin"}));

  const attackerUid = "attacker-user-id-0001";
  const attacker = testEnv.authenticatedContext(attackerUid).firestore();
  await assertFails(setDoc(
      doc(attacker, `users/${attackerUid}`),
      validUser(attackerUid, "admin"),
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
  await assertSucceeds(setDoc(ref, validInvoice(invoiceId)));
  await assertFails(getDoc(doc(other, `users/${uid}/invoices/${invoiceId}`)));
  await assertFails(updateDoc(ref, {documentStatus: "finalized"}));
  await assertFails(updateDoc(ref, {allocationNumber: "FAKE-1"}));

  const fakeId = "invoice_2026-0002";
  await assertFails(setDoc(doc(owner, `users/${uid}/invoices/${fakeId}`), {
    ...validInvoice(fakeId, 2),
    taxAuthorityAllocationRequest: {status: "approved"},
  }));
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

test("denies counter creation/reset and allows one invoice-bound increment", {
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
  await assertSucceeds(batch.commit());
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
  await assertFails(setDoc(doc(db, `users/${uid}/invoiceBuilderVerifications/emailCode`), {
    codeHash: "fake",
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
    likedBy: [],
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
    likedBy: [likerUid],
  }));
  await assertFails(updateDoc(doc(likerDb, "blog_posts/post-1"), {
    content: "A liker cannot edit the author's post",
  }));
  await assertFails(updateDoc(doc(likerDb, "blog_posts/post-1"), {
    likes: 99,
    likedBy: [likerUid],
  }));
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
