# SMB Importer

Installation info:
The operator used requires some containers running as root. Some setups dont allow this.
For talos ensure the namespace is created with the following labels:
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/enforce-version=latest