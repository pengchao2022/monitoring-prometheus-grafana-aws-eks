#!/bin/bash

set -e

echo "🚀 Starting EKS Monitoring Stack Deployment with ALB..."

NAMESPACE=${NAMESPACE:-"monitoring"}
CLUSTER_NAME=${CLUSTER_NAME:-$EKS_CLUSTER_NAME}
AWS_REGION=${AWS_REGION:-$AWS_DEFAULT_REGION}

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

# 验证环境变量
validate_environment() {
    local missing_vars=()
    
    [[ -z "$CLUSTER_NAME" ]] && missing_vars+=("EKS_CLUSTER_NAME")
    [[ -z "$AWS_REGION" ]] && missing_vars+=("AWS_REGION")
    [[ -z "$GRAFANA_ADMIN_USER" ]] && missing_vars+=("GRAFANA_ADMIN_USER")
    [[ -z "$GRAFANA_ADMIN_PASSWORD" ]] && missing_vars+=("GRAFANA_ADMIN_PASSWORD")
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "缺少以下环境变量:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        exit 1
    fi
}

# 检查 AWS Load Balancer Controller
check_alb_controller() {
    log_info "检查 AWS Load Balancer Controller..."
    
    if kubectl get deployment aws-load-balancer-controller -n kube-system &> /dev/null; then
        log_info "✅ AWS Load Balancer Controller 已安装"
        
        # 检查控制器状态
        local ready=$(kubectl get deployment aws-load-balancer-controller -n kube-system -o jsonpath='{.status.readyReplicas}')
        local desired=$(kubectl get deployment aws-load-balancer-controller -n kube-system -o jsonpath='{.status.replicas}')
        
        if [[ "$ready" == "$desired" ]]; then
            log_info "✅ AWS Load Balancer Controller 运行正常 ($ready/$desired)"
        else
            log_warn "⚠️ AWS Load Balancer Controller 未就绪 ($ready/$desired)"
        fi
    else
        log_error "❌ AWS Load Balancer Controller 未找到"
        log_error "请先安装 AWS Load Balancer Controller"
        exit 1
    fi
}

# 安装监控栈
install_monitoring_stack() {
    log_info "安装 kube-prometheus-stack..."
    
    helm upgrade --install kube-prometheus-stack \
        prometheus-community/kube-prometheus-stack \
        --namespace $NAMESPACE \
        --version 48.1.1 \
        --values charts/kube-prometheus-stack/values-alb.yaml \
        --wait \
        --timeout 20m \
        --set grafana.admin.password=$GRAFANA_ADMIN_PASSWORD
    
    log_info "✅ kube-prometheus-stack 安装完成"
}

# 部署 Ingress 资源
deploy_ingress_resources() {
    log_info "部署 Ingress 资源..."
    
    if [[ -d "kubernetes/ingress" ]]; then
        kubectl apply -f kubernetes/ingress/ -n $NAMESPACE
    fi
    
    log_info "✅ Ingress 资源部署完成"
}

# 等待 ALB 就绪
wait_for_alb() {
    log_info "等待 ALB 创建..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local alb_hostname=$(kubectl get ingress grafana-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        if [[ -n "$alb_hostname" ]]; then
            log_info "✅ ALB 已创建: $alb_hostname"
            echo "$alb_hostname" > .alb-hostname
            return 0
        fi
        
        log_info "尝试 $attempt/$max_attempts - 等待 ALB 创建..."
        sleep 30
        ((attempt++))
    done
    
    log_error "❌ ALB 创建超时"
    return 1
}

# 显示部署信息
show_deployment_info() {
    log_info "=== 部署完成 ==="
    
    GRAFANA_ALB=$(kubectl get ingress grafana-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    PROMETHEUS_ALB=$(kubectl get ingress prometheus-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    ALERTMANAGER_ALB=$(kubectl get ingress alertmanager-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    
    log_info "ALB 访问地址:"
    log_info "  📊 Grafana: http://$GRAFANA_ALB"
    log_info "  📈 Prometheus: http://$PROMETHEUS_ALB"
    log_info "  🚨 Alertmanager: http://$ALERTMANAGER_ALB"
    
    log_info "Grafana 登录信息:"
    log_info "  用户名: $GRAFANA_ADMIN_USER"
    log_info "  密码: $GRAFANA_ADMIN_PASSWORD"
}

# 主函数
main() {
    log_info "开始部署监控栈"
    log_info "集群: $CLUSTER_NAME"
    log_info "区域: $AWS_REGION"
    log_info "命名空间: $NAMESPACE"
    
    validate_environment
    
    # 更新 kubeconfig
    log_info "配置 kubectl..."
    aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
    
    # 检查集群连接
    log_info "验证集群连接..."
    kubectl cluster-info
    kubectl get nodes
    
    # 检查 ALB Controller
    check_alb_controller
    
    # 创建命名空间
    log_info "创建命名空间..."
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # 创建 Grafana secret
    log_info "创建 Grafana secret..."
    kubectl create secret generic grafana-admin-secret \
        --namespace=$NAMESPACE \
        --from-literal=admin-user=$GRAFANA_ADMIN_USER \
        --from-literal=admin-password=$GRAFANA_ADMIN_PASSWORD \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # 添加 Helm repo
    log_info "添加 Helm 仓库..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # 安装监控栈
    install_monitoring_stack
    
    # 部署 Ingress
    deploy_ingress_resources
    
    # 等待 ALB
    wait_for_alb
    
    # 健康检查
    log_info "执行健康检查..."
    if [[ -f "scripts/health-check.sh" ]]; then
        chmod +x scripts/health-check.sh
        ./scripts/health-check.sh
    fi
    
    # 显示部署信息
    show_deployment_info
    
    log_info "✅ 部署完成!"
}

main "$@"