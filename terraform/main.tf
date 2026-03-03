# Get project information
data "google_project" "project" {
  project_id = var.project_id
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com",
    "firebase.googleapis.com",
    "identitytoolkit.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "cloudscheduler.googleapis.com",
    "firestore.googleapis.com",
    "fcm.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbilling.googleapis.com",
  ])

  project = var.project_id
  service = each.key

  disable_on_destroy = false
}

# Secret Manager module
module "secret_manager" {
  source = "./modules/secret-manager"

  project_id     = var.project_id
  project_number = data.google_project.project.number
  gemini_api_key = var.gemini_api_key

  depends_on = [google_project_service.required_apis]
}

# Firebase module
module "firebase" {
  source = "./modules/firebase"

  project_id   = var.project_id
  display_name = var.firebase_project_display_name
  region       = var.region

  google_client_id     = var.google_client_id
  google_client_secret = var.google_client_secret
  apple_client_id      = var.apple_client_id
  apple_team_id        = var.apple_team_id
  apple_key_id         = var.apple_key_id
  apple_private_key    = var.apple_private_key

  depends_on = [google_project_service.required_apis]
}

# Logging module for Cloud Functions logs and metrics
module "logging" {
  source = "./modules/logging"

  project_id = var.project_id
  region     = var.region

  depends_on = [google_project_service.required_apis]
}

# Artifact Registry cleanup policy for Cloud Functions container images
resource "google_artifact_registry_repository" "gcf_artifacts" {
  project       = var.project_id
  location      = var.region
  repository_id = "gcf-artifacts"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-latest"
    action = "KEEP"
    most_recent_versions {
      keep_count = 1
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "86400s"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# CI/CD service account IAM bindings
locals {
  ci_sa_roles = var.ci_service_account_email != "" ? [
    "roles/iam.serviceAccountUser",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/cloudscheduler.admin",
  ] : []
}

resource "google_project_iam_member" "ci_service_account" {
  for_each = toset(local.ci_sa_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${var.ci_service_account_email}"
}

# Cloud Functions module will be added after Functions code is ready
# module "cloud_functions" {
#   source = "./modules/cloud-functions"
#
#   project_id        = var.project_id
#   region            = var.region
#   secret_id         = module.secret_manager.secret_id
#
#   depends_on = [
#     google_project_service.required_apis,
#     module.secret_manager
#   ]
# }
