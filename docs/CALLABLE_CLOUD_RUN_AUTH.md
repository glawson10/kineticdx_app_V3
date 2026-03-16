# Callable “request was not authenticated” (Cloud Run IAM)

When a Firebase callable (e.g. `upsertStaffProfileFn`) returns **403** or you see this in Cloud Run logs:

```text
The request was not authenticated. Either allow unauthenticated invocations or set the proper Authorization header.
```

the **Cloud Run service** for that function is blocking the request at the IAM layer. The Firebase client does send the user’s ID token; the function will validate it in code. The Cloud Run service still needs to **allow unauthenticated invocations** (grant `roles/run.invoker` to `allUsers`) so the request can reach the function.

This can happen after a new deploy or when Firebase CLI doesn’t set the invoker binding.

---

## Fix: add run.invoker for allUsers

Use the **Cloud Run service name** (lowercase, no separators, e.g. `upsertstaffprofilefn` for `upsertStaffProfileFn`).

**PowerShell (one line):**

```powershell
gcloud run services add-iam-policy-binding upsertstaffprofilefn --region=europe-west3 --member="allUsers" --role="roles/run.invoker" --project=kineticdx-v3-dev
```

**Bash:**

```bash
gcloud run services add-iam-policy-binding upsertstaffprofilefn \
  --region=europe-west3 \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --project=kineticdx-v3-dev
```

Replace `upsertstaffprofilefn` with the target function’s service name if fixing another callable (e.g. `listpatientsforbookingfn`). To list services:

```bash
gcloud run services list --region=europe-west3 --project=kineticdx-v3-dev
```

After adding the binding, retry the callable (e.g. profile photo upload). The function will still enforce Firebase Auth (`req.auth`) in code.

---

## Fix all settings callables (Active toggle, save appointment type, Online booking)

If you see "request was not authenticated" when toggling **Active**, saving **Online booking**, or editing appointment types, the Cloud Run services for those callables need the invoker binding. Service names are the function name in **lowercase with no separators**.

**1. List services to see exact names:**

```bash
gcloud run services list --region=europe-west3 --project=kineticdx-v3-dev --format="value(metadata.name)"
```

**2. Add invoker for the settings callables (PowerShell):**

```powershell
$region = "europe-west3"
$project = "kineticdx-v3-dev"
$services = @(
  "settingssetappointmenttypeactive",
  "settingsupsertappointmenttype",
  "settingsupdatepublicbookingconfig",
  "settingsupsertlocation",
  "settingssetlocationactive",
  "settingsgetcommunicationsettings",
  "settingsupdatecommunicationsettings",
  "settingsgetcalendardisplayconfig",
  "settingsupdatecalendardisplayconfig"
)
foreach ($svc in $services) {
  gcloud run services add-iam-policy-binding $svc --region=$region --member="allUsers" --role="roles/run.invoker" --project=$project
}
```

**2b. Same in Bash:**

```bash
REGION=europe-west3
PROJECT=kineticdx-v3-dev
for svc in settingssetappointmenttypeactive settingsupsertappointmenttype settingsupdatepublicbookingconfig settingsupsertlocation settingssetlocationactive settingsgetcommunicationsettings settingsupdatecommunicationsettings settingsgetcalendardisplayconfig settingsupdatecalendardisplayconfig; do
  gcloud run services add-iam-policy-binding "$svc" --region="$REGION" --member="allUsers" --role="roles/run.invoker" --project="$PROJECT"
done
```

If a binding fails with "service not found", Firebase Gen 2 may use different Cloud Run service names. Use the **fix-all** option below.

---

## Fix all Cloud Run services in the region (no guessing names)

Run this once to add `allUsers` invoker to **every** Cloud Run service in `europe-west3` for your project. Safe for Firebase callables: they still enforce Auth in code.

**PowerShell:**

```powershell
$region = "europe-west3"
$project = "kineticdx-v3-dev"
gcloud run services list --region=$region --project=$project --format="value(metadata.name)" | ForEach-Object {
  Write-Host "Adding invoker to $_"
  gcloud run services add-iam-policy-binding $_ --region=$region --member="allUsers" --role="roles/run.invoker" --project=$project
}
```

**Bash:**

```bash
REGION=europe-west3
PROJECT=kineticdx-v3-dev
for svc in $(gcloud run services list --region=$REGION --project=$PROJECT --format="value(metadata.name)"); do
  echo "Adding invoker to $svc"
  gcloud run services add-iam-policy-binding "$svc" --region="$REGION" --member="allUsers" --role="roles/run.invoker" --project="$PROJECT"
done
```

Then retry the app (e.g. toggle Active or save settings). The request should reach the function.
