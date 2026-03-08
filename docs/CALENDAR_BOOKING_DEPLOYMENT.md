# Calendar & booking deployment checklist

After implementing calendar speed, booking reliability, admin-block display, and patient finder via callable, ensure the following are deployed and verified.

---

## 1. Cloud Functions

| Function | Purpose |
|----------|---------|
| **listPatientsForBookingFn** | Server-side patient list for Find patient (booking flow) and Patient finder (shell). Requires `patients.read`. |
| **onAppointmentWrite_toBusyBlock** | Mirrors appointments (including admin blocks) to `public/availability/blocks` so public booking slots stay in sync. |

Deploy:

```bash
cd functions && npm run build && cd .. && firebase deploy --only functions
```

Or deploy the new/updated ones only:

```bash
firebase deploy --only functions:listPatientsForBookingFn,functions:onAppointmentWrite_toBusyBlock
```

---

## 2. Firestore indexes

The calendar shows **admin blocks** when a practitioner is selected by merging a second query (`kind == 'admin'`). That query needs a composite index:

- **Collection:** `appointments`
- **Fields:** `kind` (ASC), `startAt` (ASC)

Deploy indexes:

```bash
firebase deploy --only firestore:indexes
```

If the deploy reports that an index "is not necessary" (e.g. single-field), remove that entry from `firestore.indexes.json` and redeploy.

---

## 3. Permissions

- Any role that can **book** (has `schedule.write`) should also have **patients.read** so they can open Find patient and Patient finder. Role templates already grant both; custom roles or legacy members may need a backfill.
- If users see "You don't have permission to search/view patients", grant **patients.read** for that clinic (e.g. via member permissions or role template).

---

## 4. Quick verification

1. **Admin block on calendar:** Create an admin block from the calendar; confirm it appears in week view (with a practitioner selected and with “all”).
2. **Find patient (booking):** Book slot → Follow up or New patient → Find existing → list loads (or clear error + Retry).
3. **Patient finder (shell):** Open Patient finder from clinician shell → list loads (or clear error + Retry).
4. **Public booking:** Create an admin or patient appointment from the calendar; confirm that slot is no longer offered on the public booking screen.

---

## 5. Troubleshooting

### "Failed to load patients" / 403 on Find patient

**Symptom:** Find patient shows "A server error occurred" or "[firebase_functions/internal] internal", or Cloud Run logs show:

- `OPTIONS ... 403` — "The request was not authenticated. Either allow unauthenticated invocations..."
- Revision metadata shows **wrong build** (e.g. `build-function-target: computeIntakeSummaryV2` for `listPatientsForBookingFn`).

**Fix 1 – Allow callable to be invoked (fix 403 / CORS preflight):**  
The callable’s Cloud Run service must allow unauthenticated invocations so the browser’s OPTIONS preflight and the SDK’s POST can reach it. The function itself enforces auth.

**PowerShell (one line):**
```powershell
gcloud run services add-iam-policy-binding listpatientsforbookingfn --region=europe-west3 --member="allUsers" --role="roles/run.invoker" --project=kineticdx-v3-dev
```

**Bash:**
```bash
gcloud run services add-iam-policy-binding listpatientsforbookingfn \
  --region=europe-west3 \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --project=kineticdx-v3-dev
```

**Fix 2 – Wrong function code (revision built from computeIntakeSummaryV2):**  
Redeploy **only** this function so Firebase builds and deploys the correct handler:

```bash
firebase deploy --only functions:listPatientsForBookingFn
```

Then in Cloud Run (or the next deploy), confirm the revision’s `build-function-target` (or image/source) is `listPatientsForBookingFn`, not `computeIntakeSummaryV2`.
