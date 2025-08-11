variable "project_name" {
  description = "Oxide project name"
  type        = string
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
}

variable "vpc_dns_name" {
  description = "VPC DNS name"
  type        = string
}

variable "vpc_description" {
  description = "Description of the VPC"
  type        = string
}

variable "instance_count" {
  description = "Number of total nodes"
  type        = number
}

variable "server_count" {
  description = "Number of K3s server nodes"
  type        = number
}

variable "memory" {
  description = "Memory (bytes) for K3s nodes"
  type        = number
}

variable "ncpus" {
  description = "CPU cores for K3s nodes"
  type        = number
}

variable "disk_size" {
  description = "Disk size (bytes) for K3s nodes"
  type        = number
}

variable "ubuntu_image_id" {
  description = "UUID of Ubuntu image"
  type        = string
}

variable "public_ssh_key" {
  description = "SSH public key"
  type        = string
}

# NEW: NGINX Load Balancer variables
variable "nginx_lb_memory" {
  description = "Memory (bytes) for the NGINX LB node"
  type        = number
}

variable "nginx_lb_ncpus" {
  description = "CPU cores for the NGINX LB node"
  type        = number
}

variable "nginx_lb_disk_size" {
  description = "Disk size (bytes) for the NGINX LB node"
  type        = number
}
variable "ansible_user" {
  description = "Username for SSH access to instances"
  type        = string
}

variable "k3s_token" {
  description = "Token to use for the K3s cluster join"
  type        = string
}

variable "k3s_version" {
  description = "Version of K3s to install"
  type        = string
}
