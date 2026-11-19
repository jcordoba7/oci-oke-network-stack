variable "compartment_ocid" {
  description = "OCID del compartment existente donde se creará toda la red."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^ocid1\\.(compartment|tenancy)\\.", var.compartment_ocid))
    error_message = "Indica un OCID válido de compartment (o del root compartment/tenancy)."
  }
}

variable "region" {
  description = "Resource Manager proporciona la región del stack. Sin valor predeterminado; en CLI debes indicarla explícitamente."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.region)) > 0
    error_message = "La región no puede estar vacía."
  }
}

variable "cni_type" {
  description = "FLANNEL_OVERLAY: Flannel. OCI_VCN_IP_NATIVE: OCI VCN-Native Pod Networking. Debe coincidir con el CNI del nuevo cluster."
  type        = string
  nullable    = false
  default     = "FLANNEL_OVERLAY"

  validation {
    condition     = contains(["FLANNEL_OVERLAY", "OCI_VCN_IP_NATIVE"], var.cni_type)
    error_message = "Selecciona FLANNEL_OVERLAY u OCI_VCN_IP_NATIVE."
  }
}

variable "name_prefix" {
  description = "Prefijo de gateways, tablas de rutas, DHCP y listas de seguridad."
  type        = string
  nullable    = false
  default     = "oke-net"

  validation {
    condition     = length(trimspace(var.name_prefix)) > 0 && length(var.name_prefix) <= 100 && length(regexall("[\\r\\n]", var.name_prefix)) == 0
    error_message = "El nombre debe tener entre 1 y 100 caracteres y no contener saltos de línea."
  }
}

variable "vcn_name" {
  description = "Nombre visible de la VCN nueva."
  type        = string
  nullable    = false
  default     = "vcn-oke"

  validation {
    condition     = length(trimspace(var.vcn_name)) > 0 && length(var.vcn_name) <= 100 && length(regexall("[\\r\\n]", var.vcn_name)) == 0
    error_message = "El nombre debe tener entre 1 y 100 caracteres y no contener saltos de línea."
  }
}

variable "vcn_cidr" {
  description = "IPv4 canónico /16 a /30. Debe contener todas las subredes."
  type        = string
  nullable    = false
  default     = "10.0.0.0/16"

  validation {
    condition     = try(cidrnetmask(var.vcn_cidr) != "" && cidrhost(var.vcn_cidr, 0) == split("/", var.vcn_cidr)[0] && tonumber(split("/", var.vcn_cidr)[1]) >= 16 && tonumber(split("/", var.vcn_cidr)[1]) <= 30, false)
    error_message = "Usa un CIDR IPv4 canónico con prefijo entre /16 y /30 (sin bits de host)."
  }
}

variable "vcn_dns_label" {
  description = "1 a 15 caracteres alfanuméricos; debe comenzar con una letra."
  type        = string
  nullable    = false
  default     = "okevcn"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,14}$", var.vcn_dns_label))
    error_message = "Etiqueta DNS: 1 a 15 caracteres alfanuméricos; debe comenzar con una letra."
  }
}

variable "api_subnet_name" {
  description = "Subred regional privada del endpoint de Kubernetes."
  type        = string
  nullable    = false
  default     = "subnet-oke-api-private"

  validation {
    condition     = length(trimspace(var.api_subnet_name)) > 0 && length(var.api_subnet_name) <= 100 && length(regexall("[\\r\\n]", var.api_subnet_name)) == 0
    error_message = "El nombre debe tener entre 1 y 100 caracteres y no contener saltos de línea."
  }
}

variable "api_subnet_cidr" {
  description = "Privada. /28 predeterminado da más espacio que el /30 del ejemplo."
  type        = string
  nullable    = false
  default     = "10.0.0.0/28"

  validation {
    condition     = try(cidrnetmask(var.api_subnet_cidr) != "" && cidrhost(var.api_subnet_cidr, 0) == split("/", var.api_subnet_cidr)[0] && tonumber(split("/", var.api_subnet_cidr)[1]) >= 16 && tonumber(split("/", var.api_subnet_cidr)[1]) <= 30, false)
    error_message = "Usa un CIDR IPv4 canónico con prefijo entre /16 y /30 (sin bits de host)."
  }
}

variable "workers_subnet_name" {
  description = "Subred regional privada de nodos OKE."
  type        = string
  nullable    = false
  default     = "subnet-oke-workers-private"

  validation {
    condition     = length(trimspace(var.workers_subnet_name)) > 0 && length(var.workers_subnet_name) <= 100 && length(regexall("[\\r\\n]", var.workers_subnet_name)) == 0
    error_message = "El nombre debe tener entre 1 y 100 caracteres y no contener saltos de línea."
  }
}

variable "workers_subnet_cidr" {
  description = "Debe pertenecer a la VCN y no solaparse con otra subred."
  type        = string
  nullable    = false
  default     = "10.0.1.0/24"

  validation {
    condition     = try(cidrnetmask(var.workers_subnet_cidr) != "" && cidrhost(var.workers_subnet_cidr, 0) == split("/", var.workers_subnet_cidr)[0] && tonumber(split("/", var.workers_subnet_cidr)[1]) >= 16 && tonumber(split("/", var.workers_subnet_cidr)[1]) <= 30, false)
    error_message = "Usa un CIDR IPv4 canónico con prefijo entre /16 y /30 (sin bits de host)."
  }
}

variable "lb_subnet_name" {
  description = "Subred regional pública para Load Balancers."
  type        = string
  nullable    = false
  default     = "subnet-oke-lb-public"

  validation {
    condition     = length(trimspace(var.lb_subnet_name)) > 0 && length(var.lb_subnet_name) <= 100 && length(regexall("[\\r\\n]", var.lb_subnet_name)) == 0
    error_message = "El nombre debe tener entre 1 y 100 caracteres y no contener saltos de línea."
  }
}

variable "lb_subnet_cidr" {
  description = "Debe pertenecer a la VCN y no solaparse con otra subred."
  type        = string
  nullable    = false
  default     = "10.0.2.0/24"

  validation {
    condition     = try(cidrnetmask(var.lb_subnet_cidr) != "" && cidrhost(var.lb_subnet_cidr, 0) == split("/", var.lb_subnet_cidr)[0] && tonumber(split("/", var.lb_subnet_cidr)[1]) >= 16 && tonumber(split("/", var.lb_subnet_cidr)[1]) <= 30, false)
    error_message = "Usa un CIDR IPv4 canónico con prefijo entre /16 y /30 (sin bits de host)."
  }
}

variable "bastion_subnet_name" {
  description = "Sólo crea la subred; no crea el servicio Bastion ni una VM."
  type        = string
  nullable    = false
  default     = "subnet-oke-bastion-private"

  validation {
    condition     = length(trimspace(var.bastion_subnet_name)) > 0 && length(var.bastion_subnet_name) <= 100 && length(regexall("[\\r\\n]", var.bastion_subnet_name)) == 0
    error_message = "El nombre debe tener entre 1 y 100 caracteres y no contener saltos de línea."
  }
}

variable "bastion_subnet_cidr" {
  description = "Debe pertenecer a la VCN y no solaparse con otra subred."
  type        = string
  nullable    = false
  default     = "10.0.3.0/24"

  validation {
    condition     = try(cidrnetmask(var.bastion_subnet_cidr) != "" && cidrhost(var.bastion_subnet_cidr, 0) == split("/", var.bastion_subnet_cidr)[0] && tonumber(split("/", var.bastion_subnet_cidr)[1]) >= 16 && tonumber(split("/", var.bastion_subnet_cidr)[1]) <= 30, false)
    error_message = "Usa un CIDR IPv4 canónico con prefijo entre /16 y /30 (sin bits de host)."
  }
}

variable "pods_subnet_name" {
  description = "Sólo para OCI VCN-Native: subred privada y regional de IP de pods."
  type        = string
  nullable    = false
  default     = "subnet-oke-pods-private"

  validation {
    condition     = length(trimspace(var.pods_subnet_name)) > 0 && length(var.pods_subnet_name) <= 100 && length(regexall("[\\r\\n]", var.pods_subnet_name)) == 0
    error_message = "El nombre debe tener entre 1 y 100 caracteres y no contener saltos de línea."
  }
}

variable "pods_subnet_cidr" {
  description = "Sólo para OCI VCN-Native: debe pertenecer a la VCN y no solaparse con otras subredes. Dimensiona según nodos y pods por nodo."
  type        = string
  nullable    = false
  default     = "10.0.32.0/19"
}

variable "api_admin_cidrs" {
  description = "IPv4 separados por comas. Sólo habilita TCP/6443; requiere conectividad privada existente. Vacío: sólo workers y subred Bastion."
  type        = string
  nullable    = false
  default     = ""

  validation {
    condition     = alltrue([for c in compact([for value in split(",", var.api_admin_cidrs) : trimspace(value)]) : can(cidrnetmask(c))])
    error_message = "Usa CIDR IPv4 válidos separados por comas."
  }
}

variable "lb_source_cidrs" {
  description = "IPv4 separados por comas para las reglas de ingreso TCP del LB."
  type        = string
  nullable    = false
  default     = "0.0.0.0/0"

  validation {
    condition     = alltrue([for c in compact([for value in split(",", var.lb_source_cidrs) : trimspace(value)]) : can(cidrnetmask(c))]) && length(compact([for c in split(",", var.lb_source_cidrs) : trimspace(c)])) > 0
    error_message = "Usa CIDR IPv4 válidos separados por comas."
  }
}

variable "lb_listener_ports" {
  description = "Puertos separados por comas, entre 1 y 65535. No crea listeners ni un LB."
  type        = string
  nullable    = false
  default     = "80,443"

  validation {
    condition     = try(alltrue([for p in split(",", var.lb_listener_ports) : tonumber(trimspace(p)) >= 1 && tonumber(trimspace(p)) <= 65535 && floor(tonumber(trimspace(p))) == tonumber(trimspace(p))]), false)
    error_message = "Usa puertos enteros entre 1 y 65535, separados por comas."
  }
}

variable "allow_worker_internet_tcp" {
  description = "Sólo Flannel: habilita TCP/ALL a 0.0.0.0/0 por NAT. OCI VCN-Native no crea esta ruta ni aplica esta opción."
  type        = bool
  nullable    = false
  default     = true
}

variable "allow_pod_internet_https" {
  description = "Sólo OCI VCN-Native: habilita la regla opcional TCP/443 a 0.0.0.0/0 por NAT."
  type        = bool
  nullable    = false
  default     = true
}

variable "allow_bastion_ssh" {
  description = "Reglas opcionales TCP/22 entre Bastion y workers. No abre SSH desde Internet."
  type        = bool
  nullable    = false
  default     = false
}
