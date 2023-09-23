"""
deps:
azure-mgmt-resource azure-mgmt-compute azure-mgmt-network azure-identity

"""
import os
import re
import enum

from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.resource import ResourceManagementClient
from azure.storage.blob import BlobServiceClient
import azure.functions as func



EVENT_TYPES = ["Microsoft.Resources.ResourceWriteSuccess", "Microsoft.Resources.ResourceActionSuccess"]
VM_EVENT_TYPE = ["Microsoft.Compute/virtualMachines/write"]

def main(event: func.Event):

    event_info = json.dumps({
        'id': event.id,
        'data': event.get_json(),
        'topic': event.topic,
        'subject': event.subject,
        'event_type': event.event_type,
    })
    
    cmd = ClusterJoinCommand(
        vmss_id=os.getenv("VMSS_ID"),
        vmss_name=os.getenv("VMSS_NAME"),
        subscription_id=os.getenv("AZ_SUBSCRIPTION_ID"),
        rg_name=os.getenv("RG_NAME"),
        is_master=os.getenv("IS_MASTER"),
        sa_url=os.getenv("STORAGEACCOUNT_URL"),
        container_name=os.getenv("CONTAINER_NAME"),
    )
    cmd.upload_script()


class ClusterJoinCommand:
    """
    Generates a command used for joining a node to a kubernetes cluster.
    """

    def __init__(
        self,
        vmss_name: str,
        subscription_id: str,
        rg_name: str,
        is_master: bool,
        sa_url,
        container_name: str,
    ):
        self.vmss_name: str = vmss_name
        self.vm_id = self.get_vm()
        self.is_master: bool = is_master
        self.rg_name: str = rg_name
        self.storage_account_url: str = sa_url
        self.container_name: str = container_name
        self.compute_client = ComputeManagementClient(
            credential=DefaultAzureCredential(), subscription_id=subscription_id
        )
        self.blob_client = BlobServiceClient(
            account_url=self.storage_account_url, credential=DefaultAzureCredential()
        )
        self.join_cmd: str = self.generate_command()

    def get_vm(self) -> str:
        vms = self.compute_client.virtual_machines.list(
            self.rg_name, filter=f"virtualMachineScaleSet/{self.vmss_name}"
        )
        for vm in vms:
            for status in vm.instance_view.statuses:
                if status.code == "PowerState/running":
                    return vm.id

    def generate_command(self) -> str:
        resp = self.client.virtual_machine_scale_set_vms.begin_run_command(
            resource_group_name=self.rg_name,
            vm_scale_set_name=self.vmss_name,
            instance_id=self.vm_id,
            parameters={
                "command_id": "RunShellScript",
                "script": [
                    "KUBECONFIG=/etc/kubernetes/admin.conf kubeadm token create $(kubeadm token generate) --print-join-command"
                ],
            },
        ).response()
        stdout = resp.value[0].message

        # Get output, parse it
        pattern = r"^kubeadm join.*--token [a-z0-9]{6}\.[a-z0-9]{16}.*$"
        join_cmd = re.search(pattern, stdout).match()

        if is_master:
            join_cmd = join_cmd + " --control-plane"

        return join_cmd.match()

    def upload_script(self) -> None:
        blob_name = "master-join-command.sh"
        if not self.is_master:
            blob_name = "worker-join-command.sh"

        blob_client = self.blob_client.get_blob_client(
            container=self.container_nmae, blob=blob_name
        )
        blob_client.upload_blob(
            self.join_cmd.encode(), blob_type="BlockBlob", overwrite=True
        )
