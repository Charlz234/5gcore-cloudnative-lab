
# ============================================
# aliases.sh
# Add these to your ~/.bashrc for quick access.
# Create ~/.bashrc if you don't have it (esp Windows users)
# Run: source ~/.bashrc after adding
# ============================================

# Replace YOUR_PROJECT_ID with your GCP project ID
# Replace BASTION_IP with your OCI bastion public IP
# Replace CORE_IP and UERANSIM_IP from terraform output

# Lab VM Control
alias lab-start="gcloud compute instances start core-5g ueransim --zone=us-south1-a --project=YOUR_PROJECT_ID"
alias lab-stop="gcloud compute instances stop core-5g ueransim --zone=us-south1-a --project=YOUR_PROJECT_ID"
alias lab-status="gcloud compute instances list --project=YOUR_PROJECT_ID"

# Scheduler Control
alias lab-extend="gcloud scheduler jobs pause stop-core-5g && gcloud scheduler jobs pause stop-ueransim --location=us-central1 --project=YOUR_PROJECT_ID"
alias lab-resume="gcloud scheduler jobs resume stop-core-5g && gcloud scheduler jobs resume stop-ueransim --location=us-central1 --project=YOUR_PROJECT_ID"

# SSH Shortcuts
alias bastion="ssh -i ~/.ssh/id_ed25519 ubuntu@BASTION_IP"  # ~/.ssh/id_ed25519 is assumed to be the path of OCI-VM private key
alias ssh-core="ssh -J ubuntu@BASTION_IP ubuntu@10.10.0.3"
alias ssh-ueransim="ssh -J ubuntu@BASTION_IP ubuntu@10.10.0.4"