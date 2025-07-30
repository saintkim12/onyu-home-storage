#!/bin/sh
set -e

GIT_USER=saintkim12
GIT_REPO=onyu-home-storage
GIT_BRANCH=main
GIT_URL=https://github.com/${GIT_USER}/${GIT_REPO}.git
STORAGE_DIR=/opt/setup/storage
YOUR_SERVER_IP='<your-server-ip>'

mkdir -p /opt/setup
cd /opt/setup

### [1] raspberry pi 패키지 및 Docker 설치
# echo "📦 Installing Docker..."

### [2] Git 저장소 클론
echo "📥 Cloning Git repository..."
if [ ! -d "$STORAGE_DIR" ]; then
  git clone -b "$GIT_BRANCH" "$GIT_URL" "$STORAGE_DIR"
else
  echo "📦 Repo exists, pulling latest..."
  cd "$STORAGE_DIR" && git pull && cd ..
fi

### [3] 메인 디렉토리로 이동
cd "$STORAGE_DIR"

### [4] MinIO Docker 컨테이너 실행
echo "🚀 Starting MinIO..."
cd minio

echo "MinIO 초기 설정을 시작합니다..."

# 환경 변수 파일 확인
if [ ! -f .env ]; then
    echo "환경 변수 파일이 없습니다. env.example을 .env로 복사합니다..."
    cp env.example .env
    echo "환경 변수 파일을 생성했습니다. .env 파일을 편집하여 실제 값으로 수정하세요."
    exit 1
fi

# 환경 변수 로드
source .env

# 기본 버킷 생성
echo "기본 버킷을 생성합니다..."

# MinIO 클라이언트를 사용하여 버킷 생성
docker-compose run --rm mc sh -c "
mc alias set minio http://minio:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD
mc mb minio/backup
mc mb minio/documents
mc mb minio/media
mc policy set download minio/backup
mc policy set public minio/media
echo '기본 버킷이 생성되었습니다:'
mc ls minio
"

echo "MinIO 초기 설정이 완료되었습니다!"
echo "웹 콘솔: http://localhost:9001"
echo "API 엔드포인트: http://localhost:9000" 
