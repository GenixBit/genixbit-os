# SPDX-License-Identifier: GPL-3.0-or-later
# Variables definition for GenixBit OS Staging Package Repository Infrastructure

variable "project_id" {
  type        = string
  description = "Target GCP Project ID for staging package repository deployment."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id)) && !contains(["my-project", "production", "prod", "default"], var.project_id)
    error_message = "Project ID must be a valid GCP project ID (5-30 chars) and cannot be an unconfigured placeholder or production project name."
  }
}

variable "region" {
  type        = string
  description = "Target GCP Region for staging deployment."
  default     = "asia-south1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region string (e.g. asia-south1, us-central1)."
  }
}

variable "zone" {
  type        = string
  description = "Target GCP Zone for compute instances."
  default     = "asia-south1-a"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be an explicit GCP zone string (e.g. asia-south1-a)."
  }
}

variable "prefix" {
  type        = string
  description = "Resource name prefix for staging infrastructure."
  default     = "genixbit-staging"

  validation {
    condition     = length(var.prefix) <= 24 && can(regex("^[a-z0-9-]+$", var.prefix))
    error_message = "Prefix must be at most 24 characters and contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "subnet_cidr" {
  type        = string
  description = "Isolated private subnet CIDR range."
  default     = "10.100.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR string."
  }
}

variable "private_dns_name" {
  type        = string
  description = "Internal private DNS domain name ending with a dot."
  default     = "staging-packages.genixbit.internal."

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.$", var.private_dns_name))
    error_message = "Private DNS name must be a valid domain ending with a trailing dot (e.g. staging-packages.genixbit.internal.)."
  }
}

variable "machine_type_repo" {
  type        = string
  description = "Compute instance machine type for repository host."
  default     = "e2-medium"

  validation {
    condition     = length(var.machine_type_repo) > 0
    error_message = "Machine type for repository host cannot be empty."
  }
}

variable "machine_type_client" {
  type        = string
  description = "Compute instance machine type for validation client."
  default     = "e2-medium"

  validation {
    condition     = length(var.machine_type_client) > 0
    error_message = "Machine type for validation client cannot be empty."
  }
}

variable "enable_nat" {
  type        = bool
  description = "Enable Cloud NAT for controlled private outbound egress."
  default     = true
}

variable "force_destroy_evidence" {
  type        = bool
  description = "Allow force destruction of evidence bucket for confirmed disposable runs."
  default     = false
}

variable "kms_key_id" {
  type        = string
  description = "Optional KMS key ID for customer-managed disk and bucket encryption."
  default     = ""
}

variable "evidence_retention_days" {
  type        = number
  description = "Days before evidence objects auto-expire and purge."
  default     = 30

  validation {
    condition     = var.evidence_retention_days >= 1 && var.evidence_retention_days <= 365
    error_message = "Evidence retention days must be between 1 and 365."
  }
}

variable "staging_run_id" {
  type        = string
  description = "Unique staging run ID for evidence and resource tracking."
  default     = "run-staging-20260722-001"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.staging_run_id))
    error_message = "Staging run ID must be a non-empty string containing alphanumeric, hyphen, or underscore characters."
  }
}

variable "resource_expiry_date" {
  type        = string
  description = "Resource expiry date label (YYYY-MM-DD)."
  default     = "2026-08-22"

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.resource_expiry_date))
    error_message = "Resource expiry date must be formatted as YYYY-MM-DD."
  }
}
