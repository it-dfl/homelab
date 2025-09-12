# Homelab Talos Kubernetes Setup

This project automates a homelab server with a talox kubernetes cluster running on proxmox.
It integrates the talos_proxmox ansible role, provided the project structure, variables and the git configuration for argocd.

## Requirements

- See the requirements for the talos_proxmox role
- additionally if you want to use the setup_environment.sh the system needs to use apt as a package manager. It was tested on Debian Bookworm.

## Structure

- ansible
  - inventory
    - example/group_vars # Example environment to adjust for your own need
      - all
        - vars.yml  # Put variables in here
        - vault.yml # Put secrets in here
      - hosts
    - ... # Other environments
  - cluster.yml # Playbook to call talos_proxmox role
- argocd
  - prod # Directory contianing argocd config and charts for the production environment
    - app-of-apps # Argocd Applications in the app-of-apps pattern
    - ... additional applications / config / charts called by the app-of-apps
- .gitignore
- ansible-requirements.yml # Ansible roles and collections required for this project
- python-requirements.txt  # Python packages required for this project
- README.md
- setup_environment.sh # Bash script for apt based os to setup the environment

## Usage

This assumes you have access to a proxmox server with internet connection.

1. Adjust the values of your environment in ansible/inventory/<env>/ and encrypt the vault.yml with a secure password.
   Also (optional) add your environment to the .gitignore before publishing your repository.
2. If you want to use argocd to manage your applications simply set up your applications in argocd/<env>/ 
   and reference your starting application (app-of-apps) in the variables.
3. Setup your local machine to fullfill all the requirements. If it works on your system you can simply execute the setup_environment.sh:
   ```bash
   sudo setup_environment.sh
   ```
4. Now execute the playbook to install the cluster on the proxmox server:
   ```bash
   cd ansible
   ansible-playbook -i inventory/<env>/ cluster.yml
   ```

## License
MIT


