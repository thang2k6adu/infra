first access SETUP_CLUSTER_WITH_GITOPS.md to setup the cluster with gitops

2. access README.md to understand the architecture, setup argoCD into cluster

3. access SETUP_CORE.md to underestand the core components of the application

4.Access SERVICES.md to test all the feature

delete unused, err, success pods, non pod replicasSet

kubectl delete pod -A --field-selector=status.phase=Succeeded
kubectl delete pod -A --field-selector=status.phase=Failed
kubectl get rs -A --no-headers | awk '$4==0 {print $1, $2}' | xargs -r -n2 kubectl delete rs -n
