resource "azurerm_public_ip" "lb" {
  name                = "lb"
  location            = var.rg.location
  resource_group_name = var.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones                   = [1]

  domain_name_label = local.lb_dns_prefix
}


resource "azurerm_lb" "apiserver" {
  name                = "k8s-apiserver"
  resource_group_name = var.rg.name
  location            = var.rg.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "ControlPlaneIp"
    subnet_id = var.lb_subnet
    zones = ["1","2","3"]
    private_ip_address_allocation = "Static"
    private_ip_address = "10.0.201.4"
  }
}

resource "azurerm_lb_probe" "apiserver" {
  loadbalancer_id = azurerm_lb.apiserver.id
  name            = "apiserver"
  port            = 6443
}

resource "azurerm_lb_backend_address_pool" "haproxy" {
  loadbalancer_id = azurerm_lb.apiserver.id
  name            = "apiserver"
}

resource "azurerm_lb_rule" "apiserver" {
  loadbalancer_id                = azurerm_lb.apiserver.id
  name                           = "apiserver"
  protocol                       = "Tcp"
  frontend_port                  = 6443
  backend_port                   = 6443
  frontend_ip_configuration_name = "ControlPlaneIp"
  backend_address_pool_ids = [azurerm_lb_backend_address_pool.haproxy.id]
  probe_id = azurerm_lb_probe.apiserver.id
  disable_outbound_snat = true
  enable_tcp_reset = true
}

data "azurerm_virtual_machine_scale_set" "controlplane" {
  name                = azurerm_linux_virtual_machine_scale_set.controlplane.name
  resource_group_name = var.rg.name
}
// https://github.com/Azure/azure-quickstart-templates/tree/master/demos/haproxy-redundant-floatingip-ubuntu

resource "azurerm_public_ip" "haproxy" {
  count = 2
  name                = "haproxy-${count.index}"
  resource_group_name = var.rg.name
  location            = var.rg.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
    application = "HAProxy"
  }
}

resource "azurerm_network_interface" "haproxy" {
  count = 2
  name                = "haproxy-${count.index}"
  location            = var.rg.location
  resource_group_name = var.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.haproxy.subnet_id
    private_ip_address_allocation = "Dynamic"
    # public_ip_address_id = azurerm_public_ip.haproxy[count.index].id
  }
}

resource "azurerm_network_interface_application_security_group_association" "haproxy" {
  count = 2
  network_interface_id          = azurerm_network_interface.haproxy[count.index].id
  application_security_group_id = var.haproxy.asg_id
}

resource "azurerm_network_interface_backend_address_pool_association" "haproxy" {
  count = 2
  network_interface_id    = azurerm_network_interface.haproxy[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.haproxy.id
}

locals {
  controlplane_instance_list = [
    for n in data.azurerm_virtual_machine_scale_set.controlplane.instances[*] : n.computer_name
  ]
  controlplane_vm_names = join(" ", local.controlplane_instance_list)
}

resource "azurerm_availability_set" "haproxy" {
  name                = "haproxy"
  location            = var.rg.location
  resource_group_name = var.rg.name
  platform_fault_domain_count = 2

  tags = {
    environment = "Production"
    application = "HAProxy"
  }
}

resource "null_resource" "haproxy_trigger" {
  triggers = {
    user_data = base64encode(templatefile(
    "${path.module}/bin/init-haproxy.sh",
    {
      app_vms = local.controlplane_vm_names,
      master_vm = "haproxy-0",
      backup_vm = "haproxy-1",
      lb_dns_name = local.lb_dns_name
    }
  ))
  }
}

resource "azurerm_linux_virtual_machine" "haproxy" {

  lifecycle {
    replace_triggered_by = [
      null_resource.haproxy_trigger
    ]
  }
  count = 2
  name                = "haproxy-${count.index}"
  location            = var.rg.location
  resource_group_name = var.rg.name
  size            = "Standard_B1s"
  admin_username = var.admin_user.name

  availability_set_id = azurerm_availability_set.haproxy.id

  network_interface_ids = [
    azurerm_network_interface.haproxy[count.index].id
  ]

  admin_ssh_key {
    username   = var.admin_user.name
    public_key = var.admin_user.key
  }

  user_data = base64encode(templatefile(
    "${path.module}/bin/init-haproxy.sh",
    {
      app_vms = local.controlplane_vm_names,
      master_vm = "haproxy-0",
      backup_vm = "haproxy-1",
      lb_dns_name = local.lb_dns_name
    }
  ))

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb = 30
  }

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.haproxy.id]
  }
}
