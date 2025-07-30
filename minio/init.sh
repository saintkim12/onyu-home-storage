#!/bin/bash

# MinIO 설치 및 초기 설정 스크립트 (라즈베리파이 3B용)
# ARMv7 아키텍처용 바이너리 설치

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
STORAGE_DIR="/mnt/exthdd02/minio"
MINIO_DIR="$SCRIPT_DIR"
MINIO_BIN_DIR="$MINIO_DIR/bin"
MINIO_DATA_DIR="$STORAGE_DIR/data"
MINIO_CONFIG_DIR="$MINIO_DIR/config"

# 환경 변수 파일 경로
ENV_FILE="$MINIO_DIR/.env"

log_info "🚀 MinIO 설치 및 초기 설정을 시작합니다..."

# 필요한 디렉토리 생성
log_info "📁 필요한 디렉토리를 생성합니다..."
mkdir -p "$MINIO_BIN_DIR"
mkdir -p "$MINIO_DATA_DIR"
mkdir -p "$MINIO_CONFIG_DIR"

# 시스템 아키텍처 확인
ARCH=$(uname -m)
log_info "시스템 아키텍처: $ARCH"

if [[ "$ARCH" != "armv7l" && "$ARCH" != "aarch64" ]]; then
    log_warning "이 스크립트는 ARM 아키텍처용으로 설계되었습니다."
fi

# MinIO 바이너리 다운로드
MINIO_VERSION="2024-01-16T16-07-38Z"
MINIO_BINARY="minio"

log_info "📥 MinIO 바이너리를 다운로드합니다 (버전: $MINIO_VERSION)..."

# ARMv7용 MinIO 다운로드
if [[ "$ARCH" == "armv7l" ]]; then
    MINIO_URL="https://dl.min.io/server/minio/release/linux-arm/minio"
elif [[ "$ARCH" == "aarch64" ]]; then
    MINIO_URL="https://dl.min.io/server/minio/release/linux-arm64/minio"
else
    log_error "지원되지 않는 아키텍처입니다: $ARCH"
    exit 1
fi

# 기존 바이너리 제거
if [[ -f "$MINIO_BIN_DIR/$MINIO_BINARY" ]]; then
    log_info "기존 MinIO 바이너리를 제거합니다..."
    rm -f "$MINIO_BIN_DIR/$MINIO_BINARY"
fi

# 새 바이너리 다운로드
if curl -L "$MINIO_URL" -o "$MINIO_BIN_DIR/$MINIO_BINARY"; then
    chmod +x "$MINIO_BIN_DIR/$MINIO_BINARY"
    log_success "MinIO 바이너리 다운로드 완료"
else
    log_error "MinIO 바이너리 다운로드 실패"
    exit 1
fi

# 환경 변수 파일 생성
log_info "⚙️ 환경 변수 파일을 생성합니다..."

cat > "$ENV_FILE" << EOF
# MinIO 환경 변수
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin123
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_DATA_DIR=$MINIO_DATA_DIR
MINIO_CONFIG_DIR=$MINIO_CONFIG_DIR
EOF

log_success "환경 변수 파일 생성 완료: $ENV_FILE"

# systemd 서비스 파일 생성
log_info "🔧 systemd 서비스 파일을 생성합니다..."

sudo tee /etc/systemd/system/minio.service > /dev/null << EOF
[Unit]
Description=MinIO Object Storage Server
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target
AssertFileIsExecutable=$MINIO_BIN_DIR/minio

[Service]
WorkingDirectory=$MINIO_DIR
User=root
Group=root
EnvironmentFile=$ENV_FILE
ExecStart=$MINIO_BIN_DIR/minio server \$MINIO_DATA_DIR --console-address ":\${MINIO_CONSOLE_PORT}"
Restart=always
LimitNOFILE=65536

# Specifies the maximum file descriptor number that can be opened by this process
# LimitNOFILE=65536

# Specifies the maximum number of threads this process can create
# TasksMax=infinity

# Disable timeout logic and wait until process is stopped
TimeoutStopSec=infinity
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

# systemd 재로드 및 서비스 활성화
log_info "🔄 systemd를 재로드하고 서비스를 활성화합니다..."
sudo systemctl daemon-reload
sudo systemctl enable minio.service

log_success "✅ MinIO 설치 및 초기 설정이 완료되었습니다!"

# 서비스 시작
log_info "🚀 MinIO 서비스를 시작합니다..."
sudo systemctl start minio.service

# 서비스 상태 확인
sleep 3
if sudo systemctl is-active --quiet minio.service; then
    log_success "MinIO 서비스가 성공적으로 시작되었습니다!"
    log_info "📊 서비스 상태:"
    sudo systemctl status minio.service --no-pager -l
else
    log_error "MinIO 서비스 시작에 실패했습니다."
    sudo systemctl status minio.service --no-pager -l
    exit 1
fi

# 접속 정보 출력
log_info "🌐 MinIO 접속 정보:"
echo "   - API 엔드포인트: http://$(hostname -I | awk '{print $1}'):9000"
echo "   - 웹 콘솔: http://$(hostname -I | awk '{print $1}'):9001"
echo "   - 기본 사용자: minioadmin"
echo "   - 기본 비밀번호: minioadmin123"
echo ""
log_warning "⚠️  보안을 위해 기본 비밀번호를 변경하는 것을 권장합니다." 