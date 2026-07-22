# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS Staging Package Repository Infrastructure (OpenTofu / Terraform)

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Dedicated Isolated VPC Network & Subnet
resource "google_compute_network" "staging_vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "staging_subnet" {
  name                     = "${var.prefix}-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.staging_vpc.id
  private_ip_google_access = true
}

# 2. Firewall Rules - Block Public Ingress, Permit IAP and Inter-Node Internal Traffic Only
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "${var.prefix}-allow-iap-ssh"
  network = google_compute_network.staging_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google Cloud Identity-Aware Proxy (IAP) CIDR range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["staging-node"]
}

resource "google_compute_firewall" "allow_internal_https" {
  name    = "${var.prefix}-allow-internal-https"
  network = google_compute_network.staging_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443", "8443"]
  }

  source_tags = ["staging-client"]
  target_tags = ["staging-repo-host"]
}

# 3. Private Cloud Storage Bucket for Evidence with Auto-Expiry Lifecycle Rule
resource "google_storage_bucket" "staging_evidence" {
  name                        = "${var.prefix}-evidence-${var.project_id}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  labels = {
    environment = "staging"
    disposable  = "true"
    purpose     = "evidence"
  }

  lifecycle_rule {
    condition {
      age = var.evidence_retention_days
    }
    action {
      type = "Delete"
    }
  }

  encryption {
    default_kms_key_name = var.kms_key_id != "" ? var.kms_key_id : null
  }
}

# 4. Service Account for Staging Nodes with Minimal IAM Permissions
resource "google_service_account" "staging_sa" {
  account_id   = "${var.prefix}-node-sa"
  display_name = "GenixBit Staging Repository Node SA"
}

resource "google_project_iam_member" "logging_role" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.staging_sa.email}"
}

# 5. Staging Repository Host Instance (No External IP)
resource "google_compute_instance" "repo_host" {
  name         = "${var.prefix}-repo-host"
  machine_type = var.machine_type
  zone         = "${var.region}-a"

  tags = ["staging-node", "staging-repo-host"]

  labels = {
    environment = "staging"
    disposable  = "true"
    role        = "repository-host"
  }

  boot_disk {
    auto_delete = true
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 30
      type  = "pd-ssd"
    }
    kms_key_self_link = var.kms_key_id != "" ? var.kms_key_id : null
  }

  network_interface {
    subnetwork = google_compute_subnetwork.staging_subnet.id
    # No access_config block = No public IP address assigned
  }

  service_account {
    email  = google_service_account.staging_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    user-data      = <<-EOF
      #!/bin/bash
      set -euo pipefail
      echo "Initializing GenixBit OS Staging Repository Host..."
    EOF
  }
}

# 6. Isolated Disposable Client Instance (No External IP)
resource "google_compute_instance" "disposable_client" {
  name         = "${var.prefix}-disposable-client"
  machine_type = var.machine_type
  zone         = "${var.region}-a"

  tags = ["staging-node", "staging-client"]

  labels = {
    environment = "staging"
    disposable  = "true"
    role        = "validation-client"
  }

  boot_disk {
    auto_delete = true
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 20
      type  = "pd-standard"
    }
    kms_key_self_link = var.kms_key_id != "" ? var.kms_key_id : null
  }

  network_interface {
    subnetwork = google_compute_subnetwork.staging_subnet.id
    # No access_config block = No public IP address assigned
  }

  service_account {
    email  = google_service_account.staging_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    user-data      = <<-EOF
      #!/bin/bash
      set -euo pipefail
      echo "Initializing GenixBit OS Disposable Staging Client..."
    EOF
  }
}
