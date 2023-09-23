# resource "azurerm_lb" "apiserver" {
#   name                = "k8s-apiserver"
#   resource_group_name = azurerm_resource_group.k8s.name
#   location            = azurerm_resource_group.k8s.location
#   sku                 = "Standard"

#   frontend_ip_configuration {
#     name                          = "ControlPlaneIp"
#     public_ip_address_id = azurerm_public_ip.lb.id
#   }
# }

# // maybe public IP so we don't have to use VPN for now?
# resource "azurerm_lb_probe" "apiserver" {
#   loadbalancer_id = azurerm_lb.apiserver.id
#   name            = "apiserver"
#   port            = 6443
# }

# resource "azurerm_lb_rule" "apiserver" {
#   loadbalancer_id                = azurerm_lb.apiserver.id
#   name                           = "apiserver"
#   protocol                       = "Tcp"
#   frontend_port                  = 6443
#   backend_port                   = 6443
#   frontend_ip_configuration_name = "ControlPlaneIp"
#   backend_address_pool_ids = [azurerm_lb_backend_address_pool.controlplane.id]
#   probe_id = azurerm_lb_probe.apiserver.id
#   disable_outbound_snat = true
#   enable_tcp_reset = true
# }

# // https://github.com/Azure/azure-quickstart-templates/tree/master/demos/haproxy-redundant-floatingip-ubuntu

# # resource "azurerm_linux_virtual_machine_scale_set" "controlplane-haproxy" {
# #   name                = "${local.scaleset_controlplane_name}-haproxy"
# #   location            = azurerm_resource_group.k8s.location
# #   resource_group_name = azurerm_resource_group.k8s.name
# #   upgrade_mode        = "Automatic"
# #   sku            = "Standard_F2s"
# #   instances      = 2
# #   admin_username = "jfreeman"

# #   admin_ssh_key {
# #     username   = "jfreeman"
# #     public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDV9I1sJJY76gjwC4dYxaQgxKCzL6sT9mG0tTge3oFzp2A0kuyIOV2HJs3XM0RF0qlZkzDeR9ZDLgJMnZ4h5IqKch0Sk0sGN5k+gsuD9QiEY4PlWYIxk12fXGo5OlilZ+2HzPO6r5FCgGX40ct8BDWRxHthjADH9w2UCzlblyKqNnJnpIesyd1+Pul/G/9ALfjCrRQuCoFoTbKN6aGzemYQ07YJsudA4Tnc7ogAygnl2x8D3ROEpbqhv1hZYGnhAvEjkxVGTFri6GnGA4M42Fn7tSbOjqShRJa3ejVEXKqFANptbPo5z1m3BdfHNh3z0iYvOSWSWTYjbPXx76MbBZEH1hc9ismR0OZ2k4XrTtOMXE2MerETKfLf4BgmuCSJ7QOPgIh0Rfu6T5UXnIeMuDvsPuVK5CsoPaobU6kxi6UIjswOGL2uYuiSfYT+y8/O59hMQANOdqtXJ/5IiurCu+YRt+wvzl2F0g8kXa7pFCGlK8l7yzkv20gFZ6UpqdwOJEc= joelfreeman@joels-air.lan"
# #   }

# #   source_image_id = data.azurerm_image.haproxy.id

# #   user_data = base64encode(templatefile(
# #     "${path.module}/bin/init-controlplane.sh",
# #     {
# #       kubeadm_token = local.token_id,
# #       cluster_name = local.cluster_name,
# #       subscription_id = data.azurerm_subscription.current.id
# #       rg_name = azurerm_resource_group.k8s.name,
# #       apiserver_nlb = azurerm_public_ip.lb.ip_address
# #       addons = ""
# #     }
# #   ))

# #   source_image_reference {
# #     publisher = "Canonical"
# #     offer     = "UbuntuServer"
# #     sku       = "22.04-LTS"
# #     version   = "latest"
# #   }

# #   network_interface {
# #     name    = "NetworkProfile"
# #     primary = true
# #     network_security_group_id = azurerm_network_security_group.sgs["lb"].id

# #     ip_configuration {
# #       name      = "internal"
# #       primary   = true
# #       subnet_id = data.azurerm_subnet.lb.id
# #       application_security_group_ids = [azurerm_application_security_group.haproxy.id]
# #       load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.controplane.id]

# #       public_ip_address {
# #         name = "primary"
# #       }
# #     }
# #   }

# #   os_disk {
# #     caching              = "ReadWrite"
# #     storage_account_type = "Premium_LRS"
# #     disk_size_gb = 30
# #   }

# #   identity {
# #     type = "UserAssigned"
# #     identity_ids = [azurerm_user_assigned_identity.haproxy.id]
# #   }
# #   lifecycle {
# #     ignore_changes = ["instances"]
# #   }
# # }
