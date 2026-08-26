
#
# Retrieves the parent (folder or org of a project). Uses it as the firewall policy parent.
#

data "google_projects" "get_parent" {
  filter = "id:${var.project-id}"
}

output "project" {
  value       = data.google_projects.get_parent
}

resource "google_compute_firewall_policy" "default" {
  parent      = "${data.google_projects.get_parent.projects[0].parent.type}s/${data.google_projects.get_parent.projects[0].parent.id}"
  short_name  = "my-policy"
}
