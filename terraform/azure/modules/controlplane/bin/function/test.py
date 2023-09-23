import re

regex = r'kubeadm join .*?--token [a-z0-9]{6}\.[a-z0-9]{16} .*'

output = """
W1022 19:51:03.885049   26680 configset.go:202] WARNING: kubeadm cannot validate component configs for API groups [kubelet.config.k8s.io kubeproxy.config.k8s.io]
kubeadm join 192.168.56.110:6443 --token hp9b0k.1g9tqz8vkf78ucwf --discovery-token-ca-cert-hash sha256:32eb67948d72ba99aac9b5bb0305d66a48f43b0798cb2df99c8b1c30708bdc2c
"""

match = re.search(regex, output)
print(output)
print(match.group())