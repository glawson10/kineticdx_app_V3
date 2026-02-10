# Staff / Invites / Permissions — Cursor System Prompt (V3)

Use this document as a **single copy-paste system prompt** for a fresh Cursor chat when implementing or changing the Staff / Invites / Permissions system. This prompt is authoritative; if any requested change conflicts with these rules, stop and explain why.

---

## Staff / Invites / Permissions (V3 clinic-scoped, function-authoritative)

You are working in a Flutter + Firebase app using:

- Firebase Auth
- Firestore
- Cloud Functions

This system follows a strict **clinic-scoped, security-first, function-authoritative** architecture.

**This prompt is authoritative.**  
If any requested change conflicts with these rules, you must stop and explain why.

---

## 🔒 NON-NEGOTIABLE ARCHITECTURE RULES

- **All private data is clinic-scoped:** `clinics/{clinicId}/...`  
  There are no global patients, appointments, notes, intakes, or memberships.

- **Zero trust:**
  - UI is never trusted
  - Client code is never trusted
  - Auth alone never grants access
  - **Firestore Security Rules are the law** — if rules don't allow it, the feature does not exist.

- **Clinic access requires all three:**
  - Signed-in user
  - Active clinic membership document
  - Explicit permission flag (true)

- **Membership, invite, and permission writes are Cloud Functions only.**

- **Invite tokens:** Raw tokens are never stored; only secure hashes (e.g. SHA-256).

- **All membership and permission changes must emit clinic-scoped, append-only audit events** (if audit infra exists).

(Reference: canonical V3 architecture + function-authoritative rules)

---

## 🎯 GOAL

Implement a production-safe **Staff / Invites / Permissions** system so a clinic Owner / Manager can:

- View staff list
- Invite staff by email
- Assign role templates + explicit permission flags
- Allow staff to accept an invite and become active members
- Reliably gate UI and enforce access via Firestore rules

---

## 🧠 CORE ASSUMPTIONS

- Firebase Auth is used.
- A user may belong to multiple clinics.
- Clinic membership documents are the **single source of truth**.
- Roles are templates only — **permissions are always explicit**.

---

## 📁 DATA MODEL (CLINIC-SCOPED ONLY)

### Membership (Security Authority)

- **Path:** `clinics/{clinicId}/memberships/{uid}`
- **Fields (minimum):**
  - `clinicId`: string
  - `userId`: string
  - `email`: string
  - `role`: string // `owner` | `manager` | `practitioner` | `receptionist` | `billing` | `viewer`
  - `permissions`: {  
    `manageClinic`, `manageMembers`, `manageServices`, `managePatients`, `manageAppointments`, `viewClinical`, `editClinical`, `manageBilling` (all boolean)
  - `status`: `"invited"` | `"active"` | `"suspended"`
  - `createdAt`, `updatedAt`: Timestamp
  - `createdBy`: uid

### Optional user mirror (if already used)

- **Path:** `users/{uid}/memberships/{clinicId}`
- Minimal mirror only (status, role, permissions). **Never authoritative.** Written by Cloud Functions only.

### Invites (Function-only)

- **Path:** `clinics/{clinicId}/invites/{inviteId}`
- `clinicId`, `email`, `role`, `permissions`, `tokenHash` // sha256  
- `status` // active | accepted | revoked | expired  
- `expiresAt`, `createdAt`, `createdBy`: Timestamp  
- `acceptedAt?`, `acceptedBy?`

---

## ☁️ REQUIRED CLOUD FUNCTIONS (CALLABLE)

### 1️⃣ membership.inviteUser

- **Requires:** Caller is an active clinic member with `manageMembers = true`.
- **Input:** `clinicId`, `email`, `role`, `permissions?` (optional override, else derived from role template).
- **Behaviour:**
  - Normalize email (lowercase + trim).
  - Generate random invite token.
  - Store **hash only**.
  - Create invite document.
  - (Choose one approach and be consistent: **Option A:** create membership stub with `status = invited` | **Option B:** create membership only on acceptance.)
  - Emit audit event: `membership.invited`.
- **Output:** `inviteId`, `inviteLink` (raw token returned **only here**), `expiresAt`.

### 2️⃣ membership.acceptInvite

- **Requires:** Signed-in user.
- **Input:** `clinicId`, `token`.
- **Behaviour:**
  - Hash token and find matching invite within clinic.
  - Validate: not expired, not revoked, not already accepted.
  - Validate signed-in email matches invite email.
  - Create or activate membership: `status = active`, role + permissions from invite.
  - Write optional mirror doc.
  - Mark invite as accepted.
  - Emit audit event: `membership.accepted`.
- **Output:** `clinicId`, `membershipStatus`, `role`, `permissions`.

### 3️⃣ membership.updateMember

- **Requires:** `manageMembers = true`.
- **Input:** `clinicId`, `memberUid`, `patch` (role / permissions / status).
- **Rules:** Must prevent demoting or suspending the last active owner.
- Emit audit: `membership.updated`.

### 4️⃣ membership.suspendMember

- Preferred over delete. Set `status = suspended`. Access is immediately revoked. Emit audit event.

---

## 🔐 FIRESTORE SECURITY RULE REQUIREMENTS

- **Membership reads:** User can read their own membership; managers/owners can read all memberships (`manageMembers = true`).
- **Membership writes:** No client writes. Cloud Functions only (via project’s chosen allowlist / claim strategy).
- **Clinic settings writes:** Gated by `manageClinic = true`.

---

## 📱 FLUTTER UI REQUIREMENTS

- **Settings → Staff tab:** Visible only to members with `manageMembers`. List staff from `clinics/{clinicId}/memberships`. Invite staff (email input, role dropdown, optional permission checklist). Calls `membership.inviteUser`. Shows invite link with copy button. “Send email later” is acceptable.
- **Member detail:** Change role, toggle permissions, suspend / reactivate member.

---

## 🔑 FIRST LOGIN FLOW (STAFF)

- App never sets passwords. Staff receives invite link → signs in (or signs up) → accepts invite. Optional redirect to password reset.

---

## ✅ ACCEPTANCE TESTS (MANDATORY)

- Non-member cannot list staff.
- Member without `manageMembers` cannot invite or update.
- Raw invite tokens are never stored.
- Invite acceptance requires email match.
- Accepted staff gain access immediately.
- Suspended staff lose access everywhere.
- Last owner cannot be removed or demoted.

---

## 📦 DELIVERABLES

- **Cloud Functions:** inviteUser, acceptInvite, updateMember, suspendMember
- **Firestore rules** updates
- **Staff settings UI**
- **Invite acceptance screen / route**
- **Audit events** (clinic-scoped, append-only)

---

## 🧭 EXECUTION MODE

When implementing:

1. **Propose exact file list** to add/change.
2. **Implement Cloud Functions first**, then Firestore rules, then Flutter UI.
3. **Never refactor unrelated code.**
4. **If something is ambiguous — ask before changing architecture.**
