# Create a resource group
resource "azurerm_resource_group" "k8s" {
  name     = "k8s"
  location = var.location
}

module "network" {
  source = "./modules/network"
  rg = {
    name = azurerm_resource_group.k8s.name
    location = azurerm_resource_group.k8s.location
  }
}

module "controlplane" {
  depends_on = [
    module.network
  ]
  source = "./modules/controlplane"
  rg = {
    name = azurerm_resource_group.k8s.name
    location = azurerm_resource_group.k8s.location
  }
  haproxy = {
    subnet_id = module.network.haproxy_subnet
    nsg_id = module.network.haproxy_nsg
    asg_id = module.network.haproxy_asg
  }
  admin_user = {
    name = "jfreeman"
    key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDV9I1sJJY76gjwC4dYxaQgxKCzL6sT9mG0tTge3oFzp2A0kuyIOV2HJs3XM0RF0qlZkzDeR9ZDLgJMnZ4h5IqKch0Sk0sGN5k+gsuD9QiEY4PlWYIxk12fXGo5OlilZ+2HzPO6r5FCgGX40ct8BDWRxHthjADH9w2UCzlblyKqNnJnpIesyd1+Pul/G/9ALfjCrRQuCoFoTbKN6aGzemYQ07YJsudA4Tnc7ogAygnl2x8D3ROEpbqhv1hZYGnhAvEjkxVGTFri6GnGA4M42Fn7tSbOjqShRJa3ejVEXKqFANptbPo5z1m3BdfHNh3z0iYvOSWSWTYjbPXx76MbBZEH1hc9ismR0OZ2k4XrTtOMXE2MerETKfLf4BgmuCSJ7QOPgIh0Rfu6T5UXnIeMuDvsPuVK5CsoPaobU6kxi6UIjswOGL2uYuiSfYT+y8/O59hMQANOdqtXJ/5IiurCu+YRt+wvzl2F0g8kXa7pFCGlK8l7yzkv20gFZ6UpqdwOJEc= joelfreeman@joels-air.lan"
  }
  controlplane = {
    subnet_id = module.network.controlplane_subnet
    nsg_id = module.network.controlplane_nsg
    asg_id = module.network.controlplane_asg
  }
  lb_subnet = module.network.lb_subnet
}
