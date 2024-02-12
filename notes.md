# Proxmox OpenShift Setup Notes

## Initial Setup and SSH Configuration
- Connect to the Proxmox server using SSH to verify connectivity:
    ```bash
    ssh -v 192.168.1.116
    ```

- Generate an SSH key and copy it to the Proxmox server for passwordless login:
    ```bash
    ssh-keygen
    ssh-copy-id root@192.168.1.116
    ssh -v root@192.168.1.116
    ```

- Verify the current user and clean the known hosts file if necessary:
    ```bash
    whoami
    rm .ssh/known_hosts*
    ssh -v root@192.168.1.116
    ```

- Copy the SSH key for the `ansiblebot` user and verify connection:
    ```bash
    ssh-copy-id root@192.168.1.116
    ssh -v ansiblebot@192.168.1.116
    ssh -v root@192.168.1.116
    ```

## SSH Configuration for ansiblebot
- Configuration snippet for SSH:
    ```
    ; Host 192.168.1.207
    ;   HostName  192.168.1.207
    ;   User ansiblebot
    ;   IdentityFile ~/.ssh/id_rsa
    ```

## Proxmox and OpenShift Configuration
- Initialize environment variables and apply configuration:
    ```bash
    vscode ➜ /workspaces/proxmox-openshift-setup (main) $ source .env
    vscode ➜ /workspaces/proxmox-openshift-setup (main) $ tofu apply
    ```

- Disable `firewalld` and inspect NAT tables:
    ```bash
    sudo iptables -t nat -L
    sudo systemctl disable firewalld
    ```

## Troubleshooting CSR Approval
- Commands to approve CSR after a long idling period:
    ```bash
    export KUBECONFIG=~/install_dir/auth/kubeconfig
    oc get csr | grep Pending
    oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
    ```

oc -n openshift-config patch cm admin-acks --patch '{"data":{"ack-4.13-kube-1.27-api-removals-in-4.14":"true"}}' --type=merge
configmap/admin-acks patched