#Copyright 2023 Google LLC.
#SPDX-License-Identifier: Apache-2.0
variable "project-id-producer" { type = string }
variable "project-id-consumer" { type = string }
variable "apis" { type = list(string) }
variable "vpcs" {}
variable "dns_rp_rules" {}
variable "swp_domainname" { type = string }
variable "vms" {}
variable "swp_locations" {}
variable "append_rand" {
    type = bool
    default = true
}