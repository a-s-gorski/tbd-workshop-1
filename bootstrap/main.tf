locals {
  project = lower("tbd-${var.tbd_semester}-${var.user_id}")
}

resource "google_project" "tbd_project" {
  name            = "TBD ${local.project} project"
  project_id      = local.project
  billing_account = var.billing_account
  auto_create_network = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_project_iam_audit_config" "tbd_project_audit" {
  project = google_project.tbd_project.id
  service = "allServices"
  audit_log_config {
    log_type = "ADMIN_READ"
  }
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_project_service" "tbd-service" {
  project                    = google_project.tbd_project.project_id
  disable_dependent_services = true
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "serviceusage.googleapis.com",
    "sts.googleapis.com"
  ])
  service = each.value
}

resource "google_service_account" "tbd-terraform" {
  project    = google_project.tbd_project.project_id
  account_id = "${local.project}-lab"
}

resource "google_project_iam_member" "tbd-editor-supervisors" {
  for_each = toset([
    "user:marek.wiewiorka@gmail.com",
    "user:tgambin@gmail.com",
    "user:sitekwb@gmail.com"
  ])
  project = google_project.tbd_project.project_id
  role    = "roles/editor"
  member  = each.value

  checkov:skip=CKV_GCP_117: "Ensure basic roles are not used at project level."
}

resource "google_project_iam_member" "tbd-editor-member" {
  project = google_project.tbd_project.project_id
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.tbd-terraform.email}"

  checkov:skip=CKV_GCP_117: "Ensure basic roles are not used at project level."
}

resource "google_storage_bucket" "tbd-state-bucket" {
  project                     = google_project.tbd_project.project_id
  name                        = "${local.project}-state"
  location                    = var.region
  uniform_bucket_level_access = false
  force_destroy               = true
  lifecycle {
    prevent_destroy = true
  }
  public_access_prevention = "enforced"

  checkov:skip=CKV_GCP_78: "Ensure Cloud storage has versioning enabled"
}

resource "google_dataproc_cluster" "tbd_cluster" {
  project = google_project.tbd_project.project_id
  name    = "${local.project}-cluster"
  region  = var.region

  cluster_config {
    staging_bucket = google_storage_bucket.tbd-state-bucket.name

    master_config {
      num_instances = 1
      machine_type  = "n1-highmem-4"
    }

    worker_config {
      num_instances = 2
      machine_type  = "n1-highmem-4"
    }

    initialization_action {
      script = "gs://dataproc-initialization-actions/conda/bootstrap-conda.sh"
    }
  }

  labels = {
    env = "dev"
  }

  checkov:skip=CKV_GCP_103: "Ensure Dataproc Clusters do not have public IPs"
  checkov:skip=CKV_GCP_91: "Ensure Dataproc cluster is encrypted with Customer Supplied Encryption Keys (CSEK)"
}