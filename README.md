# Stack de red OKE: Flannel u OCI VCN-Native

Versión **1.1.0** para OCI Resource Manager. Crea una VCN nueva con API de Kubernetes privado, workers privados y subred pública para Load Balancers. El selector `cni_type` elige la topología y las reglas de los ejemplos 2 y 4 de Oracle. Está orientado a OKE con managed worker nodes.

Este stack crea **sólo la red**. El cluster y sus node pools se crean después con el mismo CNI.

## Selector de CNI

| Configuración | Flannel | OCI VCN-Native Pod Networking |
|---|---|---|
| `cni_type` | `FLANNEL_OVERLAY` (default) | `OCI_VCN_IP_NATIVE` |
| Subredes | API, workers, LB y Bastion | Las anteriores + pods |
| IP de pods | Overlay; no es una subred VCN | Subred privada de pods en la VCN |
| Rutas de workers | NAT + Service Gateway | Sólo Service Gateway |
| Rutas de pods | No aplica en este stack | NAT + Service Gateway |
| API → workers | TCP todos + ICMP 3/4 | TCP 10250 + ICMP 3/4 |
| Salida Internet opcional | TCP de workers por NAT | HTTPS TCP/443 de pods por NAT |

El formulario muestra nombre, CIDR y opción de salida de pods sólo con `OCI_VCN_IP_NATIVE`. La opción de salida TCP general de workers sólo se muestra y aplica en Flannel. Terraform valida estas condiciones independientemente del formulario.

Ejemplo de variables para Native:

```hcl
cni_type = "OCI_VCN_IP_NATIVE"
pods_subnet_name = "subnet-oke-pods-private"
pods_subnet_cidr = "10.0.32.0/19"
allow_pod_internet_https = true
```

Los valores del selector son los identificadores OCI exactos de la tabla; no se acepta `POD_NATIVE`.

## Recursos y parámetros

| Recurso | Valor predeterminado |
|---|---|
| VCN | `vcn-oke`, `10.0.0.0/16`, DNS habilitado |
| API | `subnet-oke-api-private`, `10.0.0.0/28`, privada regional |
| Workers | `subnet-oke-workers-private`, `10.0.1.0/24`, privada regional |
| LB | `subnet-oke-lb-public`, `10.0.2.0/24`, pública regional |
| Bastion | `subnet-oke-bastion-private`, `10.0.3.0/24`, privada regional |
| Pods (sólo Native) | `subnet-oke-pods-private`, `10.0.32.0/19`, privada regional |

Incluye Internet Gateway, NAT Gateway, Service Gateway para todos los servicios regionales de OSN, una tabla de rutas y una lista de seguridad dedicada por subred, y opciones DHCP con Internet and VCN Resolver. Todas las reglas son stateful.

Se puede seleccionar un compartment existente y editar los nombres y CIDR de VCN/subredes. `name_prefix` determina los nombres de gateways, rutas, listas y DHCP. La etiqueta DNS de VCN es configurable; las de subred son `okeapi`, `workers`, `loadbalancer`, `bastion` y `pods`.

No crea OKE, node pools, LB, listeners, Bastion, sesiones, bases de datos, Vault, IAM, VPN ni NSG. Usa **listas de seguridad**, como las referencias. No modifica los recursos predeterminados generados por OCI para la VCN; las subredes creadas no adjuntan la Security List predeterminada.

## Desplegar en Resource Manager

1. En la región de prueba, abre **Developer Services → Resource Manager → Stacks → Create stack**.
2. Selecciona una fuente **GitHub** con este repositorio y directorio de trabajo raíz. También puedes cargar el ZIP generado con `python scripts/package_stack.py`, disponible en `dist/oke-network-resource-manager-v1.1.0.zip`. Los archivos Terraform y `schema.yaml` están en la raíz del ZIP.
3. Selecciona Terraform **1.5 o superior** disponible en Resource Manager.
4. Elige el compartment de destino y el CNI. Define nombres, CIDR y opciones. La región se completa con la del stack.
5. Ejecuta **Plan**, revisa los recursos propuestos y después **Apply**.
6. Crea OKE con el **mismo CNI** y las subredes de los outputs.

El compartment de recursos puede diferir del que guarda el stack. Se necesitan permisos de red en el destino y los habituales de Resource Manager, una región suscrita y límites disponibles. Resource Manager gestiona autenticación y estado; no hay credenciales ni backend en el ZIP. El ejemplo de CLI usa Bogotá (`sa-bogota-1`).

## Reglas de seguridad

Reglas comunes: workers → API TCP/6443 y 12250; ICMP 3/4 desde workers al API y desde el API a workers; API y workers → OSN TCP; API → OSN ICMP 3/4. Workers aceptan ICMP 3/4 desde cualquier origen.

La subred LB permite ingreso TCP de `lb_source_cidrs` a `lb_listener_ports` (default `0.0.0.0/0` y `80,443`). LB → workers permite TCP/UDP 30000–32767 y 10256, con reglas de ingreso correspondientes en workers. Son permisos preparatorios: no se crea el LB.

Bastion no tiene reglas de ingreso; permite salida al API TCP/6443. El API acepta ese origen. `allow_bastion_ssh=false` por defecto; al habilitarlo se añade TCP/22 en ambos extremos entre Bastion y workers. No se crean sesiones ni se garantizan requisitos de agente, identidad o sistema operativo.

`api_admin_cidrs` permite sumar orígenes IPv4 separados por comas para TCP/6443 y viene vacío. Esto **no crea conectividad** al endpoint privado: se necesita Bastion, VPN/FastConnect, peering o un cliente con acceso privado.

### Flannel

- ALL/ALL entre workers para tráfico de nodos y overlay.
- API → workers TCP todos.
- `allow_worker_internet_tcp=true` permite la salida TCP opcional de workers a Internet por NAT.
- No se crea subred, lista ni rutas de pods.

### OCI VCN-Native

- API → workers se limita a TCP/10250; no hereda TCP/ALL de Flannel.
- Pods → API TCP/6443 y 12250.
- API → pods ALL/ALL.
- Workers → pods ALL/ALL y salida ICMP 3/4 a cualquier destino.
- Pods aceptan ALL/ALL desde workers, API y otros pods.
- Pods salen hacia otros pods ALL/ALL, OSN TCP todos e ICMP 3/4, y API TCP/6443 y 12250.
- `allow_pod_internet_https=true` agrega salida TCP/443 a Internet por NAT; se puede deshabilitar.
- No hay ALL/ALL entre workers ni salida TCP general de workers a Internet. La opción anterior `allow_worker_internet_tcp` se ignora en Native, aunque conserve `true` en variables guardadas.

La tabla de workers Native sólo tiene OSN; la tabla de pods tiene NAT + OSN. Las reglas del LB siguen el camino por NodePorts de la referencia, no un patrón de balanceo directo a IP de pods.

Las listas y NSG son **aditivos**: agregar otros controles puede ampliar los permisos. Coordina la gestión del Native Ingress Controller para que no altere estas listas fuera de Terraform.

## Validaciones y dimensionamiento

Se validan CNI permitido, CIDR IPv4 canónicos `/16` a `/30`, contención en la VCN, ausencia de solapes, nombres, DNS y puertos. Native valida además su CIDR de pods y exige API de al menos `/29`; el `/28` predeterminado sirve para ambos CNI.

En Flannel, `pods_subnet_cidr` se ignora y no representa el rango overlay. En Native, un CIDR de pods inválido, fuera de VCN o solapado bloquea el despliegue. Al cambiar la VCN, adapta también el CIDR de pods si seleccionaste Native.

El `/19` de pods es un punto de partida de Oracle, no un dimensionamiento de la aplicación. Ajústalo según nodos, pods máximos por nodo, reserva de IP, VNIC del shape y crecimiento. Este stack no recibe ni valida capacidad de nodos/pods.

Revisa solapes con redes externas y con el rango Kubernetes Services. En Flannel también debe evitarse el solape de la VCN con el overlay de pods. Por ejemplo, si usas los rangos overlay de pods `10.244.0.0/16` y Services `10.96.0.0/16`, evita sus solapes con la VCN.

## Outputs, OKE y actualización

`oke_network_inputs` entrega compartment, región, VCN, subred API, workers, LB, Bastion, `is_public_ip_enabled=false`, `cni_type` y `pods_subnet_id`. Este último es `null` en Flannel y el OCID de pods en Native. Los mapas `subnets`, `security_list_ids` y `route_table_ids` agregan la clave `pods` sólo en Native.

Al crear OKE Native selecciona el mismo CNI en el cluster y configura el node pool con la subred de workers para nodos y la subred de pods para IP de pods. Este stack no inspecciona el cluster externo y no puede detectar que hayas elegido otro CNI en la consola.

El valor predeterminado es Flannel. Al actualizar una red existente, revisa Plan antes de Apply.

**Cambiar el selector no migra un cluster existente.** Oracle indica que el CNI no puede cambiarse después de crear el cluster. Prueba el otro modo en una red/cluster independientes o planifica migrar workloads a un cluster nuevo. Cambiar el selector sobre una red en uso altera rutas y permisos; pasar de Native a Flannel propone además eliminar la subred de pods y sus recursos. Revisa las dependencias y el Plan.

Este stack no crea una subred de datos: si tu aplicación requiere bases de datos u otros servicios privados, diseña sus subredes y reglas por separado.

## Adaptaciones explícitas

- API `/28` predeterminada: más espacio que el `/30` Flannel o `/29` Native de las referencias.
- Bastion tiene tabla NAT + OSN explícita porque Oracle no detalla su tabla en estos ejemplos. Su lista limita la salida a API y SSH opcional.
- DHCP usa un recurso dedicado con el resolver indicado por Oracle.
- `ALL/30000–32767` y `ALL/10256` se expresan con reglas TCP y UDP separadas; OCI no permite filtrar puertos con `protocol="all"`.

## Pruebas

Para CLI, configura autenticación habitual del provider y adapta `terraform.tfvars.example`; no subas claves ni estado al ZIP.

```powershell
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=terraform.tfvars
```

`terraform test` requiere Terraform **1.7 o superior** y ejecuta **16 pruebas con mock_provider** para ambos CNI, parámetros propios, opciones y rechazos de datos inválidos. Los apply positivos son simulados, con limpieza automática; no contactan un tenancy.

Comprobado con Terraform **1.9.8**, provider OCI **9.13.0**, formato, `validate`, 16 pruebas y meta schema oficial de Resource Manager. La validación automatizada usa un proveedor simulado. Verifica permisos, límites y conectividad efectiva con Plan/Apply en tu tenancy.

## Referencias

- [Oracle: Example 2, Flannel privado](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengnetworkconfigexample.htm#example-flannel-cni-privatek8sapi_privateworkers_publiclb)
- [Oracle: Example 4, OCI VCN-Native privado](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengnetworkconfigexample.htm#example-oci-cni-privatek8sapi_privateworkers_publiclb)
- [Oracle: Pod Networking y restricción de cambio de CNI](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengpodnetworking.htm)
- [Resource Manager: schema.yaml y meta schema](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/terraformconfigresourcemanager_topic-schema.htm)

## Generar el ZIP de Resource Manager

Con Python 3, sin dependencias adicionales:

```powershell
python scripts/package_stack.py
```

Se generan el ZIP y su SHA-256 en `dist/`. Sólo se incluyen archivos Terraform, el lock file del provider, formulario, documentación, ejemplo de variables y pruebas. Se excluyen credenciales, estado, variables locales, directorio `.terraform` e historial Git.

## Licencia

Este repositorio se publica sin una licencia de reutilización por el momento.
