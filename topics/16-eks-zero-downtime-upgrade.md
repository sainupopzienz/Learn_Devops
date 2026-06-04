# Zero Downtime EKS Cluster Upgrade

### Steps
```
Step 1: Upgrade Control Plane (AWS managed — zero downtime)
        eksctl upgrade cluster --name=mycluster --version=1.29

Step 2: Check deprecated APIs BEFORE nodes
        kubent  ← kube-no-trouble tool
        Fix deprecated manifests (extensions/v1beta1 → apps/v1)

Step 3: Upgrade node groups — one at a time
        a. Create NEW node group with new K8s version
        b. kubectl cordon <old-node>     # stop new pods here
        c. kubectl drain <old-node> \
             --ignore-daemonsets \
             --delete-emptydir-data      # move pods to new nodes
        d. Verify pods on new nodes
        e. Delete old node group

Step 4: Upgrade Add-ons
        kube-proxy, CoreDNS, VPC CNI

Step 5: Verify
        kubectl get nodes
        kubectl get pods -A
```

> **Key:** Set PodDisruptionBudget (PDB) on critical deployments — ensures minimum replicas stay up during drain.
