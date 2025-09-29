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

## 2025-09-28 Deployment Handover
- State: bootstrap, masters, and service VMs are running; `bootkube.service` on the bootstrap host loops and the Kubernetes API never comes up.
- Root cause: the placeholder pull secret in `files/pull_secret.txt` (`{"auths":{"fake":{"auth": "bar"}}}`) is not valid base64, so `oc adm release info` fails during manifest rendering with `illegal base64 data at input byte 0`.
- Immediate fix: replace the file content with a valid JSON pull secret (example lab stub: `{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}`), rerun `ansible-playbook setup-okd.yaml --tags pull-secret,manifests,web,bootstrap`, and restart the bootstrap VM (`qm start dev-okd-bootstrap`).
- Cleanup before rerun: stop bootstrap, remove `/home/ansible/install_dir` on the service node and `/var/opt/openshift/*` on the bootstrap host to clear stale manifests.
- Monitoring: tail `journalctl -u release-image.service -u bootkube.service -f` on the bootstrap node; wait for `safe to remove the bootstrap` before starting workers.
- Next steps: once bootstrap completes, continue with the existing playbook flow to start control plane/worker VMs and verify CSR auto-approval script progress (`oc get csr`).
- New timeouts: bootstrap wait uses `bootstrap_timeout_seconds` (default 3600) and workers use `install_timeout_seconds` (default 7200); adjust in `vars/main.yaml` if longer windows are needed.

## Quick Takeover Checklist
- Verify access to the service node:
    ```bash
    ssh -i files/id_rsa ansible@192.168.1.116
    ```
- Check VM state from the Proxmox host:
    ```bash
    ssh -i ~/.ssh/keys/proxmox-ansible ansible@proxmox.liofal.net 'sudo -n qm list'
    ```
- Inspect bootstrap health and logs:
    ```bash
    ssh -i files/id_rsa ansible@192.168.1.116 \
      'ssh -i ~/.ssh/ssh_openshift core@192.168.2.189 \
        sudo journalctl -u release-image.service -u bootkube.service -f'
    ```
- Reset state before rerun (stop bootstrap first):
    ```bash
    ssh -i files/id_rsa ansible@192.168.1.116 'sudo qm stop 407'
    ssh -i files/id_rsa ansible@192.168.1.116 'rm -rf install_dir tmp'
    ssh -i files/id_rsa ansible@192.168.1.116 \
      'ssh -i ~/.ssh/ssh_openshift core@192.168.2.189 sudo rm -rf /var/opt/openshift/*'
    ```
- Regenerate assets once the pull secret is fixed:
    ```bash
    ansible-playbook setup-okd.yaml --tags pull-secret,manifests,web,bootstrap
    ```
- Restart bootstrap and monitor progress:
    ```bash
    ssh -i ~/.ssh/keys/proxmox-ansible ansible@proxmox.liofal.net 'sudo -n qm start 407'
    ssh -i files/id_rsa ansible@192.168.1.116 \
      'ssh -i ~/.ssh/ssh_openshift core@192.168.2.189 \
        sudo journalctl -u bootkube.service -f'
    ```
- After API becomes available, confirm cluster status:
    ```bash
    ssh -i files/id_rsa ansible@192.168.1.116 \
      'export KUBECONFIG=install_dir/auth/kubeconfig && oc get nodes'
    ```

## 2025-09-28 Evening Status (Codex)
- Infra destroyed and reprovisioned with OpenTofu; Ansible rerun to regenerate install assets with base64-safe pull secret.
- Bootstrap VM restarted while masters were originally powered off, so `openshift-install wait-for bootstrap-complete` timed out. After bringing masters back up they converged (`oc get nodes` shows all three masters Ready) but static pod rollout is still incomplete.
- Current blockers: control plane operators (etcd/kube-apiserver/kube-controller-manager/kube-scheduler) remain in `DoesNotExist` state and ignition fetch on worker0 keeps retrying (`https://api-int.okd.liofal.net:22623/config/worker`). Routing inconsistency (bootstrap timed out while masters were offline) plus gateway misconfiguration kept the static pods from ever rolling to revision 1.
- Bootstrap node still running; leave it up until etcd/kube-apiserver pods settle or we confirm HAProxy no longer references bootstrap backends in `okd4_*` pools (`/etc/haproxy/haproxy.cfg` still lists bootstrap). Once the rerun hits “safe to remove the bootstrap”, comment out the bootstrap entries and shut down VM 407.
- No pending CSRs; auto-approver is working. Focus on re-running the full bootstrap sequence with correct timing.
- Gateway fix: restored cloud-init so the service node uses `mgmt_gateway` on the management NIC and no gateway on the lab NIC; PXE nodes now default to `lab_gw` (service host). This puts NAT/DNS back on the service node as README expects.
- Plan: destroy + reprovision (`tofu destroy/apply`), rerun `ansible-playbook setup-okd.yaml`, then follow README timing precisely—start bootstrap, immediately launch `openshift-install wait-for bootstrap-complete`, start masters when prompted, wait for “safe to remove the bootstrap”, then proceed with workers.

## 2025-09-28 Late Update
- Reprovisioned with the gateway fix; full playbook run (no tag filter) is required on fresh installs so the untagged httpd/haproxy tasks flip Apache to port 8080 and enable the load-balancer. A tag-limited run left httpd stopped on port 80, so PXE nodes initially failed to fetch `rootfs.img`—manual restart confirmed the root cause.
- After starting `httpd` (Listen 8080) and `haproxy`, PXE downloads succeeded; bootstrap reached `Waiting up to 45m0s for bootstrapping to complete…`, and all three masters are cycling through the expected FCOS rpm-ostree reboot before CNI comes up.
- Current view: `oc get nodes` shows all masters `NotReady` while OVN/Multus pods pull; `oc get csr` confirms certificates are auto-approved; etcd operator pod is running and image pulls from quay succeed from the masters.
- Next actions: let bootstrapping finish, watch `tmp/bootstrap.log` for “safe to remove the bootstrap”, then remove bootstrap backends from `/etc/haproxy/haproxy.cfg`, stop VM 407, and proceed with the worker/installer wait-for steps per README timing.

## 2025-09-29 etcd Backup
- Snapshot taken from `master0.okd.liofal.net` using the builtin script:
  ```bash
  export KUBECONFIG=~/install_dir/auth/kubeconfig
  oc debug node/master0.okd.liofal.net -- chroot /host \
    sudo /usr/local/bin/cluster-backup.sh /var/home/core/etcd-backup
  ```
- Artifacts copied to the service host under `~/backups/etcd-2025-09-29/` and synced locally to `backups/` in this repo:
  - `snapshot_2025-09-29_065350.db`
  - `static_kuberesources_2025-09-29_065350.tar.gz`
- Restore run-book (per OKD docs):
  1. Copy the snapshot directory back to a master (e.g. `/home/core/etcd-backup`).
  2. Stop static pods by moving manifests out of `/etc/kubernetes/manifests` on all masters.
  3. On one master, run `sudo -i /usr/local/bin/cluster-restore.sh <snapshot-dir>`; answer prompts to clean out `/var/lib/etcd` and apply the snapshot.
  4. Copy the refreshed `static-pod-resources` bundle to the remaining masters.
  5. Return manifests, reboot masters, and verify etcd members come up (`oc get nodes`, `oc get co`).
- After restore, re-run `ansible-playbook setup-okd.yaml --tags hosts` if IPs/NAT changed before bringing workers back online.
