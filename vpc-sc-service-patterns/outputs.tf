#Copyright 2026 Google LLC.
#SPDX-License-Identifier: Apache-2.0

output "protected_bucket" {
    value = "${google_storage_bucket.gcs_bucket_protected.url}/${google_storage_bucket_object.file_protected.output_name}"
}
output "unprotected_bucket" {
    value = "${google_storage_bucket.gcs_bucket_unprotected.url}/${google_storage_bucket_object.file_unprotected.output_name}"
}
