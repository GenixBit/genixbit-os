# SPDX-License-Identifier: GPL-3.0-or-later
# Variables definition for GenixBit OS Staging Package Repository Infrastructure

variable "project_id" {
  type        = string
  description = "Target GCP Project ID for staging package repository deployment."
}

variable "region" {
  type        = string
  description = "Target GCP Region for staging deployment."
  default     = "asia-south1"
}

variable "prefix" {
  type        = string
  description = "Resource name prefix for staging infrastructure."
  default     = "genixbit-staging"
}

variable "subnet_cidr" {
  type        = string
  description = "Isolated private subnet CIDR range."
  default     = "10.100.0.0/24"
}

variable "machine_type" {
  type        = string
  description = "Compute instance machine type."
  default     = "e2-medium"
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
}
