locals {
  subnet_names = ["control-plane", "workers", "lb","haproxy"]
}

variable "rg" {
  type = object({
    name = string
    location = string
  })
}

# Create a virtual network within the resource group
// only need to allow incomming traffic from NLB
resource "azurerm_network_security_group" "sgs" {
  for_each = {
    controlplane = ""
    workers      = ""
    lb           = ""
    haproxy      = ""
    bastion      = ""
  }
  name                = each.key
  location            = var.rg.location
  resource_group_name = var.rg.name
}


resource "azurerm_application_security_group" "haproxy" {
  name                = "haproxy"
  location            = var.rg.location
  resource_group_name = var.rg.name
}

resource "azurerm_application_security_group" "controlplane" {
  name                = "controlplane"
  location            = var.rg.location
  resource_group_name = var.rg.name
}

resource "azurerm_application_security_group" "workers" {
  name                = "workers"
  location            = var.rg.location
  resource_group_name = var.rg.name
}


resource "azurerm_virtual_network" "main" {
  name                = "k8s-network"
  resource_group_name = var.rg.name
  location            = var.rg.location
  address_space       = ["10.0.0.0/16"]

  subnet {
    name           = local.subnet_names[0]
    address_prefix = "10.0.1.0/24"
    security_group = azurerm_network_security_group.sgs["controlplane"].id
  }

  subnet {
    name           = local.subnet_names[1]
    address_prefix = "10.0.101.0/24"
    security_group = azurerm_network_security_group.sgs["workers"].id
  }

    subnet {
        name           = local.subnet_names[2]
        address_prefix = "10.0.201.0/24"
        security_group = azurerm_network_security_group.sgs["lb"].id
    }

    subnet {
        name           = local.subnet_names[3]
        address_prefix = "10.0.220.0/24"
        security_group = azurerm_network_security_group.sgs["haproxy"].id
    }

  subnet {
    name = "AzureBastionSubnet"
    address_prefix = "10.0.202.0/24"
    security_group = azurerm_network_security_group.bastion.id
  }
}

resource "azurerm_subnet_nat_gateway_association" "subnets" {
    depends_on = [
      azurerm_virtual_network.main
    ]
  for_each = toset(
    [data.azurerm_subnet.workers.id,
    data.azurerm_subnet.controlplane.id,
    data.azurerm_subnet.lb.id,
    data.azurerm_subnet.haproxy.id]
  )

  subnet_id = each.key
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_nat_gateway" "main" {
  name                    = "main"
  location                = var.rg.location
  resource_group_name     = var.rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = [1]
}

resource "azurerm_public_ip" "natgw" {
  name                = "nat-gateway"
  location            = var.rg.location
  resource_group_name = var.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones                   = [1]
}

resource "azurerm_nat_gateway_public_ip_association" "example" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.natgw.id
}

data "azurerm_subnet" "workers" {
  name                 = local.subnet_names[1]
  resource_group_name  = var.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
}

data "azurerm_subnet" "controlplane" {
  name                 = local.subnet_names[0]
  resource_group_name  = var.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
}

data "azurerm_subnet" "lb" {
  name                 = local.subnet_names[2]
  resource_group_name  = var.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
}

data "azurerm_subnet" "haproxy" {
  name                 = local.subnet_names[3]
  resource_group_name  = var.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
}

data "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
}


// LB -> HAProxy
resource "azurerm_network_security_rule" "controlplane-nlb-to-lb" {
  depends_on = [
    azurerm_virtual_network.main
  ]
  name                        = "lb-from-controlplane"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6443"
  source_address_prefix       = "10.0.201.4"
  destination_application_security_group_ids = [azurerm_application_security_group.haproxy.id]
  resource_group_name         = var.rg.name
  network_security_group_name = azurerm_network_security_group.sgs["lb"].name
}

// LB -> Control Plane

// Worker -> LB
resource "azurerm_network_security_rule" "controlplane-nlb-ing-proxy" {
  depends_on = [
    azurerm_virtual_network.main
  ]
  name                        = "worker-to-lb"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6443"
  # USE IP TAGS
  source_application_security_group_ids = [azurerm_application_security_group.workers.id]
  destination_address_prefix = "0.0.0.0/0"
  resource_group_name         = var.rg.name
  network_security_group_name = azurerm_network_security_group.sgs["lb"].name
}


// let bastion access all
resource "azurerm_network_security_rule" "worker-bastion" {
  depends_on = [
    azurerm_virtual_network.main
  ]
  name                        = "allow-all-from-bastion"
  priority                    = 250
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = 0
  destination_port_range      = 65535
  source_address_prefix       = data.azurerm_subnet.bastion.address_prefix
  destination_address_prefix  = data.azurerm_subnet.workers.address_prefix
  resource_group_name         = var.rg.name
  network_security_group_name = azurerm_network_security_group.sgs["workers"].name
}

resource "azurerm_network_security_rule" "controlplane-bastion" {
  depends_on = [
    azurerm_virtual_network.main
  ]
  name                        = "allow-all-from-bastion"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = 0
  destination_port_range      = 65535
  source_address_prefix       = data.azurerm_subnet.bastion.address_prefix
  destination_address_prefix  = data.azurerm_subnet.controlplane.address_prefix
  resource_group_name         = var.rg.name
  network_security_group_name = azurerm_network_security_group.sgs["controlplane"].name
}

resource "azurerm_network_security_rule" "lb-bastion" {
  depends_on = [
    azurerm_virtual_network.main
  ]
  name                        = "allow-all-from-bastion"
  priority                    = 250
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = 6443
  destination_port_range      = 6443
  source_address_prefix       = data.azurerm_subnet.bastion.address_prefix
  destination_address_prefix  = data.azurerm_subnet.lb.address_prefix
  resource_group_name         = var.rg.name
  network_security_group_name = azurerm_network_security_group.sgs["lb"].name
}

// let me access Inbound!
resource "azurerm_network_security_rule" "lb-me" {
  depends_on = [
    azurerm_virtual_network.main
  ]
  name                        = "allow-all-me"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = 0
  destination_port_range      = 65535
  source_address_prefix       = "121.99.199.225/32"
  destination_address_prefix  = "0.0.0.0/0"
  resource_group_name         = var.rg.name
  network_security_group_name = azurerm_network_security_group.sgs["lb"].name
}

resource "azurerm_network_security_rule" "controlplane-to-lb" {
  depends_on = [
    azurerm_virtual_network.main
  ]
  name                        = "allow-from-controlplane"
  priority                    = 150
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = 6443
  source_application_security_group_ids = [azurerm_application_security_group.controlplane.id]
  destination_application_security_group_ids = [azurerm_application_security_group.haproxy.id]
  resource_group_name         = var.rg.name
  network_security_group_name = azurerm_network_security_group.sgs["lb"].name
}

// Control Plane -> Kubelet API
resource "azurerm_network_security_rule" "workers-kubelet-ing" {
  depends_on = [
    azurerm_virtual_network.main
  ]
  name                        = "kubelet-from-controlplane"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "10250"
  source_application_security_group_ids = [azurerm_application_security_group.controlplane.id]
  destination_application_security_group_ids = [azurerm_application_security_group.workers.id]
  resource_group_name         = var.rg.name
  network_security_group_name = azurerm_network_security_group.sgs["workers"].name
}

// Allow all ing nodeport traffic from VNET (We'll fix this later when we create ingress)
resource "azurerm_network_security_rule" "workers-nodeport-ing" {
  depends_on = [
    azurerm_virtual_network.main
  ]
  name                        = "allow-nodeport-from-worker-and-controlplane"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "30000-32767"
  source_application_security_group_ids = [azurerm_application_security_group.controlplane.id,azurerm_application_security_group.workers.id]
  destination_application_security_group_ids  = [azurerm_application_security_group.workers.id]
  resource_group_name         = var.rg.name
  network_security_group_name = azurerm_network_security_group.sgs["workers"].name
}