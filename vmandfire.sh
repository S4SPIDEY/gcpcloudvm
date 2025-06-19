#!/bin/bash

# ─────────────────────────────────────────────
# STEP 1: Prompt for SSH Key and Format It
# ─────────────────────────────────────────────
read -p "Paste your full SSH public key (must end with a username, e.g., ssh-rsa AAAA... spidey): " SSH_PUB

# Extract username from end of key
SSH_USER=$(echo "$SSH_PUB" | awk '{print $NF}')
SSH_KEY="${SSH_USER}:${SSH_PUB}"

# ─────────────────────────────────────────────
# STEP 2: Detect Current GCP Project
# ─────────────────────────────────────────────
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
  echo "❌ No active project found. Please run: gcloud config set project [PROJECT_ID]"
  exit 1
fi

echo "✅ Using project: $PROJECT_ID"

# ─────────────────────────────────────────────
# STEP 3: Enable Required GCP APIs
# ─────────────────────────────────────────────
echo "🔧 Enabling required GCP APIs..."
gcloud services enable compute.googleapis.com iam.googleapis.com --quiet
echo "✅ APIs enabled: Compute & IAM"

# ─────────────────────────────────────────────
# STEP 4: Get Compute Engine Default Service Account (optional fallback)
# ─────────────────────────────────────────────
SERVICE_ACCOUNT=$(gcloud iam service-accounts list \
  --filter="displayName:Compute Engine default service account" \
  --format="value(email)" \
  --project="$PROJECT_ID")

if [ -z "$SERVICE_ACCOUNT" ]; then
  echo "⚠️ No default Compute Engine service account found. Proceeding without --service-account flag."
  USE_SA=false
else
  echo "✅ Using service account: $SERVICE_ACCOUNT"
  USE_SA=true
fi

# ─────────────────────────────────────────────
# STEP 5: Create Firewall Rule (safe skip if exists)
# ─────────────────────────────────────────────
RULE_NAME="allow-custom-ports"

EXISTS=$(gcloud compute firewall-rules list --filter="name=$RULE_NAME" --format="value(name)" --project="$PROJECT_ID")
if [ "$EXISTS" != "$RULE_NAME" ]; then
  echo "🛡️ Creating firewall rule '$RULE_NAME'..."
  gcloud compute firewall-rules create "$RULE_NAME" \
    --project="$PROJECT_ID" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:40400,tcp:8080,tcp:7000,tcp:7001,udp:40400,udp:8080,udp:7000,udp:7001 \
    --source-ranges=0.0.0.0/0 \
    --description="Allow TCP/UDP on ports 40400, 8080, 7000, 7001 from all networks"
else
  echo "✅ Firewall rule '$RULE_NAME' already exists. Skipping..."
fi

# ─────────────────────────────────────────────
# STEP 6: Create VM with Custom Config
# ─────────────────────────────────────────────
echo "🚀 Creating VM 'modeltraining'..."

gcloud compute instances create modeltraining \
  --project="$PROJECT_ID" \
  --zone=us-central1-a \
  --machine-type=n2-standard-8 \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
  --metadata=ssh-keys="$SSH_KEY" \
  --maintenance-policy=MIGRATE \
  --provisioning-model=STANDARD \
  $( [ "$USE_SA" = true ] && echo "--service-account=$SERVICE_ACCOUNT" ) \
  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
  --tags=https-server,http-server \
  --create-disk=auto-delete=yes,boot=yes,device-name=modeltraining,image=projects/ubuntu-os-cloud/global/images/ubuntu-minimal-2410-oracular-amd64-v20250606,mode=rw,size=100,type=pd-balanced \
  --no-shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --labels=goog-ec-src=vm_add-gcloud \
  --reservation-affinity=any \
  --quiet

echo "✅ VM 'modeltraining' created successfully!"
