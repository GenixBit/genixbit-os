# SPDX-License-Identifier: GPL-3.0-or-later
# Outputs definition for GenixBit OS Staging Package Repository Infrastructure

output "vpc_network_name" {
  value       = google_compute_network.staging_vpc.name
  description = "Name of the isolated staging VPC network."
}

output "subnet_name" {
  value       = google_compute_subnetwork.staging_subnet.name
  description = "Name of the private staging subnetwork."
}

output "repo_host_private_ip" {
  value       = google_compute_instance.repo_host.network_interface[0].network_ip
  description = "Private IP address of the staging repository host."
}

output "disposable_client_private_ip" {
  value       = google_compute_instance.disposable_client.network_interface[0].network_ip
  description = "Private IP address of the disposable validation client."
}

output "evidence_bucket_name" {
  value       = google_storage_bucket.staging_evidence.name
  description = "Name of the private evidence Cloud Storage bucket."
}

output "staging_hostname" {
  value       = "staging-packages.os.genixbit.com"
  description = "Dedicated staging repository hostname."
}
