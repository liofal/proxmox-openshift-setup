ssh -v 192.168.1.116
ssh-keygen
ssh-copy-id root@192.168.1.116
ssh -v root@192.168.1.116
whoami
rm .ssh/known_hosts*
ssh -v root@192.168.1.116
ssh-copy-id root@192.168.1.116
ssh -v ansiblebot@192.168.1.116
ssh -v root@192.168.1.116


; Host 192.168.1.207
;   HostName  192.168.1.207
;   User ansiblebot
;   IdentityFile ~/.ssh/id_rsa

vscode ➜ /workspaces/proxmox-openshift-setup (main) $ source .env                      
vscode ➜ /workspaces/proxmox-openshift-setup (main) $ tofu apply 