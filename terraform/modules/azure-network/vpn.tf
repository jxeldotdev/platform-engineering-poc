

resource "azurerm_virtual_wan" "vpn" {
  name                = var.vpn.wan_name
  resource_group_name = var.rg.name
  location            = var.rg.location
}

resource "azurerm_virtual_hub" "hub" {
  name                = var.vpn.hub_name
  resource_group_name = var.rg.name
  location            = var.rg.location
  virtual_wan_id      = azurerm_virtual_wan.example.id
  address_prefix      = var.vpn.hub_prefix
}

resource "azurerm_vpn_server_configuration" "vpn-conf" {
  name                     = var.vpn.config.name
  resource_group_name      = var.rg.name
  location                 = var.rg.location
  vpn_authentication_types = ["Certificate"]

  client_root_certificate {
    name             = var.vpn.config.root_cert_name
    public_cert_data = var.vpn.config.public_cert_data
  }
}

resource "azurerm_point_to_site_vpn_gateway" "gw" {
  name                        = var.vpn.gateway.name
  location                    = var.rg.location
  resource_group_name         = var.rg.name
  virtual_hub_id              = azurerm_virtual_hub.hub.id
  vpn_server_configuration_id = azurerm_vpn_server_configuration.vpn-conf.id
  scale_unit                  = 1
  connection_configuration {
    name = var.vpn.gateway.connection_config_name

    vpn_client_address_pool {
      address_prefixes = var.vpn.gateway.address_prefixes
    }
  }
}

