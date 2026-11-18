output "vcn_id" {
  description = "OCID de la VCN creada."
  value       = oci_core_vcn.oke.id
}

output "subnets" {
  description = "Subredes regionales creadas, CIDR, visibilidad y OCID."
  value = { for k, s in oci_core_subnet.oke : k => {
    id = s.id, name = s.display_name, cidr = s.cidr_block, private = s.prohibit_public_ip_on_vnic
  } }
}

output "security_list_ids" {
  description = "Listas de seguridad dedicadas por rol."
  value       = { for k, s in oci_core_security_list.oke : k => s.id }
}

output "route_table_ids" {
  description = "Tablas de rutas por rol."
  value       = merge({ for k, rt in oci_core_route_table.private : k => rt.id }, { lb = oci_core_route_table.public_lb.id })
}

output "gateway_ids" {
  description = "Internet Gateway, NAT Gateway y Service Gateway."
  value = {
    internet = oci_core_internet_gateway.oke.id
    nat      = oci_core_nat_gateway.oke.id
    service  = oci_core_service_gateway.oke.id
  }
}

output "oke_network_inputs" {
  description = "Entradas de red y CNI seleccionado para un nuevo cluster OKE privado (no crea el cluster)."
  value = {
    compartment_id       = var.compartment_ocid
    region               = var.region
    vcn_id               = oci_core_vcn.oke.id
    oke_api_subnet_id    = oci_core_subnet.oke["api"].id
    workers_subnet_id    = oci_core_subnet.oke["workers"].id
    public_subnet_id     = oci_core_subnet.oke["lb"].id
    bastion_subnet_id    = oci_core_subnet.oke["bastion"].id
    is_public_ip_enabled = false
    cni_type             = var.cni_type
    pods_subnet_id       = try(oci_core_subnet.oke["pods"].id, null)
  }
}
