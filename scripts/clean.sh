#!/bin/bash

set -e

NAMESPACE=${1:-"monitoring"}

echo "🧹 Starting monitoring stack cleanup..."
echo "Namespace: $NAMESPACE"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命名空间是否存在
check_namespace() {
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 1. 卸载 Helm release
uninstall_helm() {
    log_info "Checking Helm releases..."
    if helm list -n "$NAMESPACE" | grep -q "kube-prometheus-stack"; then
        log_info "Uninstalling kube-prometheus-stack..."
        helm uninstall kube-prometheus-stack -n "$NAMESPACE"
    else
        log_warn "kube-prometheus-stack release not found"
    fi
}

# 2. 删除所有 Kubernetes 资源
delete_resources() {
    log_info "Deleting all resources in namespace $NAMESPACE..."
    
    # 删除 Ingress
    if kubectl get ingress -n "$NAMESPACE" &> /dev/null; then
        kubectl delete ingress --all -n "$NAMESPACE"
        log_info "Ingress resources deleted"
    fi
    
    # 删除所有其他资源
    kubectl delete all --all -n "$NAMESPACE" 2>/dev/null && log_info "All resources deleted" || log_warn "No resources to delete"
    
    # 删除 PVC
    kubectl delete pvc --all -n "$NAMESPACE" 2>/dev/null && log_info "PVCs deleted" || log_warn "No PVCs to delete"
    
    # 删除 secrets
    kubectl delete secret --all -n "$NAMESPACE" 2>/dev/null && log_info "Secrets deleted" || log_warn "No secrets to delete"
}

# 3. 删除命名空间
delete_namespace() {
    log_info "Deleting namespace $NAMESPACE..."
    kubectl delete namespace "$NAMESPACE" 2>/dev/null && log_info "Namespace deleted" || log_warn "Namespace already deleted"
}

# 主清理流程
main() {
    echo "========================================"
    echo "    Monitoring Stack Cleanup"
    echo "========================================"
    
    if check_namespace; then
        log_info "Namespace $NAMESPACE exists, starting cleanup..."
        uninstall_helm
        sleep 10
        delete_resources
        sleep 10
        delete_namespace
    else
        log_warn "Namespace $NAMESPACE does not exist, nothing to clean up"
    fi
    
    echo "========================================"
    log_info "✅ Cleanup completed!"
}

main "$@"