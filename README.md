# k8s-eso-demo

ทดสอบการใช้งาน [External Secrets Operator (ESO)](https://external-secrets.io/) บน Kubernetes (Docker Desktop)
โดย sync secret จาก **Azure Key Vault** หรือ **AWS Secrets Manager** มาเป็น Kubernetes Secret
และใช้งานผ่าน Rust application — เพื่อพิสูจน์ว่า app เป็น **cloud agnostic** จริง

---

## แนวคิดหลัก

```
Azure Key Vault          AWS Secrets Manager
      │                          │
      └──────────┬───────────────┘
                 │  ESO ดึง secret (sync ทุก refreshInterval)
                 ▼
      Kubernetes Secret: demo-app-secret
         ├── db-password = <value>
         └── api-key     = <value>
                 │
                 │  mount ผ่าน env var (Deployment ไม่เปลี่ยน)
                 ▼
         Rust Pod (eso-demo)
           DB_PASSWORD = ***
           API_KEY     = ***
```

> Rust app อ่านแค่ `DB_PASSWORD` และ `API_KEY` จาก env var
> ไม่รู้ว่า secret มาจาก cloud ไหน — นี่คือ **cloud agnostic**

---

## สิ่งที่ต้องมีก่อนเริ่ม

| เครื่องมือ | เวอร์ชันที่แนะนำ | ตรวจสอบ |
|---|---|---|
| Docker Desktop | ≥ 4.x (เปิด Kubernetes ใน Settings) | `docker version` |
| kubectl | ≥ 1.28 | `kubectl version --client` |
| Helm | ≥ 3.13 | `helm version` |
| Rust + Cargo | ≥ 1.82 | `cargo version` |
| Azure CLI | ≥ 2.x | `az version` |
| AWS CLI | ≥ 2.x | `aws --version` |

---

## โครงสร้างโปรเจค

```
k8s-eso-demo/
├── src/
│   └── main.rs                   # Rust app — อ่าน secret จาก env var เท่านั้น
├── k8s/
│   ├── namespace.yaml             # Namespace: eso-demo
│   ├── deployment.yaml            # Deployment (ไม่เปลี่ยนเมื่อ switch provider)
│   ├── demo-pod.yaml              # Pod เดี่ยวสำหรับทดสอบเร็ว
│   ├── secret-store.yaml          # SecretStore → Azure Key Vault
│   ├── external-secret.yaml       # ExternalSecret (Azure) → demo-app-secret
│   ├── aws-secret-store.yaml      # SecretStore → AWS Secrets Manager
│   └── aws-external-secret.yaml   # ExternalSecret (AWS) → demo-app-secret (ชื่อเดียวกัน)
├── scripts/
│   ├── deploy-eso.sh              # ติดตั้ง ESO controller
│   ├── setup-azure-secret.sh      # สร้าง SP secret + Azure SecretStore
│   ├── setup-aws-secret.sh        # สร้าง AWS credentials secret + AWS SecretStore
│   ├── switch-vault.sh            # สลับ provider (azure ↔ aws)
│   ├── build-and-load.sh          # Build Docker image
│   └── teardown-eso.sh            # ลบทุกอย่าง
├── Cargo.toml
├── Dockerfile                     # Multi-stage build (Rust → Alpine)
└── .env.example                   # Template credentials (Azure + AWS)
```

---

## ขั้นตอนการทดสอบ

### Task 1 — ติดตั้ง ESO Controller

```bash
./scripts/deploy-eso.sh
```

ตรวจสอบ:
```bash
kubectl get pods -n external-secrets
# ต้องเห็น 3 pods (controller, webhook, cert-controller) ในสถานะ Running

kubectl get crds | grep external-secrets.io
```

---

### Task 2 — เชื่อมต่อ Azure Key Vault

**เตรียม Azure Key Vault:**
```bash
# สร้าง secret ใน Azure Key Vault
az keyvault secret set --vault-name <VAULT_NAME> --name demo-db-password --value "AzureDbPass123"
az keyvault secret set --vault-name <VAULT_NAME> --name demo-api-key     --value "az-api-key-xyz"

# สร้าง Service Principal และให้สิทธิ์
az ad sp create-for-rbac --name "eso-demo-sp" --skip-assignment
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee <CLIENT_ID> \
  --scope $(az keyvault show --name <VAULT_NAME> --query id -o tsv)
```

**ตั้งค่า credentials:**
```bash
cp .env.example .env
# แก้ไข .env ใส่ค่า AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_KEYVAULT_URL
```

**สร้าง SecretStore:**
```bash
./scripts/setup-azure-secret.sh
```

ตรวจสอบ SecretStore:
```bash
kubectl get secretstore azure-keyvault-store -n eso-demo
# STATUS ต้องเป็น Valid
```

**Apply ExternalSecret:**
```bash
kubectl apply -f k8s/external-secret.yaml
kubectl get externalsecret demo-secret -n eso-demo
# READY ต้องเป็น True
```

---

### Task 2b — เชื่อมต่อ AWS Secrets Manager

**เตรียม AWS Secrets Manager:**
```bash
# สร้าง secret ใน AWS SM (ชื่อต้องตรงกับ remoteRef.key ใน aws-external-secret.yaml)
aws secretsmanager create-secret \
  --name demo-db-password \
  --secret-string "AwsDbPass456" \
  --region ap-southeast-1

aws secretsmanager create-secret \
  --name demo-api-key \
  --secret-string "aws-api-key-abc" \
  --region ap-southeast-1

# สร้าง IAM User และ Access Key สำหรับ ESO
aws iam create-user --user-name eso-demo-user
aws iam attach-user-policy \
  --user-name eso-demo-user \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
aws iam create-access-key --user-name eso-demo-user
```

**ใส่ AWS credentials ใน .env:**
```bash
# เพิ่มใน .env ที่มีอยู่แล้ว:
# AWS_ACCESS_KEY_ID=...
# AWS_SECRET_ACCESS_KEY=...
# AWS_REGION=ap-southeast-1
```

**สร้าง SecretStore:**
```bash
./scripts/setup-aws-secret.sh
```

ตรวจสอบ SecretStore:
```bash
kubectl get secretstore aws-secretsmanager-store -n eso-demo
# STATUS ต้องเป็น Valid
```

---

### Task 3 — Build และ Deploy Rust App

**Build Docker image:**
```bash
./scripts/build-and-load.sh
```

**Deploy:**
```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
```

**ดู log:**
```bash
kubectl logs -l app=eso-demo -n eso-demo --follow
```

ผลลัพธ์ที่คาดหวัง:
```
=== ESO Secret Validator ===
Pod: eso-demo-xxxxxxxxx-xxxxx

[OK] DB_PASSWORD (from AKV key: demo-db-password) = Az************
[OK] API_KEY     (from AKV key: demo-api-key)     = az************

All secrets loaded successfully from Azure Key Vault via ESO.
```

---

### Task 5 — ทดสอบ Cloud Agnostic ด้วย switch-vault.sh

#### ดู provider ที่ใช้งานอยู่
```bash
./scripts/switch-vault.sh status
```

#### Switch จาก Azure → AWS
```bash
./scripts/switch-vault.sh aws
```

Script จะ:
1. ลบ ExternalSecret เดิม (ESO ลบ `demo-app-secret` อัตโนมัติ เพราะ `creationPolicy: Owner`)
2. Apply `k8s/aws-external-secret.yaml` (สร้าง `demo-app-secret` ใหม่จาก AWS SM)
3. รอให้ ESO sync จนได้สถานะ `Ready: True`
4. Restart Deployment
5. แสดงสรุปสถานะ

ดู log หลัง switch:
```bash
kubectl logs -l app=eso-demo -n eso-demo --tail=20
```

ผลลัพธ์ที่คาดหวัง (ค่า secret เปลี่ยนเป็น AWS แต่โค้ด app ไม่เปลี่ยน):
```
=== ESO Secret Validator ===
Pod: eso-demo-yyyyyyyyy-yyyyy

[OK] DB_PASSWORD (from AKV key: demo-db-password) = Aw************
[OK] API_KEY     (from AKV key: demo-api-key)     = aw************

All secrets loaded successfully from Azure Key Vault via ESO.
```

#### Switch กลับจาก AWS → Azure
```bash
./scripts/switch-vault.sh azure
```

#### ข้อสรุป Cloud Agnostic
| สิ่งที่เปลี่ยน | สิ่งที่ไม่เปลี่ยน |
|---|---|
| ExternalSecret (provider) | Rust source code |
| ค่า secret ใน K8s | `deployment.yaml` |
| SecretStore | ชื่อ K8s Secret (`demo-app-secret`) |
| | ชื่อ env var (`DB_PASSWORD`, `API_KEY`) |

> Rust app พิสูจน์ว่าเป็น cloud agnostic: อ่าน env var เหมือนเดิม
> ไม่ว่า secret จะมาจาก Azure หรือ AWS

---

### ทดสอบ Auto-sync (Force Refresh)

แก้ไขค่า secret ใน Azure KV หรือ AWS SM แล้ว force sync:

```bash
kubectl annotate externalsecret demo-secret \
  force-sync=$(date +%s) --overwrite -n eso-demo

# Restart pod เพื่อรับ secret ใหม่
kubectl rollout restart deployment/eso-demo -n eso-demo
kubectl logs -l app=eso-demo -n eso-demo --follow
```

---

### Cleanup

```bash
./scripts/teardown-eso.sh
```
