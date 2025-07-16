#!/bin/bash

# ==== AUTO-DETECT PROJECT ====
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
  echo "❌ No active project found. Please run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
else
  echo "📦 Using Project: $PROJECT_ID"
fi

# ==== CONFIG START ====
VM_NAMES=("vm01" "vm02")
ZONE="us-central1-a"
IMAGE="projects/ubuntu-os-cloud/global/images/ubuntu-minimal-2410-oracular-amd64-v20250709"
MACHINE_TYPE="c2d-standard-4"
# ==== CONFIG END ====

# Prompt for SSH keys
echo -e "\\n🔐 Enter SSH key + username for each VM (format: ssh-rsa AAAA...xyz username)"
USER_KEYS=()
for i in {1..2}; do
  read -rp "VM $i SSH key: " input
  USER_KEYS+=("$input")
done

# Create VMs
VM_SUMMARY=()
for i in {0..1}; do
  VM_NAME="${VM_NAMES[$i]}"
  SSH_LINE="${USER_KEYS[$i]}"
  SSH_USER=$(echo "$SSH_LINE" | awk '{print $NF}')
  SSH_KEY=$(echo "$SSH_LINE" | sed "s/ $SSH_USER\$//")

  echo -e "\\n🚀 Creating $VM_NAME in $ZONE..."

  gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
    --metadata="ssh-keys=$SSH_USER:$SSH_KEY" \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --no-service-account \
    --no-scopes \
    --tags=http-server,https-server \
    --create-disk=auto-delete=yes,boot=yes,device-name="$VM_NAME",image="$IMAGE",mode=rw,size=60,type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --no-shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any

  EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

  VM_SUMMARY+=("$VM_NAME | $EXTERNAL_IP | $SSH_USER")
done

# Final summary
echo -e "\\n✅ VMs Created Successfully!"
echo -e "\\n🧾 VM Summary:"
printf "VM Name | External IP | Username\\n"
printf "%s\\n" "${VM_SUMMARY[@]}"
