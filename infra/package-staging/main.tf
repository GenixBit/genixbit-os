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

# 2. Controlled Private Egress via Cloud NAT (No Inbound Public Access)
resource "google_compute_router" "staging_router" {
  count   = var.enable_nat ? 1 : 0
  name    = "${var.prefix}-router"
  region  = var.region
  network = google_compute_network.staging_vpc.id
}

resource "google_compute_router_nat" "staging_nat" {
  count                              = var.enable_nat ? 1 : 0
  name                               = "${var.prefix}-nat"
  router                             = google_compute_router.staging_router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.staging_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# 3. Private Cloud DNS Zone and Record (No Public DNS Mutation)
resource "google_dns_managed_zone" "private_zone" {
  name        = "${var.prefix}-private-dns"
  dns_name    = var.private_dns_name
  description = "GenixBit OS Staging Internal Private DNS Zone"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.staging_vpc.id
    }
  }

  labels = {
    environment = "staging"
    disposable  = "true"
    run_id      = var.staging_run_id
  }
}

resource "google_dns_record_set" "repo_host_a" {
  name         = "staging-packages.${google_dns_managed_zone.private_zone.dns_name}"
  managed_zone = google_dns_managed_zone.private_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_instance.repo_host.network_interface[0].network_ip]
}

# 4. Firewall Rules - No Public Ingress, IAP & Internal HTTPS Only
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

# 5. Separate Service Accounts for Host and Client (Least Privilege)
resource "google_service_account" "repo_sa" {
  account_id   = "${var.prefix}-repo-sa"
  display_name = "GenixBit Staging Repository Host SA"
}

resource "google_service_account" "client_sa" {
  account_id   = "${var.prefix}-client-sa"
  display_name = "GenixBit Staging Validation Client SA"
}

resource "google_project_iam_member" "repo_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.repo_sa.email}"
}

resource "google_project_iam_member" "repo_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.repo_sa.email}"
}

resource "google_project_iam_member" "client_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.client_sa.email}"
}

# 6. Private Evidence Cloud Storage Bucket (Hardened Security & Expiry)
resource "google_storage_bucket" "staging_evidence" {
  name                        = "${var.prefix}-evidence-${var.project_id}"
  location                    = var.region
  force_destroy               = var.force_destroy_evidence
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  labels = {
    environment = "staging"
    disposable  = "true"
    expiry_date = var.resource_expiry_date
    run_id      = var.staging_run_id
  }

  lifecycle_rule {
    condition {
      age = var.evidence_retention_days
    }
    action {
      type = "Delete"
    }
  }

  dynamic "encryption" {
    for_each = var.kms_key_id != "" ? [var.kms_key_id] : []
    content {
      default_kms_key_name = encryption.value
    }
  }
}

# 7. Staging Repository Host Instance (Private IP Only)
resource "google_compute_instance" "repo_host" {
  name         = "${var.prefix}-repo-host"
  machine_type = var.machine_type_repo
  zone         = var.zone

  tags = ["staging-node", "staging-repo-host"]

  labels = {
    environment = "staging"
    disposable  = "true"
    role        = "repository-host"
    expiry_date = var.resource_expiry_date
    run_id      = var.staging_run_id
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
    # No access_config block = Zero public IP assigned
  }

  service_account {
    email = google_service_account.repo_sa.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ]
  }

  metadata_startup_script = templatefile("${path.module}/templates/repo-host-startup.sh.tftpl", {
    hostname = "staging-packages.${var.private_dns_name}"
    run_id   = var.staging_run_id
  })

  metadata = {
    enable-oslogin = "TRUE"
  }
}

# 8. Disposable Validation Client Instance (Private IP Only)
resource "google_compute_instance" "disposable_client" {
  name         = "${var.prefix}-disposable-client"
  machine_type = var.machine_type_client
  zone         = var.zone

  tags = ["staging-node", "staging-client"]

  labels = {
    environment = "staging"
    disposable  = "true"
    role        = "validation-client"
    expiry_date = var.resource_expiry_date
    run_id      = var.staging_run_id
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
    # No access_config block = Zero public IP assigned
  }

  service_account {
    email = google_service_account.client_sa.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write"
    ]
  }

  metadata_startup_script = templatefile("${path.module}/templates/client-startup.sh.tftpl", {
    hostname = "staging-packages.${var.private_dns_name}"
    run_id   = var.staging_run_id
  })

  metadata = {
    enable-oslogin = "TRUE"
  }
}
