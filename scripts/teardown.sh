#!/bin/bash

set -e

echo "🧹 Cleaning up Monitoring Stack..."

NAMESPACE=${NAMESPACE:-"monitoring"}
CLUSTER_NAME=${CLUSTER_NAME:-$EKS_CLUSTER_NAME}
AWS_REGION=${AWS_REGION:-$AWS_DEFAULT_REGION}

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 验证环境
if [[ -z "$CLUSTER_NAME" ]] || [[ -z "$AWS_REGION" ]]; then
    log_error "Missing required environment variables"
    exit 1
fi

# 更新 kubeconfig
log_info "Updating kubeconfig..."
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# 删除 Ingress 资源 (这会删除 ALB)
log_info "Deleting Ingress resources..."
kubectl delete -f kubernetes/ingress/ -n $NAMESPACE --ignore-not-found=true

# 等待 ALB 删除
log_info "Waiting for ALB deletion..."
sleep 60

# 删除 Helm release
log_info "Deleting Helm release..."
helm uninstall kube-prometheus-stack -n $NAMESPACE --ignore-not-found=true

# 删除 PVCs
log_info "Deleting Persistent Volume Claims..."
kubectl delete pvc -n $NAMESPACE --all --ignore-not-found=true

# 删除 secrets
log_info "Deleting secrets..."
kubectl delete secret grafana-admin-secret -n $NAMESPACE --ignore-not-found=true

# 删除 namespace
log_info "Deleting namespace..."
kubectl delete namespace $NAMESPACE --ignore-not-found=true

# 验证清理
log_info "Verifying cleanup..."
kubectl get namespaces | grep $NAMESPACE || log_info "Namespace $NAMESPACE deleted"
helm list -n $NAMESPACE | grep kube-prometheus-stack || log_info "Helm release deleted"

log_info "✅ Cleanup completed successfully!"