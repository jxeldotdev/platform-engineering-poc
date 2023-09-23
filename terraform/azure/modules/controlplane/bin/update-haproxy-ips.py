import os
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient

# set up Azure credentials
credential = DefaultAzureCredential()


subscription_id = os.environ["AZURE_SUBSCRIPTION_ID"]
resource_group = os.getenv("RG_NAME", "kubernetes")
scale_set_name = os.getenv("SCALE_SET_NAME", "k8s-controlplane")
compute_client = ComputeManagementClient(credential, subscription_id)

def get_current_ips(config_file: str = "/etc/haproxy/haproxy.cfg"):
    """
    Parses IP addresses from a haproxy config file and returns a list of IPs.
    """
    ips = []
    with open(config_file, "r") as f:
        config = f.read()
    
    pattern = r"k8s-controlplane\d{6}\s+\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+"

    # find all matches in the string
    matches = re.findall(pattern, config, re.DOTALL)
    hosts = {}
    for match in matches:
        split_match = match.split(" ")
        hosts.update({
            split_match[0]: split_match[1]
        })
        print(f"Hostname: {split_match[0]}, IP: {split_match[1]}")
    return ips

def get_scale_set_ips(scale_set_name: str):
    """
    Get a list of instances and their ips from azure api

    """
    compute_client = ComputeManagementClient(credential, subscription_id)
    vms = compute_client.virtual_machine_scale_set_vms.list(resource_group, scale_set_name)
    instances = {}
    for vm in vms:
        vm_id = vm.os_profile.computer_name
        for nic in vm.network_profile.network_interfaces:
            nic_name = os.path.basename(nic.id)
            nic_info = compute_client.network_interfaces.get(resource_group, nic_name)
            ip_configs = nic_info.ip_configurations
            for config in ip_configs:
                instances.update({
                    vm_id: config.private_ip_address
                })
    return instances

def compare(cur_instances: dict, api_instances: dict):
    # get length of both dicts
    sorted_cur = sorted(cur_instances.items())
    sorted_api = sorted(api_instances.items())

    # compare dictionaries
    if sorted_cur == sorted_api:
        return False
    else:
        return True

def main():
    cur_ips = get_current_ips()
    api_ips = get_scale_set_ips(scale_set_name)
    # api_ips = {}
    
    if compare(cur_ips, api_ips):
        # Make the changes to the config file.
        for hostname, ip in new_ips.items():
            if hostname in existing_ips:
                # Replace the existing IP address with the new one.
                pattern = re.escape(hostname) + r"\s+" + re.escape(existing_ips[hostname])
                replacement = hostname + " " + ip
                config = re.sub(pattern, replacement, config, flags=re.DOTALL)