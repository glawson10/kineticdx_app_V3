/**
 * CP-P1 Commit 19: Firestore security rules tests for settings and public.
 * Run with: firebase emulators:start --only firestore (in one terminal)
 *          then: cd test/firestore_rules && npm test
 * Or: firebase emulators:exec --only firestore "cd test/firestore_rules && npm test"
 */

const path = require("path");
const fs = require("fs");

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

const { setDoc, getDoc, doc } = require("firebase/firestore");

const PROJECT_ID = "demo-settings-rules";
const CLINIC_ID = "c1";

let testEnv;

beforeAll(async () => {
  const rulesPath = path.join(__dirname, "../../firestore.rules");
  const rules = fs.readFileSync(rulesPath, "utf8");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules,
      host: "127.0.0.1",
      port: 8080,
    },
  });
}, 20000);

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

afterEach(async () => {
  if (testEnv) await testEnv.clearFirestore();
});

async function seedMember(db, uid, permissions) {
  const memberRef = doc(db, "clinics", CLINIC_ID, "members", uid);
  await setDoc(memberRef, {
    active: true,
    permissions: permissions || { "settings.read": true },
  });
}

describe("Settings & public rules (Commit 19)", () => {
  describe("Public is read-only", () => {
    it("unauthenticated can read clinics/{clinicId}/public/config (e.g. publicBooking)", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        const publicRef = doc(db, "clinics", CLINIC_ID, "public", "config", "publicBooking", "config");
        await setDoc(publicRef, { slotStepMinutes: 15 });
      });
      const unauth = testEnv.unauthenticatedContext();
      const db = unauth.firestore();
      const publicRef = doc(db, "clinics", CLINIC_ID, "public", "config", "publicBooking", "config");
      await assertSucceeds(getDoc(publicRef));
    });

    it("any client write to clinics/{clinicId}/public/** is denied", async () => {
      const uid = "user1";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await seedMember(db, uid, { "settings.read": true, "settings.write": true });
      });
      const auth = testEnv.authenticatedContext(uid);
      const db = auth.firestore();
      const publicRef = doc(db, "clinics", CLINIC_ID, "public", "config");
      await assertFails(setDoc(publicRef, { foo: "bar" }));
    });
  });

  describe("Locations are callable-only", () => {
    it("settings.read user can read clinics/{clinicId}/locations/*", async () => {
      const uid = "settingsReadUser";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await seedMember(db, uid, { "settings.read": true });
        const locRef = doc(db, "clinics", CLINIC_ID, "locations", "loc1");
        await setDoc(locRef, { name: "Main", active: true });
      });
      const auth = testEnv.authenticatedContext(uid);
      const db = auth.firestore();
      const locRef = doc(db, "clinics", CLINIC_ID, "locations", "loc1");
      await assertSucceeds(getDoc(locRef));
    });

    it("settings.write user cannot write locations from client", async () => {
      const uid = "settingsWriteUser";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await seedMember(db, uid, { "settings.read": true, "settings.write": true });
      });
      const auth = testEnv.authenticatedContext(uid);
      const db = auth.firestore();
      const locRef = doc(db, "clinics", CLINIC_ID, "locations", "loc1");
      await assertFails(setDoc(locRef, { name: "New", active: true }));
    });
  });

  describe("Appointment types are callable-only", () => {
    it("settings.read user can read appointmentTypes", async () => {
      const uid = "settingsReadUser";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await seedMember(db, uid, { "settings.read": true });
        const atRef = doc(db, "clinics", CLINIC_ID, "appointmentTypes", "at1");
        await setDoc(atRef, { label: "Consult", durationMinutes: 30 });
      });
      const auth = testEnv.authenticatedContext(uid);
      const db = auth.firestore();
      const atRef = doc(db, "clinics", CLINIC_ID, "appointmentTypes", "at1");
      await assertSucceeds(getDoc(atRef));
    });

    it("client write to appointmentTypes denied even with settings.write", async () => {
      const uid = "settingsWriteUser";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await seedMember(db, uid, { "settings.read": true, "settings.write": true });
      });
      const auth = testEnv.authenticatedContext(uid);
      const db = auth.firestore();
      const atRef = doc(db, "clinics", CLINIC_ID, "appointmentTypes", "at1");
      await assertFails(setDoc(atRef, { label: "New", durationMinutes: 15 }));
    });
  });

  describe("Settings doc-specific write locks", () => {
    it("settings.write user can update clinics/{clinicId}/settings/someOtherDoc", async () => {
      const uid = "settingsWriteUser";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await seedMember(db, uid, { "settings.read": true, "settings.write": true });
        const ref = doc(db, "clinics", CLINIC_ID, "settings", "someOtherDoc");
        await setDoc(ref, { foo: "bar" });
      });
      const auth = testEnv.authenticatedContext(uid);
      const db = auth.firestore();
      const ref = doc(db, "clinics", CLINIC_ID, "settings", "someOtherDoc");
      await assertSucceeds(setDoc(ref, { foo: "baz" }, { merge: true }));
    });

    it("settings.write user cannot write settings/calendarDisplay", async () => {
      const uid = "settingsWriteUser";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await seedMember(db, uid, { "settings.read": true, "settings.write": true });
      });
      const auth = testEnv.authenticatedContext(uid);
      const db = auth.firestore();
      const ref = doc(db, "clinics", CLINIC_ID, "settings", "calendarDisplay");
      await assertFails(setDoc(ref, { displayStartHour: 8 }));
    });

    it("settings.write user cannot write settings/publicBooking", async () => {
      const uid = "settingsWriteUser";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await seedMember(db, uid, { "settings.read": true, "settings.write": true });
      });
      const auth = testEnv.authenticatedContext(uid);
      const db = auth.firestore();
      const ref = doc(db, "clinics", CLINIC_ID, "settings", "publicBooking");
      await assertFails(setDoc(ref, { slotStepMinutes: 10 }));
    });

    it("settings.write user cannot write settings/communication", async () => {
      const uid = "settingsWriteUser";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await seedMember(db, uid, { "settings.read": true, "settings.write": true });
      });
      const auth = testEnv.authenticatedContext(uid);
      const db = auth.firestore();
      const ref = doc(db, "clinics", CLINIC_ID, "settings", "communication");
      await assertFails(setDoc(ref, { defaultReminderChannel: "email" }));
    });

    it("settings.read-only user cannot write any settings doc", async () => {
      const uid = "settingsReadOnlyUser";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await seedMember(db, uid, { "settings.read": true });
      });
      const auth = testEnv.authenticatedContext(uid);
      const db = auth.firestore();
      const ref = doc(db, "clinics", CLINIC_ID, "settings", "someOtherDoc");
      await assertFails(setDoc(ref, { foo: "bar" }));
    });
  });
});
