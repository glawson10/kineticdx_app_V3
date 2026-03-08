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
