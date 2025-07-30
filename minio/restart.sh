#!/bin/bash

# MinIO 서비스 재시작 스크립트

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 스크립트 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

log_info "🔄 MinIO 서비스를 재시작합니다..."

# 환경 변수 파일 확인
if [[ ! -f "$ENV_FILE" ]]; then
    log_error "환경 변수 파일을 찾을 수 없습니다: $ENV_FILE"
    log_error "먼저 init.sh를 실행하여 MinIO를 설치해주세요."
    exit 1
fi

# 환경 변수 로드
source "$ENV_FILE"

# MinIO 서비스 상태 확인
if ! sudo systemctl is-active --quiet minio.service; then
    log_warning "MinIO 서비스가 실행 중이 아닙니다."
fi

# 서비스 중지
log_info "⏹️ MinIO 서비스를 중지합니다..."
sudo systemctl stop minio.service

# 잠시 대기
sleep 2

# 서비스 시작
log_info "🚀 MinIO 서비스를 시작합니다..."
sudo systemctl start minio.service

# 서비스 상태 확인
sleep 3
if sudo systemctl is-active --quiet minio.service; then
    log_success "✅ MinIO 서비스가 성공적으로 재시작되었습니다!"
    
    # 서비스 상태 출력
    log_info "📊 서비스 상태:"
    sudo systemctl status minio.service --no-pager -l
    
    # 접속 정보 출력
    log_info "🌐 MinIO 접속 정보:"
    echo "   - API 엔드포인트: http://$(hostname -I | awk '{print $1}'):$MINIO_PORT"
    echo "   - 웹 콘솔: http://$(hostname -I | awk '{print $1}'):$MINIO_CONSOLE_PORT"
    echo "   - 사용자: $MINIO_ROOT_USER"
    echo ""
    
    # 포트 확인
    log_info "🔍 포트 상태 확인:"
    if netstat -tlnp 2>/dev/null | grep -q ":$MINIO_PORT "; then
        log_success "API 포트 $MINIO_PORT: 활성화됨"
    else
        log_warning "API 포트 $MINIO_PORT: 비활성화됨"
    fi
    
    if netstat -tlnp 2>/dev/null | grep -q ":$MINIO_CONSOLE_PORT "; then
        log_success "콘솔 포트 $MINIO_CONSOLE_PORT: 활성화됨"
    else
        log_warning "콘솔 포트 $MINIO_CONSOLE_PORT: 비활성화됨"
    fi
    
else
    log_error "❌ MinIO 서비스 재시작에 실패했습니다."
    log_info "📊 서비스 상태:"
    sudo systemctl status minio.service --no-pager -l
    
    # 로그 확인
    log_info "📋 최근 로그 확인:"
    sudo journalctl -u minio.service --no-pager -n 20
    
    exit 1
fi 