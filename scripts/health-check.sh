#!/bin/bash

set -e

echo "🔍 Running comprehensive health checks..."

NAMESPACE=${NAMESPACE:-"monitoring"}
TIMEOUT=${TIMEOUT:-300}

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_pods() {
    echo "📊 Checking Pod status..."
    local pods=$(kubectl get pods -n $NAMESPACE --no-headers | wc -l)
    
    if [[ $pods -eq 0 ]]; then
        echo -e "${RED}❌ No pods found in namespace $NAMESPACE${NC}"
        return 1
    fi
    
    kubectl get pods -n $NAMESPACE
    
    # 检查所有 Pods 是否就绪
    local not_ready=$(kubectl get pods -n $NAMESPACE --no-headers | grep -v "Running" | grep -v "Completed" | wc -l)
    
    if [[ $not_ready -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ Some pods are not ready${NC}"
        kubectl get pods -n $NAMESPACE | grep -v "Running" | grep -v "Completed"
        return 1
    fi
    
    echo -e "${GREEN}✅ All pods are running${NC}"
}

check_services() {
    echo "🌐 Checking Service status..."
    kubectl get services -n $NAMESPACE
    
    local services=$(kubectl get services -n $NAMESPACE --no-headers | wc -l)
    
    if [[ $services -eq 0 ]]; then
        echo -e "${RED}❌ No services found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Services are created${NC}"
}

check_ingress() {
    echo "🚪 Checking Ingress status..."
    kubectl get ingress -n $NAMESPACE
    
    local ingress_hostname=$(kubectl get ingress grafana-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [[ -z "$ingress_hostname" ]]; then
        echo -e "${YELLOW}⚠️ Ingress hostname not available yet${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Ingress is provisioned: $ingress_hostname${NC}"
}

check_helm_releases() {
    echo "📦 Checking Helm releases..."
    helm list -n $NAMESPACE
    
    local release_count=$(helm list -n $NAMESPACE --no-headers | wc -l)
    
    if [[ $release_count -eq 0 ]]; then
        echo -e "${RED}❌ No Helm releases found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Helm releases are deployed${NC}"
}

check_critical_components() {
    echo "🔧 Checking critical components..."
    
    local components=(
        "kube-prometheus-stack-grafana"
        "kube-prometheus-stack-prometheus"
        "kube-prometheus-stack-operator"
    )
    
    for component in "${components[@]}"; do
        if kubectl get deployment $component -n $NAMESPACE > /dev/null 2>&1; then
            local ready=$(kubectl get deployment $component -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
            local desired=$(kubectl get deployment $component -n $NAMESPACE -o jsonpath='{.status.replicas}')
            
            if [[ "$ready" == "$desired" ]]; then
                echo -e "${GREEN}✅ $component is ready ($ready/$desired)${NC}"
            else
                echo -e "${RED}❌ $component is not ready ($ready/$desired)${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}⚠️ $component deployment not found${NC}"
        fi
    done
}

# 执行所有检查
check_pods
check_services
check_ingress
check_helm_releases
check_critical_components

echo -e "${GREEN}✅ All health checks completed successfully!${NC}"