#Copyright 2023 Google LLC.
#SPDX-License-Identifier: Apache-2.0
variable "project-id" { type = string }
variable "apis" { type = list(string) }
variable "vpcs" {}
variable "fw_rules" {}
variable "psc_ips" {}
variable "dns_rp_rules" {}
variable "swp_domainname" { type = string }
variable "vms" {}
variable "swp_locations" {}