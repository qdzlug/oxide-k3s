terraform {
  required_version = ">= 1.0"
  required_providers {
    oxide = {
      source  = "oxidecomputer/oxide"
      version = "0.5.0"
    }
  }
}

provider "oxide" {}

data "oxide_project" "k3s" {
  name = var.project_name
}

resource "oxide_ssh_key" "k3s" {
  name        = "k3s-rmt-key"
  description = "SSH key for k3s RMT provisioning"
  public_key  = var.public_ssh_key
}

resource "oxide_vpc" "k3s" {
  name        = var.vpc_name
  dns_name    = var.vpc_dns_name
  description = var.vpc_description
  project_id  = data.oxide_project.k3s.id
}

data "oxide_vpc_subnet" "default" {
  project_name = data.oxide_project.k3s.name
  vpc_name     = oxide_vpc.k3s.name
  name         = "default"
}

resource "oxide_disk" "nodes" {
  for_each = { for i in range(var.instance_count) : i => "k3s-node-${i + 1}" }

  name            = each.value
  project_id      = data.oxide_project.k3s.id
  description     = "Disk for ${each.value}"
  size            = var.disk_size
  source_image_id = var.ubuntu_image_id
}

resource "oxide_instance" "nodes" {
  for_each = oxide_disk.nodes

  name             = each.value.name
  project_id       = data.oxide_project.k3s.id
  boot_disk_id     = each.value.id
  description      = "K3s node ${each.value.name}"
  memory           = var.memory
  ncpus            = var.ncpus
  disk_attachments = [each.value.id]
  ssh_public_keys  = [oxide_ssh_key.k3s.id]
  start_on_create  = true
  host_name        = each.value.name

  external_ips = [{
    type = "ephemeral"
  }]

  network_interfaces = [{
    name        = "nic-${each.value.name}"
    description = "Primary NIC"
    vpc_id      = data.oxide_vpc_subnet.default.vpc_id
    subnet_id   = data.oxide_vpc_subnet.default.id
  }]

  user_data = base64encode(<<-EOF
#!/bin/bash
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
chmod 0440 /etc/sudoers.d/ubuntu
EOF
  )
}

resource "oxide_disk" "nginx_lb" {
  project_id      = data.oxide_project.k3s.id
  name            = "nginx-lb-disk"
  size            = 34359738368
  description     = "Boot disk for nginx load balancer"
  source_image_id = var.ubuntu_image_id
}

resource "oxide_instance" "nginx_lb" {
  project_id       = data.oxide_project.k3s.id
  name             = "nginx-lb"
  description      = "NGINX Load Balancer"
  boot_disk_id     = oxide_disk.nginx_lb.id
  disk_attachments = [oxide_disk.nginx_lb.id]
  ssh_public_keys  = [oxide_ssh_key.k3s.id]
  memory           = 2147483648
  ncpus            = 1
  start_on_create  = true
  host_name        = "nginx-lb"

  external_ips = [{
    type = "ephemeral"
  }]

  network_interfaces = [{
    name        = "nic-nginx-lb"
    description = "Primary NIC"
    vpc_id      = data.oxide_vpc_subnet.default.vpc_id
    subnet_id   = data.oxide_vpc_subnet.default.id
  }]

  user_data = base64encode(<<-EOF
#!/bin/bash
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
chmod 0440 /etc/sudoers.d/ubuntu
EOF
  )
}

resource "oxide_vpc_firewall_rules" "k3srules" {
  vpc_id = oxide_vpc.k3s.id

  rules = [
    {
      action      = "allow"
      description = "Allow inbound HTTP (port 80) from anywhere."
      name        = "allow-http-80"
      direction   = "inbound"
      priority    = 55
      status      = "enabled"
      filters = {
        hosts     = [{ type = "ip_net", value = "0.0.0.0/0" }]
        ports     = ["80"]
        protocols = ["TCP"]
      }
      targets = [{ type = "subnet", value = data.oxide_vpc_subnet.default.name }]
    },
    {
      action      = "allow"
      description = "Allow inbound HTTPS (port 443) from anywhere."
      name        = "allow-https-443"
      direction   = "inbound"
      priority    = 56
      status      = "enabled"
      filters = {
        hosts     = [{ type = "ip_net", value = "0.0.0.0/0" }]
        ports     = ["443"]
        protocols = ["TCP"]
      }
      targets = [{ type = "subnet", value = data.oxide_vpc_subnet.default.name }]
    },
    {
      action      = "allow"
      description = "Allow inbound Kubernetes API (port 6443) from anywhere."
      name        = "allow-k8s-api-6443"
      direction   = "inbound"
      priority    = 50
      status      = "enabled"
      filters = {
        hosts     = [{ type = "ip_net", value = "0.0.0.0/0" }]
        ports     = ["6443"]
        protocols = ["TCP"]
      }
      targets = [{ type = "subnet", value = data.oxide_vpc_subnet.default.name }]
    },
    {
      action      = "allow"
      description = "Allow inbound SSH (port 22) from anywhere."
      name        = "allow-ssh-22"
      direction   = "inbound"
      priority    = 60
      status      = "enabled"
      filters = {
        hosts     = [{ type = "ip_net", value = "0.0.0.0/0" }]
        ports     = ["22"]
        protocols = ["TCP"]
      }
      targets = [{ type = "subnet", value = data.oxide_vpc_subnet.default.name }]
    },
    {
      action      = "allow"
      description = "Allow inbound ICMP (ping) from anywhere."
      name        = "allow-icmp"
      direction   = "inbound"
      priority    = 70
      status      = "enabled"
      filters = {
        hosts     = [{ type = "ip_net", value = "0.0.0.0/0" }]
        protocols = ["ICMP"]
      }
      targets = [{ type = "subnet", value = data.oxide_vpc_subnet.default.name }]
    },
    {
      action      = "allow"
      description = "Allow all inbound traffic from other instances within the VPC."
      name        = "allow-internal-vpc"
      direction   = "inbound"
      priority    = 80
      status      = "enabled"
      filters = {
        hosts = [{ type = "vpc", value = oxide_vpc.k3s.name }]
      }
      targets = [{ type = "subnet", value = data.oxide_vpc_subnet.default.name }]
    }
  ]
}

data "oxide_instance_external_ips" "nodes" {
  for_each    = oxide_instance.nodes
  instance_id = each.value.id
}

data "oxide_instance_external_ips" "nginx_lb" {
  instance_id = oxide_instance.nginx_lb.id
}

locals {
  sorted_instance_keys = sort(keys(oxide_instance.nodes))

  node_ips = [
    for k in local.sorted_instance_keys :
    data.oxide_instance_external_ips.nodes[k].external_ips[0].ip
  ]

  internal_node_ips = [
    for k in local.sorted_instance_keys :
    tolist(oxide_instance.nodes[k].network_interfaces)[0].ip_address
  ]

  nginx_lb_ip  = data.oxide_instance_external_ips.nginx_lb.external_ips[0].ip
  api_endpoint = local.internal_node_ips[0]

  internal_ip = local.internal_node_ips[0]
  external_ip = local.node_ips[0]

  extra_inventory_lines = <<EOT

  lb:
    hosts:
      ${local.nginx_lb_ip}:
        traefik_backend_hosts:
%{for ip in local.internal_node_ips~}
          - ${ip}
%{endfor~}

  k3s_cluster:
    vars:
      api_endpoint: "${local.internal_node_ips[0]}"
      extra_server_args: "--tls-san ${local.internal_node_ips[0]} --tls-san ${local.node_ips[0]}"
EOT
}


resource "local_file" "inventory_yaml" {
  filename = "${path.root}/../../inventory.yml"
  content = templatefile("${path.root}/templates/inventory.yml.tpl", {
    node_ips     = local.node_ips,
    server_count = var.server_count,
    nginx_lb_ip  = local.nginx_lb_ip,
    backend_ips  = local.internal_node_ips,
    ansible_user = var.ansible_user,
    k3s_token    = var.k3s_token,
    k3s_version  = var.k3s_version,
    api_endpoint = local.api_endpoint,
    internal_ip  = local.internal_ip,
    external_ip  = local.external_ip
  })
}

