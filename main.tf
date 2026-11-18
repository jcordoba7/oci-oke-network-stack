locals {
  tags = {
    "managed-by" = "terraform"
    "component"  = "oke-network"
  }

  is_native = var.cni_type == "OCI_VCN_IP_NATIVE"

  subnets = merge({
    api     = { name = var.api_subnet_name, cidr = var.api_subnet_cidr, dns = "okeapi", private = true }
    workers = { name = var.workers_subnet_name, cidr = var.workers_subnet_cidr, dns = "workers", private = true }
    lb      = { name = var.lb_subnet_name, cidr = var.lb_subnet_cidr, dns = "loadbalancer", private = false }
    bastion = { name = var.bastion_subnet_name, cidr = var.bastion_subnet_cidr, dns = "bastion", private = true }
    }, local.is_native ? {
    pods = { name = var.pods_subnet_name, cidr = var.pods_subnet_cidr, dns = "pods", private = true }
  } : {})

  # Integer endpoints permit containment/overlap checks without external tools.
  # try() lets malformed input be reported by variable validation instead.
  ranges = {
    for key, cidr in merge({ vcn = var.vcn_cidr }, { for k, s in local.subnets : k => s.cidr }) : key => {
      first = try(sum([for i, octet in split(".", cidrhost(cidr, 0)) : tonumber(octet) * pow(256, 3 - i)]), -1)
      last  = try(sum([for i, octet in split(".", cidrhost(cidr, -1)) : tonumber(octet) * pow(256, 3 - i)]), -1)
    }
  }
  subnet_pairs = flatten([
    for i, a in sort(keys(local.subnets)) : [
      for j, b in sort(keys(local.subnets)) : { a = a, b = b } if i < j
    ]
  ])
}

resource "terraform_data" "network_validation" {
  input = { vcn = var.vcn_cidr, subnets = local.subnets }

  lifecycle {
    precondition {
      condition = !local.is_native || try(
        cidrnetmask(var.pods_subnet_cidr) != "" &&
        cidrhost(var.pods_subnet_cidr, 0) == split("/", var.pods_subnet_cidr)[0] &&
        tonumber(split("/", var.pods_subnet_cidr)[1]) >= 16 &&
        tonumber(split("/", var.pods_subnet_cidr)[1]) <= 30, false
      )
      error_message = "Para OCI VCN-Native, pods_subnet_cidr debe ser un CIDR IPv4 canónico entre /16 y /30."
    }
    precondition {
      condition     = !local.is_native || try(tonumber(split("/", var.api_subnet_cidr)[1]) <= 29, false)
      error_message = "Para OCI VCN-Native, la subred API debe tener al menos tamaño /29."
    }
    precondition {
      condition = alltrue([
        for k in keys(local.subnets) : local.ranges[k].first >= local.ranges.vcn.first && local.ranges[k].last <= local.ranges.vcn.last
      ])
      error_message = "Todos los CIDR de las subredes deben estar contenidos en el CIDR de la VCN."
    }
    precondition {
      condition = alltrue([
        for p in local.subnet_pairs : local.ranges[p.a].last < local.ranges[p.b].first || local.ranges[p.b].last < local.ranges[p.a].first
      ])
      error_message = "Los CIDR de las subredes no pueden solaparse."
    }
  }
}

resource "oci_core_vcn" "oke" {
  compartment_id = var.compartment_ocid
  display_name   = var.vcn_name
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = var.vcn_dns_label
  freeform_tags  = local.tags

  depends_on = [terraform_data.network_validation]
}

resource "oci_core_internet_gateway" "oke" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-igw"
  enabled        = true
  freeform_tags  = local.tags
}

resource "oci_core_nat_gateway" "oke" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-nat"
  block_traffic  = false
  freeform_tags  = local.tags
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

locals {
  osn_service = one(data.oci_core_services.all.services)
}

resource "oci_core_service_gateway" "oke" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-sgw"
  freeform_tags  = local.tags

  services {
    service_id = local.osn_service.id
  }
}

resource "oci_core_route_table" "private" {
  for_each       = toset([for k, s in local.subnets : k if s.private])
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-${each.key}-rt"
  freeform_tags  = local.tags

  # Example 4: native workers reach OSN only; pod egress uses the pod subnet.
  dynamic "route_rules" {
    for_each = local.is_native && each.key == "workers" ? [] : [1]
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_nat_gateway.oke.id
    }
  }
  route_rules {
    destination       = local.osn_service.cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.oke.id
  }
}

resource "oci_core_route_table" "public_lb" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-lb-rt"
  freeform_tags  = local.tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.oke.id
  }
}

resource "oci_core_dhcp_options" "oke" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-dhcp"
  freeform_tags  = local.tags

  options {
    type        = "DomainNameServer"
    server_type = "VcnLocalPlusInternet"
  }
}

resource "oci_core_subnet" "oke" {
  for_each                   = local.subnets
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.oke.id
  display_name               = each.value.name
  cidr_block                 = each.value.cidr
  dns_label                  = each.value.dns
  prohibit_public_ip_on_vnic = each.value.private
  prohibit_internet_ingress  = each.value.private
  dhcp_options_id            = oci_core_dhcp_options.oke.id
  route_table_id             = each.key == "lb" ? oci_core_route_table.public_lb.id : oci_core_route_table.private[each.key].id
  # Exactly one dedicated list; the permissive VCN default list is not attached.
  security_list_ids = [oci_core_security_list.oke[each.key].id]
  freeform_tags     = local.tags
  # No availability_domain -> regional subnet.
}
