# Terraform >= 1.7 for mock_provider. Tests never contact or change an OCI tenancy.
mock_provider "oci" {
  mock_data "oci_core_services" {
    defaults = {
      services = [{
        id          = "ocid1.service.oc1.bog.mock"
        name        = "All BOG Services In Oracle Services Network"
        cidr_block  = "all-bog-services-in-oracle-services-network"
        description = "Mock regional service, no OCI calls"
      }]
    }
  }
}

variables {
  compartment_ocid = "ocid1.compartment.oc1..test"
}

run "default_network" {
  command = apply

  assert {
    condition = (
      length(oci_core_subnet.oke) == 4 &&
      alltrue([for k in ["api", "workers", "bastion"] : oci_core_subnet.oke[k].prohibit_public_ip_on_vnic && oci_core_subnet.oke[k].prohibit_internet_ingress]) &&
      !oci_core_subnet.oke["lb"].prohibit_public_ip_on_vnic && !oci_core_subnet.oke["lb"].prohibit_internet_ingress
    )
    error_message = "Sólo la subred del LB debe ser pública."
  }
  assert {
    condition     = length(oci_core_route_table.private) == 3 && alltrue([for rt in oci_core_route_table.private : length(rt.route_rules) == 2]) && length(oci_core_route_table.public_lb.route_rules) == 1
    error_message = "Las subredes privadas requieren NAT y OSN; el LB requiere IGW."
  }
  assert {
    condition     = alltrue([for s in oci_core_subnet.oke : length(s.security_list_ids) == 1])
    error_message = "Cada subred debe usar únicamente su lista dedicada."
  }
  assert {
    condition     = length(oci_core_security_list.oke["api"].ingress_security_rules) == 4 && alltrue([for r in oci_core_security_list.oke["api"].ingress_security_rules : r.source != "0.0.0.0/0"])
    error_message = "El API no debe tener una apertura general a Internet."
  }
  assert {
    condition     = length(oci_core_security_list.oke["bastion"].ingress_security_rules) == 0 && length(oci_core_security_list.oke["bastion"].egress_security_rules) == 1
    error_message = "Bastion no debe aceptar ingress ni habilitar SSH por defecto."
  }
  assert {
    condition     = length(oci_core_security_list.oke["lb"].ingress_security_rules) == 2 && length(oci_core_security_list.oke["lb"].egress_security_rules) == 4
    error_message = "Se esperan HTTP/HTTPS TCP y salida TCP/UDP para NodePorts y health checks."
  }
  assert {
    condition = alltrue(flatten([for s in oci_core_security_list.oke : concat(
      [for r in s.ingress_security_rules : !r.stateless],
      [for r in s.egress_security_rules : !r.stateless]
    )]))
    error_message = "Todas las reglas de la referencia deben ser stateful."
  }
  assert {
    condition = alltrue([for port in [6443, 12250] : anytrue([
      for r in oci_core_security_list.oke["api"].ingress_security_rules :
      r.source == var.workers_subnet_cidr && r.protocol == "6" && try(r.tcp_options[0].min == port && r.tcp_options[0].max == port, false)
    ])])
    error_message = "Workers deben llegar al API por TCP 6443 y 12250."
  }
  assert {
    condition = alltrue([for protocol in ["6", "17"] : anytrue([
      for r in oci_core_security_list.oke["workers"].ingress_security_rules :
      r.source == var.lb_subnet_cidr && r.protocol == protocol && try(
        protocol == "6" ? r.tcp_options[0].min == 30000 && r.tcp_options[0].max == 32767 : r.udp_options[0].min == 30000 && r.udp_options[0].max == 32767,
        false
      )
    ])])
    error_message = "NodePorts TCP/UDP 30000–32767 deben estar limitados a la subred LB."
  }
}

run "custom_network_and_names" {
  command = apply
  variables {
    vcn_name            = "vcn-cliente-pruebas"
    vcn_cidr            = "172.20.0.0/16"
    api_subnet_name     = "api-cliente"
    api_subnet_cidr     = "172.20.0.0/28"
    workers_subnet_name = "workers-cliente"
    workers_subnet_cidr = "172.20.20.0/24"
    lb_subnet_name      = "lb-cliente"
    lb_subnet_cidr      = "172.20.10.0/24"
    bastion_subnet_name = "bastion-cliente"
    bastion_subnet_cidr = "172.20.40.0/24"
  }
  assert {
    condition     = oci_core_vcn.oke.display_name == "vcn-cliente-pruebas" && oci_core_subnet.oke["api"].display_name == "api-cliente" && oci_core_subnet.oke["workers"].cidr_block == "172.20.20.0/24"
    error_message = "Los nombres y CIDR deben conservar los valores elegidos."
  }
}

run "optional_rules" {
  command = apply
  variables {
    allow_bastion_ssh         = true
    allow_worker_internet_tcp = false
    api_admin_cidrs           = "192.168.20.0/24, 192.168.30.0/24"
    lb_source_cidrs           = "192.0.2.0/24, 198.51.100.0/24"
    lb_listener_ports         = "443,8443"
  }
  assert {
    condition     = length(oci_core_security_list.oke["api"].ingress_security_rules) == 6 && length(oci_core_security_list.oke["lb"].ingress_security_rules) == 4 && length(oci_core_security_list.oke["bastion"].egress_security_rules) == 2
    error_message = "Los CIDR/puertos adicionales y SSH opcional deben expandirse correctamente."
  }
  assert {
    condition     = alltrue([for r in oci_core_security_list.oke["workers"].egress_security_rules : r.destination != "0.0.0.0/0"])
    error_message = "Al deshabilitar salida TCP opcional no debe quedar egress a Internet."
  }
}

run "reject_overlap" {
  command = plan
  variables {
    workers_subnet_cidr = "10.0.0.0/24"
  }
  expect_failures = [terraform_data.network_validation]
}

run "reject_outside_vcn" {
  command = plan
  variables {
    bastion_subnet_cidr = "10.99.3.0/24"
  }
  expect_failures = [terraform_data.network_validation]
}

run "reject_host_bits" {
  command = plan
  variables {
    api_subnet_cidr = "10.0.0.1/28"
  }
  expect_failures = [var.api_subnet_cidr]
}

run "reject_invalid_listener_port" {
  command = plan
  variables {
    lb_listener_ports = "443,65536"
  }
  expect_failures = [var.lb_listener_ports]
}

run "reject_invalid_dns_label" {
  command = plan
  variables {
    vcn_dns_label = "invalid-label"
  }
  expect_failures = [var.vcn_dns_label]
}

run "native_network" {
  command = apply
  variables {
    cni_type = "OCI_VCN_IP_NATIVE"
  }
  assert {
    condition     = length(oci_core_subnet.oke) == 5 && oci_core_subnet.oke["pods"].prohibit_public_ip_on_vnic && oci_core_subnet.oke["pods"].prohibit_internet_ingress && length(oci_core_security_list.oke) == 5
    error_message = "VCN-Native debe crear la quinta subred privada y su lista de seguridad."
  }
  assert {
    condition = (
      length(oci_core_route_table.private["workers"].route_rules) == 1 &&
      alltrue([for r in oci_core_route_table.private["workers"].route_rules : r.destination_type == "SERVICE_CIDR_BLOCK"]) &&
      length(oci_core_route_table.private["pods"].route_rules) == 2
    )
    error_message = "Workers nativos sólo usan SGW; pods usan NAT y SGW."
  }
  assert {
    condition = (
      anytrue([for r in oci_core_security_list.oke["api"].egress_security_rules : r.destination == var.workers_subnet_cidr && r.protocol == "6" && try(r.tcp_options[0].min == 10250 && r.tcp_options[0].max == 10250, false)]) &&
      anytrue([for r in oci_core_security_list.oke["workers"].ingress_security_rules : r.source == var.api_subnet_cidr && r.protocol == "6" && try(r.tcp_options[0].min == 10250 && r.tcp_options[0].max == 10250, false)]) &&
      alltrue([for r in oci_core_security_list.oke["api"].egress_security_rules : r.destination != var.workers_subnet_cidr || r.protocol != "6" || length(r.tcp_options) == 1])
    )
    error_message = "El API debe acceder a workers nativos por kubelet TCP/10250, sin TCP/ALL."
  }
  assert {
    condition = alltrue([for port in [6443, 12250] : anytrue([
      for r in oci_core_security_list.oke["api"].ingress_security_rules : r.source == var.pods_subnet_cidr && r.protocol == "6" && try(r.tcp_options[0].min == port && r.tcp_options[0].max == port, false)
    ])])
    error_message = "Los pods nativos deben tener acceso al API por 6443 y 12250."
  }
  assert {
    condition = (
      length(oci_core_security_list.oke["pods"].ingress_security_rules) == 3 &&
      alltrue([for cidr in [var.workers_subnet_cidr, var.api_subnet_cidr, var.pods_subnet_cidr] : anytrue([for r in oci_core_security_list.oke["pods"].ingress_security_rules : r.source == cidr && r.protocol == "all"])]) &&
      length(oci_core_security_list.oke["pods"].egress_security_rules) == 6
    )
    error_message = "La lista de pods debe cubrir workers, API, otros pods, OSN y HTTPS opcional."
  }
  assert {
    condition     = alltrue([for r in oci_core_security_list.oke["workers"].egress_security_rules : r.destination != "0.0.0.0/0" || r.protocol != "6"])
    error_message = "VCN-Native no debe heredar salida TCP general de workers de Flannel."
  }
  assert {
    condition     = output.oke_network_inputs.cni_type == "OCI_VCN_IP_NATIVE" && output.oke_network_inputs.pods_subnet_id == oci_core_subnet.oke["pods"].id
    error_message = "Los outputs deben indicar el CNI y el OCID de pods correctos."
  }
}

run "native_custom_network_without_pod_internet" {
  command = apply
  variables {
    cni_type                 = "OCI_VCN_IP_NATIVE"
    vcn_cidr                 = "172.20.0.0/16"
    api_subnet_cidr          = "172.20.0.0/29"
    workers_subnet_cidr      = "172.20.1.0/24"
    lb_subnet_cidr           = "172.20.2.0/24"
    bastion_subnet_cidr      = "172.20.3.0/24"
    pods_subnet_cidr         = "172.20.32.0/19"
    pods_subnet_name         = "pods-cliente"
    allow_pod_internet_https = false
  }
  assert {
    condition     = oci_core_subnet.oke["pods"].display_name == "pods-cliente" && oci_core_subnet.oke["pods"].cidr_block == "172.20.32.0/19" && alltrue([for r in oci_core_security_list.oke["pods"].egress_security_rules : r.destination != "0.0.0.0/0"])
    error_message = "VCN-Native debe respetar parámetros propios y permitir deshabilitar HTTPS de pods."
  }
}

run "reject_native_pods_overlap" {
  command = plan
  variables {
    cni_type         = "OCI_VCN_IP_NATIVE"
    pods_subnet_cidr = "10.0.0.0/19"
  }
  expect_failures = [terraform_data.network_validation]
}

run "reject_native_pods_outside_vcn" {
  command = plan
  variables {
    cni_type         = "OCI_VCN_IP_NATIVE"
    pods_subnet_cidr = "10.99.32.0/19"
  }
  expect_failures = [terraform_data.network_validation]
}

run "reject_native_pods_host_bits" {
  command = plan
  variables {
    cni_type         = "OCI_VCN_IP_NATIVE"
    pods_subnet_cidr = "10.0.32.1/19"
  }
  expect_failures = [terraform_data.network_validation]
}

run "reject_invalid_cni" {
  command = plan
  variables {
    cni_type = "POD_NATIVE"
  }
  expect_failures = [var.cni_type]
}

run "reject_native_api_too_small" {
  command = plan
  variables {
    cni_type        = "OCI_VCN_IP_NATIVE"
    api_subnet_cidr = "10.0.0.0/30"
  }
  expect_failures = [terraform_data.network_validation]
}

run "flannel_ignores_unused_pods" {
  command = apply
  variables {
    cni_type         = "FLANNEL_OVERLAY"
    pods_subnet_cidr = "unused"
  }
  assert {
    condition     = length(oci_core_subnet.oke) == 4 && !contains(keys(oci_core_security_list.oke), "pods") && !contains(keys(oci_core_route_table.private), "pods") && output.oke_network_inputs.pods_subnet_id == null && output.oke_network_inputs.cni_type == "FLANNEL_OVERLAY"
    error_message = "Flannel no debe crear ni validar una subred VCN de pods que no utiliza."
  }
}
