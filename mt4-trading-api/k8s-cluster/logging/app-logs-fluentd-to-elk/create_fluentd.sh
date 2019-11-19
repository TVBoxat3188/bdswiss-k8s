# create secret fluentd
kubectl create secret generic mt4-trading-api-fluentd-secret-client-key --from-file=id_rsa=./ssl/client.key -n kube-system
kubectl create secret generic mt4-trading-api-fluentd-secret-client-cer --from-file=id_rsa=./ssl/client.cer -n kube-system
kubectl create secret generic mt4-trading-api-fluentd-secret-client-ca-cer --from-file=id_rsa=./ssl/client-ca.cer -n kube-system

# create daemon fluentd
kubectl create -f fluentd-daemonset-elasticsearch-rbac-configmap.yaml
kubectl create -f fluentd-daemonset-elasticsearch-rbac.yaml
