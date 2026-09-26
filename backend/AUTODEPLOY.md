# Railway production autodeploy

The production `api` service is connected to the GitHub repository `mmaatteusz/bezpieczna-polska` and the `main` branch.

Railway watches `backend/**`. A commit merged to `main` that changes files under `backend/` should trigger a fresh source deployment. Production identity is verified through `/health` using the deployed `BUILD_SHA`, and the runtime audit validates `/ready`, source health, snapshot, shelters and NEPTUN after deployment.

This file also provides a safe `backend/**` change for validating the GitHub → Railway autodeploy path without changing application behavior.
