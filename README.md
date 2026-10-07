
# The Directory — Flask + Postgres on Kubernetes (minikube → Amazon EKS with Helm)

A small people-directory app (add up to 5 people, click a card to flip it and see their details), built to practice deploying a real multi-service application on Kubernetes. It started as six hand-written manifests on minikube and is now packaged as a **Helm chart and deployed to Amazon EKS** with persistent EBS storage and a public AWS load balancer.

> **SCREENSHOT — the finished app.**
<img width="1600" height="900" alt="Screenshot (84)" src="https://github.com/user-attachments/assets/7fa8b448-c0c7-4254-bd43-25470db295b5" />


---

## Stack

- **Frontend:** HTML/CSS/JS served directly by Flask (single deployment, single Service)
- **Backend:** Python Flask, REST API (`/api/people`, `/api/health`)
- **Database:** PostgreSQL 15
- **Packaging:** Helm (one chart)
- **Orchestration:** Kubernetes — minikube locally, Amazon EKS (eu-north-1) in AWS
- **Storage:** EBS gp3 volumes via the EBS CSI driver
- **Containerization:** Docker, non-root hardened image
- **Monitoring:** Prometheus + Grafana (RED and USE dashboards), not done on EKS yet.

## Architecture (EKS)

```
Browser
   │  http://<aws-load-balancer>:80
   ▼
AWS load balancer (created by the flask-service of type LoadBalancer)
   │
   ▼
flask-service  (port 80  →  targetPort 5000)
   │
   ▼
flask-deployment (2 replicas, Flask listens on 5000)
   │  reads/writes via env vars from postgres-secret
   ▼
postgres-service (ClusterIP :5432)
   │
   ▼
postgres-deployment (1 replica, strategy: Recreate)
   │
   ▼
postgres-pvc (StorageClass gp3 → EBS volume via ebs.csi.aws.com)
```

Cluster: managed node group, 2 worker nodes [TODO: instance type, e.g. t3.medium], default VPC, Auto Mode off — so I installed and configured the EBS CSI driver myself.

> **SCREENSHOT — cluster overview.** 
> <img width="1600" height="900" alt="Screenshot (88)" src="https://github.com/user-attachments/assets/f944e54a-d392-4ba8-81e3-e5b201fe4746" />

> **SCREENSHOT — node group.**
> <img width="1600" height="900" alt="Screenshot (89)" src="https://github.com/user-attachments/assets/bf42ace8-b166-4cc5-8075-9250d6aec3db" />

## Repository layout

```
.
├── people-directory/             # the Helm chart (folder containing Chart.yaml)
│   ├── Chart.yaml
│   ├── values.yaml               # defaults (minikube-friendly)
│   └── templates/
│       ├── postgres-secret.yaml
│       ├── postgres-pvc.yaml
│       ├── postgres-deployment.yaml
│       ├── postgres-service.yaml
│       ├── flask-deployment.yaml
│       └── flask-service.yaml
├── monitoring/                   # Grafana dashboard JSON
└── .github/workflows/            # CI
```

[TODO: adjust the tree to match your real repo]

Design rules I followed in the chart:

- **One source of truth per fact.** The container port lives once in values (`flask.port: 5000`) and feeds the Deployment, the probes and the Service `targetPort`. The Service's public port (`80`) is a separate value.
- **The chart only *references* a StorageClass, it never creates one.** A StorageClass is cluster-wide infrastructure with a different lifecycle from the app.
- **No namespace hardcoded in templates.** Helm applies it from `-n`.
- **No password in any file.** It is passed at install time with `--set`.

---

## Deploying to EKS

### 1. Connect to the cluster

```bash
aws sts get-caller-identity
aws eks update-kubeconfig --region eu-north-1 --name People-Directory
kubectl get nodes
```

> **SCREENSHOT — nodes Ready.** 
><img width="1600" height="900" alt="Screenshot (81)" src="https://github.com/user-attachments/assets/bd7b212f-dfde-4e58-af8e-e2c213e381e9" />

### 2. Prepare storage (one-time, cluster-level)

With EKS Auto Mode off, nothing provisions volumes for you. I installed the **Amazon EBS CSI Driver** add-on with an IAM role (IRSA) so its controller can call the EC2 API, then created a `gp3` StorageClass:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
```


`WaitForFirstConsumer` matters: an EBS volume lives in a single availability zone, so Kubernetes waits until the pod is scheduled and then creates the volume in that node's AZ.

> **SCREENSHOT — EBS CSI healthy.** 
> <img width="1600" height="900" alt="Screenshot (82)" src="https://github.com/user-attachments/assets/cd73aabb-44b6-4d72-b073-16f2444e709f" />

> **SCREENSHOT 06 — add-on in the console.** 
><img width="1600" height="900" alt="Screenshot (90)" src="https://github.com/user-attachments/assets/29ed8961-7179-4c57-aeba-6e158c63fb87" />


### 3. Validate the chart before touching the cluster

```bash
helm lint ./people-directory -f ./people-directory/values-eks.yaml
helm template people-directory ./people-directory \
  -f ./people-directory/values-eks.yaml --set postgres.password=test
```

`helm template` renders the final YAML locally. I check that the Service selector matches the pod labels, the storage class is `gp3`, and the ports are right.

### 4. Install

```bash
helm upgrade --install people-directory ./people-directory \
  -n people-directory --create-namespace \
  -f ./people-directory/values-eks.yaml \
  --set postgres.password='<password>' \
  --wait --timeout 5m
```

I dropped `--atomic` while debugging: it rolls the release back on failure, which deletes the evidence.

### 5. Verify bottom-up

```bash
kubectl get pvc,pods,svc,endpoints -n people-directory -o wide
helm list -n people-directory
helm history people-directory -n people-directory
```

> **SCREENSHOT — everything healthy.**
> <img width="1591" height="531" alt="Screenshot (81)" src="https://github.com/user-attachments/assets/a340482f-08ce-4fef-8022-292d58c4925d" />
>
> **SCREENSHOT — Helm release.**
> <img width="1401" height="403" alt="new" src="https://github.com/user-attachments/assets/1838b293-36df-4759-80b4-bfa997dcfd32" />
>
> **SCREENSHOT — Service wiring.**
> <img width="1600" height="900" alt="Screenshot (83)" src="https://github.com/user-attachments/assets/8f12089d-ce7b-4222-a0ef-6897bb38ed20" />
>
> **SCREENSHOT — the load balancer in AWS.**
> <img width="1600" height="900" alt="Screenshot (91)" src="https://github.com/user-attachments/assets/3f7c16fc-83bb-4939-8a7c-4be964f1941a" />
>
> **SCREENSHOT — the EBS volume.** 
> <img width="1600" height="900" alt="Screenshot (92)" src="https://github.com/user-attachments/assets/74712948-24b3-42c2-89dd-8e56d249ef7a" />

---

## Persistent storage

Postgres data survives pod deletion and recreation through a `PersistentVolumeClaim` mounted at `/var/lib/postgresql/data`. On EKS the claim is backed by a real EBS gp3 volume.

Verified by adding people through the UI, deleting the Postgres pod directly, and confirming the data was still there once the replacement pod came up.

Two EBS-specific details:

- The Postgres Deployment uses `strategy: Recreate`. An EBS volume attaches t<img width="1600" height="900" alt="Screenshot (85)" src="https://github.com/user-attachments/assets/77d4bcaa-3dc7-4a2f-99ee-353ea6b97483" />
o one node at a time, so a rolling update could try to start the new pod while the old one still holds the volume.
- [TODO: if you set `PGDATA` to a subfolder, say so here. The fresh EBS volume has a `lost+found` folder at its root, which Postgres refuses to initialise over. 

> **SCREENSHOT — persistence test (before).**
> <img width="1600" height="900" alt="Screenshot (85)" src="https://github.com/user-attachments/assets/0db7ca1d-0cd1-49e8-bff2-67488d999454" />
>
> 📸 **SCREENSHOT — persistence test (after).** After `kubectl delete pod <postgres-pod> -n people-directory`: the new pod name and the same cards still in the app.
> <img width="1600" height="900" alt="Screenshot (86)" src="https://github.com/user-attachments/assets/df8ed470-64b7-4f72-93ce-14a6322d7ec4" />
The data persisted.
<img width="1600" height="900" alt="Screenshot (87)" src="https://github.com/user-attachments/assets/fcae94e0-da5f-42f3-ae7c-3d8844990427" />


## Health checks

Both containers use readiness and liveness probes.

- **Readiness** controls whether the Service routes traffic to a pod. Flask retries its DB connection on startup, and until that succeeds the pod should not receive user traffic.
- **Liveness** controls whether Kubernetes restarts a container that is stuck even though the process hasn't crashed.
- Flask is checked through a dedicated `/api/health` HTTP endpoint on its container port. Postgres is checked with `pg_isready`, because it speaks the Postgres wire protocol, not HTTP.

---

## Debugging stories


Everything below actually broke. Each entry covers the symptom, how I investigated, the root cause, the fix, and what I learned.

### 1. Silent DB env-var mismatch (minikube)

**Symptom:** Pods were Running, but the page returned HTTP 500.
**Investigation:** `kubectl logs` showed a Postgres authentication failure. That was confusing, since the network path to Postgres clearly worked.
**Root cause:** The Deployment injected `DB_HOST/DB_USER/DB_PASSWORD/DB_NAME`, while the app read `POSTGRES_HOST/POSTGRES_USER/POSTGRES_PASSWORD/POSTGRES_DB`. The code used `.get()` with a default, so it didn't crash; it silently connected with the wrong credentials.
**Fix:** Aligned the variable names with the actual secret keys.
**Lesson:** Silent fallbacks in config code hide real bugs. I'd rather config fail loudly than quietly run wrong.


### 2. EBS CSI controller stuck in CrashLoopBackOff

**Symptom:** `kubectl get pods -n kube-system` showed `ebs-csi-controller` at **1/6 containers ready** with 91 restarts, while `ebs-csi-node` was healthy (3/3). Left alone, the Postgres PVC could never bind.
**Investigation:** The controller pod has six containers: `ebs-plugin` plus five sidecars that depend on it. One failing container taking the others with it pointed at `ebs-plugin`. Its logs (`kubectl logs … -c ebs-plugin --previous`) showed `no EC2 IMDS role found … GetMetadata … context deadline exceeded`. `aws eks describe-addon` showed `role: null`.
**Root cause:** The add-on had no IAM role. With no role, the AWS SDK falls back to the node's metadata service, which pods can't reach, so the health check failed, the liveness probe returned 500 and kubelet kept restarting the container.
**Fix:** attached an IAM role with `AmazonEBSCSIDriverPolicy` to the add-on via the cluster's OIDC provider (IRSA), then restarted the controller. The controller reached 6/6 Running.
**Lesson:** Prefer a dedicated IAM role for the one service account that needs it over giving every pod on the node EBS permissions. Least privilege.


### 3. Helm refused to install: StorageClass ownership

**Symptom:** `helm install --dry-run` failed with `StorageClass "gp3" … exists and cannot be imported into the current release: invalid ownership metadata`.
**Root cause:** My chart contained a `gp3` StorageClass template, and I had already created `gp3` manually. Helm will not take over resources it didn't create; it only manages objects that carry its ownership label and annotations.
**Fix:** Removed the StorageClass from the chart. The PVC references `storageClassName: gp3` from values and the class lives outside the release.
**Lesson:** Cluster-scoped infrastructure (StorageClasses) and app resources have different lifecycles. If the chart owned the class, `helm uninstall` would delete it for every other app using it.


### 4. Page unreachable on the external IP

**Symptom:** The load balancer had an external hostname, but the browser couldn't load the app. It worked when I added `:5000` to the URL.
**Root cause:** Browsers use port 80 by default. My Service had `port: 5000`, so the load balancer listened on 5000, and nothing was listening on 80.
**Fix:** Set the Service `port` to 80 and kept `targetPort` at 5000 (where Flask listens).
**Lesson:** The Service `port` is the front door, `targetPort` is the container's port, and `nodePort` is an internal hop the load balancer uses to reach the nodes. They are three different things.

### 5. Helm upgrade hanging after the port change

**Symptom:** After the fix above, `helm upgrade` ran for minutes without finishing.
**Investigation:** I had reused the same `port` variable everywhere, so the container port (and anything derived from it, such as the probes) also became 80, while Flask still listens on 5000.
**Root cause:** The new pods could not become Ready, so Helm's `--wait` kept waiting until the timeout. During a rolling update the old pod kept serving, which is why the site still worked on :5000.
**Fix:** Split it into two values: `flask.containerPort: 5000` (Deployment, probes, `targetPort`) and the Service's own public port 80.
**Lesson:** `helm template` and reading the rendered YAML would have caught it before the cluster was involved. One source of truth per fact.

---

## Cost and teardown

The EKS control plane alone costs roughly $0.10/hour at the time of writing (check current pricing), plus nodes, the load balancer and EBS storage, so I tear everything down after each session. Order matters, otherwise orphaned load balancers and volumes keep billing:

1. `helm uninstall people-directory -n people-directory` (removes the Service, and with it the load balancer)
2. `kubectl delete pvc --all -n people-directory` (deletes the EBS volume, since the reclaim policy is `Delete`), then delete the namespace
3. Verify in the EC2 console that no load balancers or volumes remain
4. `kubectl delete sc gp3`
5. Delete the node group, then the cluster
6. Remove the leftover IAM role and OIDC provider

## Limitations (what this is not yet)

- The cluster was created in the console, so it isn't reproducible yet.
- Plain HTTP on a load balancer hostname: no HTTPS, no Ingress, no custom domain.
- Postgres is a single Deployment: no replication or backups. A StatefulSet is the better model for a real database.
- The database password is passed with `--set`, and Kubernetes Secrets are only base64-encoded, not encrypted. A real setup would use AWS Secrets Manager.
- CI doesn't deploy to EKS yet.

## Next steps

- Recreate the cluster with Terraform
- GitHub Actions deploying to EKS using OIDC (no long-lived AWS keys)
- ALB Ingress with HTTPS (ACM certificate)
- Trivy image scanning in CI/CD
- ArgoCD for GitOps-based deployment

## What I learned

- Helm is a templating engine plus release tracker. Anything that actually runs is plain Kubernetes, so most "Helm problems" are Kubernetes problems.
- On EKS with Auto Mode off, storage and load balancing are not free: the EBS CSI driver and its IAM role are part of the job.
- Debug bottom-up: PVC, then pod, then endpoints, then Service, then load balancer. Stop at the first broken layer.
- Change one thing at a time. Most of my bad hours came from changing several at once.
