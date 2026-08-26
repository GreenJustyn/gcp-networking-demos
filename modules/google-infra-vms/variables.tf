variable "project-id" {
    type    = string
    default = null
}

variable "vms" {
  type = list(object({
    append-suffix-tag : optional(bool,true),
    image : optional(string),
    name : string,
    project-id : optional(string),
    region : optional(string),
    zone : optional(string),
    subnet : optional(string),
    subnet-project-id : optional(string),
    tags : optional(list(string)),
    description : optional(string),
    machine-type : optional(string,"e2-micro"),
    ip-forwarding : optional(bool),
    scopes : optional(list(string),["cloud-platform"]),
    script : optional(string),
    network : optional(string),
    external-ipv4 : optional(string,true),
    private-ip : optional(string),
    cidrhostnum : optional(number)
  }))
}
variable "vpcs" { default = null }
variable "namesuffix" { }
