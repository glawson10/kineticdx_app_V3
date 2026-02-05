# Manual test checklist: Patient Uploads tab

## Prerequisites
- Deploy updated **firestore.rules** and **storage.rules** (and **firestore.indexes.json** if using Firestore indexes deploy).
- App signed in as a clinic member with at least **patients.read** or **clinical.read** to see the Uploads tab; **patients.write** to upload/delete.
- At least one patient in the clinic (edit mode).

---

## 1. Tab visibility and permissions
- [ ] Open **Patients** → select a patient (edit). Confirm **Details** and **Uploads** tabs appear in the app bar.
- [ ] Sign in as a member with **patients.read** but without **patients.write**. Open a patient. Confirm **Uploads** tab is visible; list loads; **no** upload FAB and **no** delete on items.
- [ ] Sign in as a member with **patients.write**. Confirm upload FAB and delete icon on each upload are visible and work.

---

## 2. Upload
- [ ] **Camera**: Tap upload → Camera → take photo. Confirm file uploads and appears in the list (name, size, date).
- [ ] **Gallery**: Tap upload → Gallery → pick image (JPG/PNG). Confirm upload and list update.
- [ ] **Files**: Tap upload → Files → pick a PDF. Confirm upload and list update. Repeat with an image (e.g. PNG).
- [ ] Confirm **Firestore**: `clinics/{clinicId}/patients/{patientId}/uploads/{uploadId}` has: clinicId, patientId, storagePath, fileName, contentType, sizeBytes, createdAt, createdByUid, status "active".
- [ ] Confirm **Storage**: object exists at `clinics/{clinicId}/private/patientUploads/{patientId}/{uploadId}/{fileName}`.
- [ ] Try upload as user **without** patients.write: expect permission error (Storage or Firestore).

---

## 3. List and view
- [ ] List shows only **active** uploads; newest first. Upload several; confirm order.
- [ ] Tap a **PDF**: PDF viewer opens; pinch-zoom works; scroll pages.
- [ ] Tap an **image**: Image viewer opens; zoom (pinch/InteractiveViewer) works.
- [ ] Open an unsupported type (if any): confirm fallback message.

---

## 4. Share / export
- [ ] Open a PDF or image → tap **Share**. Confirm **warning dialog** (“Sharing patient documents…”) appears.
- [ ] Cancel: dialog closes, no share.
- [ ] Continue: OS share sheet opens; complete share (e.g. to another app). Confirm file is received (e.g. PDF/image opens).

---

## 5. Delete
- [ ] From list: tap delete on an upload → confirm dialog → Delete. Confirm item disappears from list; Firestore doc has **status "deleted"** (or doc removed, per your rule); Storage object removed (or 404).
- [ ] From viewer: tap delete → confirm → Delete. Confirm viewer closes and list no longer shows that upload.
- [ ] Delete as user **without** patients.write: expect no delete button (or permission error if exposed).

---

## 6. Security (rules)
- [ ] **Firestore**: From a client with no clinic membership (or different clinic), try read/write on `clinics/{clinicId}/patients/{patientId}/uploads` → expect denied.
- [ ] **Storage**: Try read/write to `clinics/{clinicId}/private/patientUploads/...` without correct membership/permissions → expect denied.
- [ ] Confirm no public read on uploads; no public URLs stored as source of truth (only storagePath in Firestore).

---

## 7. Errors and edge cases
- [ ] Upload with no network → confirm clear error/snackbar.
- [ ] Delete: remove Storage object manually (e.g. console), then delete from app → Firestore status still updates; no crash.
- [ ] Very large file (if applicable): confirm progress or clear failure.

---

## Notes
- **Firestore index**: If the uploads query fails with “index required”, deploy indexes (e.g. `firebase deploy --only firestore:indexes`) after adding the `uploads` composite index in **firestore.indexes.json**.
- **Platform**: Camera option may be unavailable on desktop; use Gallery/Files. Share sheet behavior is platform-specific.
