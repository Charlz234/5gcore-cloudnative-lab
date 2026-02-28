# ============================================
# GCP Cloud Scheduler
# Start VMs at 9am WAT, stop at 3pm WAT daily
# ============================================

# Enable required APIs
resource "google_project_service" "cloud_scheduler_api" {
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute_api" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# Dedicated service account for scheduler
resource "google_service_account" "lab_scheduler_sa" {
  account_id   = "lab-scheduler-sa"
  display_name = "Lab Scheduler Service Account"
  description  = "Controls start/stop of lab VMs via Cloud Scheduler"
}

# Grant compute instanceAdmin to service account
resource "google_project_iam_member" "scheduler_compute_admin" {
  project = var.gcp_project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.lab_scheduler_sa.email}"
}

# ---- START JOBS ----

# Start 5g-core at 9am WAT (8am UTC)
resource "google_cloud_scheduler_job" "start_core" {
  name        = "start-5g-core"
  description = "Start 5G core VM at 9am WAT daily"
  schedule    = "0 8 * * *"
  time_zone   = "Africa/Lagos"
  region      = "us-central1"

  depends_on = [google_project_service.cloud_scheduler_api]

  http_target {
    http_method = "POST"
    uri         = "https://compute.googleapis.com/compute/v1/projects/${var.gcp_project_id}/zones/${var.gcp_zone}/instances/core-5g/start"
    oauth_token {
      service_account_email = google_service_account.lab_scheduler_sa.email
    }
  }
}

# Start ueransim at 9am WAT (8am UTC)
resource "google_cloud_scheduler_job" "start_ueransim" {
  name        = "start-ueransim"
  description = "Start UERANSIM VM at 9am WAT daily"
  schedule    = "0 8 * * *"
  time_zone   = "Africa/Lagos"
  region      = "us-central1"

  depends_on = [google_project_service.cloud_scheduler_api]

  http_target {
    http_method = "POST"
    uri         = "https://compute.googleapis.com/compute/v1/projects/${var.gcp_project_id}/zones/${var.gcp_zone}/instances/ueransim/start"
    oauth_token {
      service_account_email = google_service_account.lab_scheduler_sa.email
    }
  }
}

# ---- STOP JOBS ----

# Stop 5g-core at 3pm WAT (2pm UTC)
resource "google_cloud_scheduler_job" "stop_core" {
  name        = "stop-5g-core"
  description = "Stop 5G core VM at 3pm WAT daily"
  schedule    = "0 14 * * *"
  time_zone   = "Africa/Lagos"
  region      = "us-central1"

  depends_on = [google_project_service.cloud_scheduler_api]

  http_target {
    http_method = "POST"
    uri         = "https://compute.googleapis.com/compute/v1/projects/${var.gcp_project_id}/zones/${var.gcp_zone}/instances/core-5g/stop"
    oauth_token {
      service_account_email = google_service_account.lab_scheduler_sa.email
    }
  }
}

# Stop ueransim at 3pm WAT (2pm UTC)
resource "google_cloud_scheduler_job" "stop_ueransim" {
  name        = "stop-ueransim"
  description = "Stop UERANSIM VM at 3pm WAT daily"
  schedule    = "0 14 * * *"
  time_zone   = "Africa/Lagos"
  region      = "us-central1"

  depends_on = [google_project_service.cloud_scheduler_api]

  http_target {
    http_method = "POST"
    uri         = "https://compute.googleapis.com/compute/v1/projects/${var.gcp_project_id}/zones/${var.gcp_zone}/instances/ueransim/stop"
    oauth_token {
      service_account_email = google_service_account.lab_scheduler_sa.email
    }
  }
}
