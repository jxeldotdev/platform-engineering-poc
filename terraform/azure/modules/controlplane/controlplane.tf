locals {
  scaleset_worker_name       = "k8s-workers"
  scaleset_controlplane_name = "k8s-controlplane"
  token_id                   = format("%s.%s", random_string.token_id.result, random_string.token_secret.result)
  cluster_name = "freeman-kubeadm-test"
  lb_dns_prefix = "${local.cluster_name}-${random_string.lb_suffix.result}"
  # lb_dns_name = "${local.lb_dns_prefix}.${var.rg.location}.cloudapp.azure.com:6443"
  lb_dns_name = "10.0.201.4:6443"
}

resource "random_string" "lb_suffix" {
  length  = 6
  numeric = true
  special = false
  lower   = true
  upper   = false
}

# Token for kubeadm
resource "random_string" "token_id" {
  length  = 6
  numeric = true
  lower   = true
  special = false
  upper   = false
}

resource "random_string" "token_secret" {
  length  = 16
  numeric = true
  lower   = true
  special = false
  upper   = false
}

data "azurerm_subscription" "current" {
}

data "azurerm_image" "default" {
  name = "base-almalinux9-1680572926"
  resource_group_name = "golden-image-build"
}


resource "azurerm_linux_virtual_machine_scale_set" "controlplane" {
  name                = local.scaleset_controlplane_name
  location            = var.rg.location
  resource_group_name = var.rg.name
  upgrade_mode        = "Manual"
  sku            = "Standard_F2s_v2"
  instances      = 3
  admin_username = "jfreeman"
  zone_balance = true
  zones = ["1","2","3"]

  user_data = base64encode(templatefile(
    "${path.module}/bin/init-controlplane.sh",
    {
      kubeadm_token = local.token_id,
      cluster_name = local.cluster_name,
      subscription_id = data.azurerm_subscription.current.id
      rg_name = var.rg.name,
      apiserver_nlb = local.lb_dns_name
      addons = "",
      storage_account_name = azurerm_storage_account.scripts.name,
      container_name = azurerm_storage_container.master.name,
      az_storage_key = azurerm_storage_account.scripts.primary_access_key,
      vault_name = azurerm_key_vault.certs.name
    }
  ))

  admin_ssh_key {
    username   = "jfreeman"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDV9I1sJJY76gjwC4dYxaQgxKCzL6sT9mG0tTge3oFzp2A0kuyIOV2HJs3XM0RF0qlZkzDeR9ZDLgJMnZ4h5IqKch0Sk0sGN5k+gsuD9QiEY4PlWYIxk12fXGo5OlilZ+2HzPO6r5FCgGX40ct8BDWRxHthjADH9w2UCzlblyKqNnJnpIesyd1+Pul/G/9ALfjCrRQuCoFoTbKN6aGzemYQ07YJsudA4Tnc7ogAygnl2x8D3ROEpbqhv1hZYGnhAvEjkxVGTFri6GnGA4M42Fn7tSbOjqShRJa3ejVEXKqFANptbPo5z1m3BdfHNh3z0iYvOSWSWTYjbPXx76MbBZEH1hc9ismR0OZ2k4XrTtOMXE2MerETKfLf4BgmuCSJ7QOPgIh0Rfu6T5UXnIeMuDvsPuVK5CsoPaobU6kxi6UIjswOGL2uYuiSfYT+y8/O59hMQANOdqtXJ/5IiurCu+YRt+wvzl2F0g8kXa7pFCGlK8l7yzkv20gFZ6UpqdwOJEc= joelfreeman@joels-air.lan"
  }

  source_image_id = data.azurerm_image.default.id
  
  plan {
    name = "9-gen2"
    publisher = "almalinux"
    product = "almalinux"
  }

  network_interface {
    name    = "NetworkProfile"
    primary = true
    network_security_group_id = var.controlplane.nsg_id

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = var.controlplane.subnet_id
      application_security_group_ids = [var.controlplane.asg_id]
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb = 100
  }

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.controlplane.id]
  }

}
