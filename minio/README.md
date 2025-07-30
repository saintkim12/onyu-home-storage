# MinIO Object Storage (라즈베리파이 3B용)

라즈베리파이 3B (ARMv7)에서 실행되는 MinIO Object Storage 서버입니다. Docker 대신 바이너리를 직접 설치하여 사용합니다.

## 📋 요구사항

- 라즈베리파이 3B (ARMv7 아키텍처)
- Raspberry Pi OS 또는 Ubuntu Server
- 최소 2GB RAM (권장: 4GB+)
- 최소 10GB 저장 공간
- 인터넷 연결 (바이너리 다운로드용)

## 🚀 설치 및 설정

### 1. 초기 설치

```bash
# 스크립트 실행 권한 부여
chmod +x init.sh restart.sh

# MinIO 설치 및 초기 설정 실행
sudo ./init.sh
```

이 스크립트는 다음 작업을 수행합니다:
- ARMv7용 MinIO 바이너리 다운로드
- 필요한 디렉토리 생성 (`bin/`, `data/`, `config/`)
- 환경 변수 파일 생성 (`.env`)
- systemd 서비스 파일 생성 및 활성화
- MinIO 서비스 시작

### 2. 서비스 재시작

```bash
# MinIO 서비스 재시작
sudo ./restart.sh
```

## ⚙️ 설정

### 환경 변수

`.env` 파일에서 다음 설정을 변경할 수 있습니다:

```bash
# 기본 설정
MINIO_ROOT_USER=minioadmin          # 관리자 사용자명
MINIO_ROOT_PASSWORD=minioadmin123   # 관리자 비밀번호
MINIO_PORT=9000                     # API 포트
MINIO_CONSOLE_PORT=9001             # 웹 콘솔 포트
MINIO_DATA_DIR=/path/to/data        # 데이터 저장 경로
MINIO_CONFIG_DIR=/path/to/config    # 설정 파일 경로
```

### 보안 설정

**중요**: 기본 비밀번호를 반드시 변경하세요!

```bash
# 환경 변수 파일 편집
sudo nano .env

# 비밀번호 변경 후 서비스 재시작
sudo ./restart.sh
```

## 🌐 접속 정보

설치 완료 후 다음 주소로 접속할 수 있습니다:

- **API 엔드포인트**: `http://[라즈베리파이_IP]:9000`
- **웹 콘솔**: `http://[라즈베리파이_IP]:9001`
- **기본 사용자**: `minioadmin`
- **기본 비밀번호**: `minioadmin123`

## 📁 디렉토리 구조

```
storage/minio/
├── init.sh              # 초기 설치 스크립트
├── restart.sh           # 서비스 재시작 스크립트
├── .env                 # 환경 변수 파일
├── bin/                 # MinIO 바이너리
│   └── minio
├── data/                # 데이터 저장소
└── config/              # 설정 파일
```

## 🔧 관리 명령어

### 서비스 상태 확인
```bash
sudo systemctl status minio.service
```

### 서비스 로그 확인
```bash
sudo journalctl -u minio.service -f
```

### 서비스 수동 시작/중지
```bash
sudo systemctl start minio.service
sudo systemctl stop minio.service
```

### 서비스 자동 시작 설정/해제
```bash
sudo systemctl enable minio.service
sudo systemctl disable minio.service
```

## 🛠️ 문제 해결

### 1. 포트 충돌
다른 서비스가 9000 또는 9001 포트를 사용하는 경우:
```bash
# 포트 사용 확인
sudo netstat -tlnp | grep :9000
sudo netstat -tlnp | grep :9001

# .env 파일에서 포트 변경 후 재시작
sudo ./restart.sh
```

### 2. 권한 문제
```bash
# 디렉토리 권한 확인
ls -la bin/ data/ config/

# 권한 수정 (필요한 경우)
sudo chown -R root:root bin/ data/ config/
sudo chmod 755 bin/
sudo chmod 700 data/ config/
```

### 3. 메모리 부족
라즈베리파이의 메모리가 부족한 경우:
```bash
# 스왑 파일 생성
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 부팅 시 자동 마운트
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 📊 성능 최적화

### 1. SD 카드 최적화
```bash
# /etc/fstab에 추가
tmpfs /tmp tmpfs defaults,noatime,nosuid,size=100m 0 0
tmpfs /var/tmp tmpfs defaults,noatime,nosuid,size=30m 0 0
```

### 2. 네트워크 최적화
```bash
# /etc/sysctl.conf에 추가
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
```

## 🔄 업데이트

MinIO를 최신 버전으로 업데이트하려면:

```bash
# 서비스 중지
sudo systemctl stop minio.service

# init.sh 재실행 (바이너리만 업데이트)
sudo ./init.sh

# 또는 수동으로 바이너리 교체
sudo rm bin/minio
# 새 바이너리 다운로드 후
sudo ./restart.sh
```

## 📝 로그

MinIO 로그는 다음 명령어로 확인할 수 있습니다:

```bash
# 실시간 로그 확인
sudo journalctl -u minio.service -f

# 최근 로그 확인
sudo journalctl -u minio.service --no-pager -n 50

# 특정 날짜 로그 확인
sudo journalctl -u minio.service --since "2024-01-01" --until "2024-01-02"
```

## 🆘 지원

문제가 발생하면 다음을 확인하세요:

1. 시스템 로그: `sudo journalctl -u minio.service`
2. 서비스 상태: `sudo systemctl status minio.service`
3. 포트 상태: `sudo netstat -tlnp | grep minio`
4. 디스크 공간: `df -h`
5. 메모리 사용량: `free -h` 