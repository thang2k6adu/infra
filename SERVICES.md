
Check Kubernetes Dashboard

Kiểm tra pod & service
kubectl -n kubernetes-dashboard get pods
kubectl -n kubernetes-dashboard get svc

Kiểm tra RBAC
kubectl get clusterrole dashboard-admin
kubectl get clusterrolebinding kubernetes-dashboard-admin
kubectl -n kubernetes-dashboard get sa kubernetes-dashboard-admin

Lấy token đăng nhập
kubectl -n kubernetes-dashboard create token kubernetes-dashboard-admin

Port-forward Dashboard (nhớ mở firewall)
kubectl -n kubernetes-dashboard port-forward --address 0.0.0.0 service/kubernetes-dashboard 8443:443

Check kube-prometheus-stack
Kiểm tra pod
kubectl -n monitoring get pods

Kiểm tra CRDs
kubectl get crd | grep prometheus
kubectl get crd | grep servicemonitor

Kiểm tra Prometheus
kubectl -n monitoring get prometheus
kubectl -n monitoring get svc

Kiểm tra PVC
kubectl -n monitoring get pvc

Port-forward Prometheus UI (nhớ mở firewall)
kubectl -n monitoring port-forward --address 0.0.0.0 svc/monitoring-kube-prometheus-prometheus 9090:9090


Mở:

http://localhost:9090

3. Check Ingress NGINX
Kiểm tra namespace & pod
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx get svc

Kiểm tra IngressClass
kubectl get ingressclass

Kiểm tra HPA
kubectl -n ingress-nginx get hpa

Kiểm tra ServiceMonitor (metrics)
kubectl -n ingress-nginx get servicemonitor

Test metrics endpoint
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller-metrics 10254:10254
curl http://localhost:10254/metrics