# Oracle Examples 2 and 4: Flannel or OCI VCN-Native, private API/workers, public LB.
# All rules are stateful: response traffic is permitted by connection tracking.
locals {
  api_admin_cidrs = distinct(compact([for c in split(",", var.api_admin_cidrs) : trimspace(c)]))
  lb_source_cidrs = distinct(compact([for c in split(",", var.lb_source_cidrs) : trimspace(c)]))
  listener_ports  = distinct([for p in split(",", var.lb_listener_ports) : tonumber(trimspace(p))])

  api_ingress = concat(
    [for port in [6443, 12250] : { peer = var.workers_subnet_cidr, protocol = "6", min = port, max = port, description = "Workers to OKE API/control plane" }],
    [{ peer = var.workers_subnet_cidr, protocol = "1", icmp = true, description = "Workers path MTU discovery" }],
    [{ peer = var.bastion_subnet_cidr, protocol = "6", min = 6443, max = 6443, description = "Bastion subnet to private Kubernetes API" }],
    local.is_native ? [for port in [6443, 12250] : { peer = var.pods_subnet_cidr, protocol = "6", min = port, max = port, description = "Native pods to OKE API/control plane" }] : [],
    [for cidr in local.api_admin_cidrs : { peer = cidr, protocol = "6", min = 6443, max = 6443, description = "Additional private API administrator network" }]
  )
  api_egress = concat([
    { peer = local.osn_service.cidr_block, peer_type = "SERVICE_CIDR_BLOCK", protocol = "6", description = "Control plane to Oracle Services Network (including TCP 9995)" },
    { peer = local.osn_service.cidr_block, peer_type = "SERVICE_CIDR_BLOCK", protocol = "1", icmp = true, description = "OSN path MTU discovery" },
    { peer = var.workers_subnet_cidr, protocol = "1", icmp = true, description = "Workers path MTU discovery" }
    ], local.is_native ? [
    { peer = var.workers_subnet_cidr, protocol = "6", min = 10250, max = 10250, description = "Control plane to native worker kubelet" },
    { peer = var.pods_subnet_cidr, protocol = "all", description = "Control plane to native pods" }
    ] : [
    { peer = var.workers_subnet_cidr, protocol = "6", description = "Control plane to workers TCP" }
  ])
  # ALL with a port range cannot be represented in OCI security rules. Expand
  # Oracle's ALL/NodePort and ALL/10256 into the port-bearing TCP+UDP protocols.
  lb_backend_rules = flatten([
    for protocol in ["6", "17"] : [
      { protocol = protocol, min = 30000, max = 32767, description = "Load balancer NodePorts" },
      { protocol = protocol, min = 10256, max = 10256, description = "Load balancer kube-proxy health checks" }
    ]
  ])
  workers_ingress = concat(local.is_native ? [
    { peer = var.api_subnet_cidr, protocol = "6", min = 10250, max = 10250, description = "Control plane to native worker kubelet" }
    ] : [
    { peer = var.workers_subnet_cidr, protocol = "all", description = "Flannel pod-to-pod and worker-to-worker" },
    { peer = var.api_subnet_cidr, protocol = "6", description = "Control plane to worker TCP" }
    ], [
    { peer = "0.0.0.0/0", protocol = "1", icmp = true, description = "Path MTU discovery" }
    ], [for r in local.lb_backend_rules : merge(r, { peer = var.lb_subnet_cidr })],
    var.allow_bastion_ssh ? [{ peer = var.bastion_subnet_cidr, protocol = "6", min = 22, max = 22, description = "Optional SSH from Bastion subnet" }] : []
  )
  workers_egress = concat(local.is_native ? [
    { peer = var.pods_subnet_cidr, protocol = "all", description = "Workers to native pods" },
    { peer = "0.0.0.0/0", protocol = "1", icmp = true, description = "Native workers path MTU discovery" }
    ] : [
    { peer = var.workers_subnet_cidr, protocol = "all", description = "Flannel pod-to-pod and worker-to-worker" },
    ], [
    { peer = local.osn_service.cidr_block, peer_type = "SERVICE_CIDR_BLOCK", protocol = "6", description = "Workers to Oracle Services Network" }
    ], [for port in [6443, 12250] : { peer = var.api_subnet_cidr, protocol = "6", min = port, max = port, description = "Workers to OKE API/control plane" }],
    !local.is_native && var.allow_worker_internet_tcp ? [{ peer = "0.0.0.0/0", protocol = "6", description = "Optional outbound TCP through NAT" }] : []
  )
  lb_ingress = [for pair in setproduct(local.lb_source_cidrs, local.listener_ports) : {
    peer = pair[0], protocol = "6", min = pair[1], max = pair[1], description = "Public LB configurable TCP listener"
  }]
  lb_egress = [for r in local.lb_backend_rules : merge(r, { peer = var.workers_subnet_cidr })]
  bastion_egress = concat(
    [{ peer = var.api_subnet_cidr, protocol = "6", min = 6443, max = 6443, description = "Bastion to private API" }],
    var.allow_bastion_ssh ? [{ peer = var.workers_subnet_cidr, protocol = "6", min = 22, max = 22, description = "Optional SSH to managed nodes" }] : []
  )
  pods_ingress = [for cidr in [var.workers_subnet_cidr, var.api_subnet_cidr, var.pods_subnet_cidr] : {
    peer = cidr, protocol = "all", description = "Workers, API and native pods to pods"
  }]
  pods_egress = concat([
    { peer = var.pods_subnet_cidr, protocol = "all", description = "Native pod-to-pod" },
    { peer = local.osn_service.cidr_block, peer_type = "SERVICE_CIDR_BLOCK", protocol = "1", icmp = true, description = "Native pods OSN path MTU discovery" },
    { peer = local.osn_service.cidr_block, peer_type = "SERVICE_CIDR_BLOCK", protocol = "6", description = "Native pods to Oracle Services Network" }
    ], [for port in [6443, 12250] : { peer = var.api_subnet_cidr, protocol = "6", min = port, max = port, description = "Native pods to OKE API/control plane" }],
    var.allow_pod_internet_https ? [{ peer = "0.0.0.0/0", protocol = "6", min = 443, max = 443, description = "Optional native pod HTTPS through NAT" }] : []
  )
  security = merge({
    api     = { ingress = local.api_ingress, egress = local.api_egress }
    workers = { ingress = local.workers_ingress, egress = local.workers_egress }
    lb      = { ingress = local.lb_ingress, egress = local.lb_egress }
    bastion = { ingress = [], egress = local.bastion_egress }
  }, local.is_native ? { pods = { ingress = local.pods_ingress, egress = local.pods_egress } } : {})
}

resource "oci_core_security_list" "oke" {
  for_each       = local.security
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke.id
  display_name   = "${var.name_prefix}-${each.key}-sl"
  freeform_tags  = local.tags

  dynamic "ingress_security_rules" {
    for_each = each.value.ingress
    iterator = rule
    content {
      source      = rule.value.peer
      source_type = try(rule.value.peer_type, "CIDR_BLOCK")
      protocol    = rule.value.protocol
      description = rule.value.description
      stateless   = false

      dynamic "tcp_options" {
        for_each = rule.value.protocol == "6" && can(rule.value.min) ? [rule.value] : []
        content {
          min = tcp_options.value.min
          max = tcp_options.value.max
        }
      }
      dynamic "udp_options" {
        for_each = rule.value.protocol == "17" && can(rule.value.min) ? [rule.value] : []
        content {
          min = udp_options.value.min
          max = udp_options.value.max
        }
      }
      dynamic "icmp_options" {
        for_each = try(rule.value.icmp, false) ? [1] : []
        content {
          type = 3
          code = 4
        }
      }
    }
  }

  dynamic "egress_security_rules" {
    for_each = each.value.egress
    iterator = rule
    content {
      destination      = rule.value.peer
      destination_type = try(rule.value.peer_type, "CIDR_BLOCK")
      protocol         = rule.value.protocol
      description      = rule.value.description
      stateless        = false

      dynamic "tcp_options" {
        for_each = rule.value.protocol == "6" && can(rule.value.min) ? [rule.value] : []
        content {
          min = tcp_options.value.min
          max = tcp_options.value.max
        }
      }
      dynamic "udp_options" {
        for_each = rule.value.protocol == "17" && can(rule.value.min) ? [rule.value] : []
        content {
          min = udp_options.value.min
          max = udp_options.value.max
        }
      }
      dynamic "icmp_options" {
        for_each = try(rule.value.icmp, false) ? [1] : []
        content {
          type = 3
          code = 4
        }
      }
    }
  }
}
