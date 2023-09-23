"""

Copy files in /etc/kubernetes/pki to Azure Key vault.

Environment vars used:
CLUSTER_NAME
KEY_VAULT_NAME


"""
from os import as getenv, listdir, path
from azure.core.exceptions import ResourceNotFoundError
from azure.identity import DefaultAzureCredential
from azure.keyvault.certificates import (CertificateContentType,
                                         CertificatePolicy,
                                         WellKnownIssuerNames, CertificateClient)
from azure.keyvault.secrets import SecretClient
import OpenSSL.crypto as crypto                   
import logging

logger = logging.getLogger(__name__)

class Certificate:
    def __init__(self, name: str, files: list[str], type: str):
        self.name = name
        self.files = files
        self.type = type

    def import_to_keyvault(self, keyvault_url: str):
        # Authenticate to Azure
        credential = DefaultAzureCredential()
        
        # Create a certificate client
        certificate_client = CertificateClient(vault_url=keyvault_url, credential=credential)

        # Read the certificate and private key files
        certificate_file_path = self.files[0]
        private_key_file_path = self.files[1]
        with open(certificate_file_path, "rb") as f:
            certificate_data = f.read()
        with open(private_key_file_path, "rb") as f:
            private_key_data = f.read()

        cluster_name = getenv("CLUSTER_NAME")
        cert_name = f"{cluster_name}-{self.name}"
        if self.type == "x509":
            certificate = crypto.load_certificate(crypto.FILETYPE_PEM, certificate_data)    
            private_key = crypto.load_privatekey(crypto.FILETYPE_PEM, private_key_data)

            # Create a PKCS12 certificate
            pkcs12 = crypto.PKCS12()
            pkcs12.set_certificate(certificate)
            pkcs12.set_privatekey(private_key)
        # Import the certificate into Azure Key Vault
            try:
                certificate_client.get_certificate(self.name)
                print(f"Certificate {self.name} already exists in Key Vault, skipping import.")
            except ResourceNotFoundError:
                print(f"Importing certificate {self.name} to Key Vault...")
                certificate_client.import_certificate(
                    certificate_name=cert_name,
                    certificate_bytes=pkcs12.export(),
                    policy=CertificatePolicy(issuer_name=WellKnownIssuerNames.self, 
                    content_type=CertificateContentType.pkcs12,
                    key_type="rsa"
                    )
                )
                logger.info(f"Certificate {self.name} imported successfully.")
        else:
            # Store private key as a secret, importing RSA key is fucking hard
            secret_client = SecretClient(vault_url=keyvault_url, credential=credential)
            secret_client.set_secret(cert_name, private_key_data.decode("utf-8"))

class CertificateList:
    def __init__(self, certificates: list[Certificate]):
        self.certificates = certificates

def get_certs_to_import():
    # Get a list of files in the /etc/kubernetes/pki directoryc
    
    certs_to_import = CertificateList(
        certificates=[
            Certificate(
                name="ca",
                files=[
                    "/etc/kubernetes/pki/ca.crt",
                    "/etc/kubernetes/pki/ca.key"
                ],
                type="x509"
            ),
            Certificate(
                name="sa",
                files=[
                    "/etc/kubernetes/pki/sa.pub",
                    "/etc/kubernetes/pki/sa.key",
                ],
                type="rsa"
            ),
            Certificate(
                name="front-proxy-ca",
                files=[
                    "/etc/kubernetes/pki/front-proxy-ca.crt",
                    "/etc/kubernetes/pki/front-proxy-ca.key"
                ],
                type="x509"
            ),
            Certificate(
                name="etcd",
                files=[
                    "/etc/kubernetes/pki/etcd/ca.crt",
                    "/etc/kubernetes/pki/etcd/ca.key"
                ],
                type="x509"
            )
        ]
    )

    # Check if each file in each certificate object exists on the filesystem,
    # and remove the certificate object from the list if any of the files do not exist
    for certificate in certs_to_import.certificates:
        missing_files = []
        for file in certificate.files:
            if not path.exists(file):
                missing_files.append(file)
                continue
            logger.info(f"Certificate file {file} exists")
        if missing_files:
            logger.error(f"Certificate {certificate.name} cannot be imported because the following files are missing: {missing_files}")
            certs_to_import.certificates.remove(certificate)
    return certs_to_import

def import_certs(cert_list: CertificateList, keyvault_url: str):
    for cert in cert_list.certificates:
        cert.import_to_keyvault(keyvault_url)

if __name__ == '__main__':
    try:
        kv_name = getenv("KEY_VAULT_NAME ", "cluster-certs")
    except EnvironmentError:
        logger.critical("Unable to determine key vault name from ENV var KEY_VAULT_NAME, exiting!")
    
    kv_url = f"https://{kv_name}.vault.azure.net/"

    cert_list = get_certs_to_import()


    import_certs(cert_list, keyvault_url=kv_url)     