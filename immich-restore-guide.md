# Immich 복원 가이드 (Restic + S3 Glacier Deep Archive)

> **목적**: 재난 상황에서 Immich 데이터를 안전하게 복원하기 위한 완전한 가이드
>
> **전제 조건**: [immich-backup.notion.md](immich-backup.notion.md)의 백업 전략을 사용 중인 경우

---

## 목차

1. [복원 시나리오](#-복원-시나리오)
2. [사전 준비사항](#-사전-준비사항)
3. [복원 절차](#-복원-절차)
4. [검증 및 확인](#-검증-및-확인)
5. [트러블슈팅](#-트러블슈팅)
6. [테스트 계획](#-테스트-계획)

---

## 🎯 복원 시나리오

### 시나리오 1: 로컬 데이터 손실 (서버는 정상)

**상황**: Immich 데이터만 삭제되었으나 서버 환경은 정상

- 복원 소요 시간: **약 1-2시간** (로컬 restic 저장소 사용)
- 복원 난이도: ⭐ (쉬움)
- 사용 저장소: 로컬 restic 저장소 (`/mnt/exthdd02/immich-archive-restic/restic`)

### 시나리오 2: 로컬 저장소 손실 (외장 HDD 고장)

**상황**: 외장 HDD 고장으로 로컬 restic 저장소 사용 불가

- 복원 소요 시간: **48시간 + 2-3시간** (Glacier 복원 + 다운로드 + 데이터 추출)
- 복원 난이도: ⭐⭐ (보통)
- 사용 저장소: S3 Glacier Deep Archive

### 시나리오 3: 완전한 재난 (서버 전체 손실)

**상황**: 서버/스토리지 전체 손실, 새 환경에서 복원 필요

- 복원 소요 시간: **48시간 + 4-6시간** (환경 재구축 포함)
- 복원 난이도: ⭐⭐⭐ (어려움)
- 필요 작업: 서버 재구축 + S3 복원 + 데이터 추출

### 시나리오 4: 특정 시점 복원

**상황**: 실수로 사진 삭제, 특정 날짜의 백업으로 복원 필요

- 복원 소요 시간: **1-2시간** (로컬) 또는 **48시간 + 2시간** (S3)
- 복원 난이도: ⭐⭐ (보통)
- 특징: 특정 스냅샷 선택 가능

---

## 🛠 사전 준비사항

### 필수 도구 설치

```bash
# Restic 설치 (복원에 필수)
sudo apt update
sudo apt install restic

# MinIO Client 설치 (S3 접근용)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# mc alias 설정 (AWS S3)
mc alias set aws https://s3.amazonaws.com \
  <AWS_ACCESS_KEY_ID> \
  <AWS_SECRET_ACCESS_KEY>
```

### 필요한 정보 확인

- **S3 버킷 이름**: `immich-archive-restic`
- **로컬 restic 저장소 경로**: `/mnt/exthdd02/immich-archive-restic/restic`
- **Immich 원본 데이터 경로**: MinIO 볼륨 (`/mnt/minio/immich`)
- **Restic 비밀번호**: 없음 (`--insecure-no-password` 사용)

---

## 📋 복원 절차

### 절차 A: 로컬 저장소에서 복원 (가장 빠름)

**적용 시나리오**: 시나리오 1, 4 (로컬 저장소가 정상인 경우)

#### 1단계: 스냅샷 확인

```bash
# 사용 가능한 스냅샷 목록 확인
restic -r /mnt/exthdd02/immich-archive-restic/restic \
  --insecure-no-password snapshots

# 출력 예시:
# ID        Time                 Host        Tags        Paths
# --------------------------------------------------------------
# 4f3c2a1b  2025-10-10 01:05:23  onyu-home              /mnt/minio/immich
# 7a8b5d9e  2025-11-01 01:05:45  onyu-home              /mnt/minio/immich
# 2e9f1c4a  2025-12-01 01:05:12  onyu-home              /mnt/minio/immich
```

#### 2단계: 특정 날짜/최신 스냅샷 선택

```bash
# 특정 스냅샷 상세 정보 확인
restic -r /mnt/exthdd02/immich-archive-restic/restic \
  --insecure-no-password snapshots <snapshot-id>

# 스냅샷 내용 미리보기 (파일 목록)
restic -r /mnt/exthdd02/immich-archive-restic/restic \
  --insecure-no-password ls <snapshot-id>
```

#### 3단계: 데이터 복원

```bash
# 임시 위치에 복원 (원본 덮어쓰기 방지)
mkdir -p /mnt/exthdd02/restored-immich
restic -r /mnt/exthdd02/immich-archive-restic/restic \
  --insecure-no-password restore latest \
  --target /mnt/exthdd02/restored-immich

# 또는 특정 스냅샷 복원
restic -r /mnt/exthdd02/immich-archive-restic/restic \
  --insecure-no-password restore <snapshot-id> \
  --target /mnt/exthdd02/restored-immich

# 복원 진행률 표시
# Restic은 자동으로 진행률을 표시합니다
```

#### 4단계: 복원된 데이터 확인

```bash
# 복원된 파일 구조 확인
ls -lh /mnt/exthdd02/restored-immich/mnt/minio/immich/

# 용량 확인 (원본과 비교)
du -sh /mnt/exthdd02/restored-immich/mnt/minio/immich/
du -sh /mnt/minio/immich/  # 현재 데이터 (비교용)
```

#### 5단계: Immich에 데이터 복구

**옵션 A: Docker 볼륨 교체 (완전 복원)**

```bash
# Immich 서비스 중지
cd /path/to/immich/docker-compose
docker compose down

# 기존 MinIO 데이터 백업 (혹시 모를 상황 대비)
mv /mnt/minio/immich /mnt/minio/immich.old.$(date +%Y%m%d)

# 복원된 데이터로 교체
cp -a /mnt/exthdd02/restored-immich/mnt/minio/immich /mnt/minio/

# 권한 확인 (중요!)
chown -R 1000:1000 /mnt/minio/immich

# Immich 재시작
docker compose up -d

# 로그 확인
docker compose logs -f immich-server
```

**옵션 B: 특정 파일만 복원 (부분 복원)**

```bash
# 특정 경로만 복원 (예: 특정 날짜의 사진)
restic -r /mnt/exthdd02/immich-archive-restic/restic \
  --insecure-no-password restore <snapshot-id> \
  --target /mnt/exthdd02/restored-immich \
  --include '/mnt/minio/immich/library/user-uuid/2024/01/*'

# 복원된 파일만 복사
cp -a /mnt/exthdd02/restored-immich/mnt/minio/immich/library/user-uuid/2024/01/* \
  /mnt/minio/immich/library/user-uuid/2024/01/

# Immich 재시작 필요 없음 (새 파일 자동 감지)
```

---

### 절차 B: S3 Glacier에서 복원 (재난 복구)

**적용 시나리오**: 시나리오 2, 3, 4 (로컬 저장소 사용 불가)

#### 1단계: Glacier 복원 요청 (AWS Console 또는 CLI)

**AWS Console 사용 (GUI)**:

1. AWS S3 Console 접속: https://s3.console.aws.amazon.com/
2. 버킷 선택: `immich-archive-restic`
3. 모든 객체 선택 (폴더별 선택 가능)
4. 작업 → "복원 시작" 클릭
5. 복원 옵션 설정:
   - **복원 계층**: Standard (12시간) 또는 Bulk (48시간, 저렴)
   - **복원 일수**: 7일 (충분한 시간 확보)
6. 복원 시작

**AWS CLI 사용 (자동화)**:

```bash
# AWS CLI 설치 (없는 경우)
sudo apt install awscli
aws configure  # Access Key, Secret Key, Region 입력

# 버킷 내 모든 객체 복원 요청 (Bulk 계층, 48시간)
aws s3api list-objects-v2 \
  --bucket immich-archive-restic \
  --query 'Contents[].Key' \
  --output text | \
while read key; do
  aws s3api restore-object \
    --bucket immich-archive-restic \
    --key "$key" \
    --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Bulk"}}'
done

# 복원 상태 확인
aws s3api head-object \
  --bucket immich-archive-restic \
  --key data/0a/0a1b2c3d4e5f... \
  | jq '.Restore'
# 출력: "ongoing-request="true"" (진행 중)
# 출력: "ongoing-request="false", expiry-date="..."" (완료)
```

#### 2단계: 복원 완료 대기 (12-48시간)

```bash
# 복원 상태 모니터링 스크립트
cat > check-glacier-restore.sh << 'EOF'
#!/bin/bash
while true; do
  STATUS=$(aws s3api head-object \
    --bucket immich-archive-restic \
    --key config \
    2>/dev/null | jq -r '.Restore // "not started"')

  echo "[$(date)] Restore status: $STATUS"

  if [[ "$STATUS" == *"false"* ]]; then
    echo "Restore completed!"
    break
  fi

  sleep 3600  # 1시간마다 확인
done
EOF

chmod +x check-glacier-restore.sh
./check-glacier-restore.sh
```

#### 3단계: S3에서 로컬로 다운로드

```bash
# 새 로컬 저장소 위치 준비
mkdir -p /mnt/exthdd02/restored-restic-repo

# S3 → 로컬 다운로드 (mc mirror 사용)
mc mirror aws/immich-archive-restic /mnt/exthdd02/restored-restic-repo

# 다운로드 진행률 확인
# mc는 자동으로 진행률을 표시합니다
# 예상 소요 시간: 1-2시간 (63GB 기준, 인터넷 속도에 따라 다름)
```

#### 4단계: Restic 저장소 무결성 확인

```bash
# 저장소 검증 (손상 여부 확인)
restic -r /mnt/exthdd02/restored-restic-repo \
  --insecure-no-password check

# 출력 예시:
# using temporary cache in /tmp/restic-check-cache-123456789
# repository 0a1b2c3d opened successfully, password is correct
# created new cache in /tmp/restic-check-cache-123456789
# create exclusive lock for repository
# load indexes
# check all packs
# check snapshots, trees and blobs
# no errors were found
```

#### 5단계: 스냅샷 확인 및 데이터 복원

```bash
# 스냅샷 목록 확인
restic -r /mnt/exthdd02/restored-restic-repo \
  --insecure-no-password snapshots

# 데이터 복원 (절차 A의 3-5단계와 동일)
restic -r /mnt/exthdd02/restored-restic-repo \
  --insecure-no-password restore latest \
  --target /mnt/exthdd02/restored-immich
```

---

### 절차 C: 새 서버에서 완전 복원 (재난 복구)

**적용 시나리오**: 시나리오 3 (서버 전체 손실)

#### 1단계: 새 서버 환경 구축

```bash
# 기본 패키지 설치
sudo apt update
sudo apt install -y docker.io docker-compose git restic awscli

# 사용자를 docker 그룹에 추가
sudo usermod -aG docker $USER
newgrp docker

# MinIO Client 설치
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# 외장 HDD 마운트 (필요시)
sudo mkdir -p /mnt/exthdd02
sudo mount /dev/sdb1 /mnt/exthdd02  # 디바이스 이름은 상황에 따라 다름
```

#### 2단계: AWS 자격 증명 설정

```bash
# AWS CLI 설정
aws configure
# AWS Access Key ID: <입력>
# AWS Secret Access Key: <입력>
# Default region name: ap-northeast-2
# Default output format: json

# mc alias 설정
mc alias set aws https://s3.amazonaws.com \
  <AWS_ACCESS_KEY_ID> \
  <AWS_SECRET_ACCESS_KEY>
```

#### 3단계: S3에서 복원 (절차 B와 동일)

절차 B의 1-4단계를 따릅니다.

#### 4단계: Immich Docker 환경 재구축

```bash
# Immich 설치 디렉토리 생성
mkdir -p ~/immich
cd ~/immich

# docker-compose.yml 및 .env 파일 복원
# (백업해둔 설정 파일을 복사하거나 새로 작성)

# MinIO 데이터 디렉토리 생성
sudo mkdir -p /mnt/minio/immich
sudo chown -R 1000:1000 /mnt/minio/immich

# 복원된 데이터 복사
cp -a /mnt/exthdd02/restored-immich/mnt/minio/immich/* /mnt/minio/immich/

# Immich 시작
docker compose up -d

# 로그 확인
docker compose logs -f
```

---

## ✅ 검증 및 확인

### 복원 후 필수 확인 사항

#### 1. 데이터 무결성 확인

```bash
# 파일 개수 비교 (복원 전후)
find /mnt/minio/immich -type f | wc -l
find /mnt/exthdd02/restored-immich/mnt/minio/immich -type f | wc -l

# 용량 비교
du -sh /mnt/minio/immich
du -sh /mnt/exthdd02/restored-immich/mnt/minio/immich

# 샘플 파일 확인 (무작위 이미지 열어보기)
ls /mnt/minio/immich/library/*/2024/01/*.jpg | head -5
```

#### 2. Immich 서비스 확인

```bash
# Docker 컨테이너 상태
docker compose ps

# Immich 로그 확인 (에러 없는지)
docker compose logs immich-server | grep -i error
docker compose logs immich-server | tail -50

# Immich Web UI 접속
# 브라우저에서 http://<server-ip>:2283 접속
# 로그인 후 사진 목록 확인
```

#### 3. 메타데이터 확인

```bash
# PostgreSQL 데이터베이스 확인
docker compose exec immich-postgres psql -U postgres -d immich -c \
  "SELECT COUNT(*) FROM assets;"

# Redis 연결 확인
docker compose exec immich-redis redis-cli ping
# 출력: PONG
```

#### 4. 기능 테스트

- [ ] 사진/비디오 썸네일 정상 로드
- [ ] 사진 업로드 기능 정상 작동
- [ ] 검색 기능 정상 작동
- [ ] 앨범 생성/삭제 정상 작동
- [ ] 사진 다운로드 정상 작동

---

## 🔧 트러블슈팅

### 문제 1: Glacier 복원이 너무 오래 걸림

**증상**: 48시간이 지나도 복원이 완료되지 않음

**원인**: Bulk 복원 계층 사용 시 최대 48시간 소요

**해결**:

```bash
# Expedited 복원으로 재요청 (비용 높음, 1-5분 소요)
aws s3api restore-object \
  --bucket immich-archive-restic \
  --key <object-key> \
  --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Expedited"}}'
```

### 문제 2: Restic 저장소 손상 오류

**증상**: `restic check` 실패 또는 복원 중 에러

**원인**: S3 다운로드 중 파일 손상 또는 불완전한 다운로드

**해결**:

```bash
# S3에서 다시 다운로드 (강제 덮어쓰기)
mc mirror --overwrite aws/immich-archive-restic /mnt/exthdd02/restored-restic-repo

# 저장소 수리 시도
restic -r /mnt/exthdd02/restored-restic-repo \
  --insecure-no-password rebuild-index

restic -r /mnt/exthdd02/restored-restic-repo \
  --insecure-no-password check --read-data
```

### 문제 3: 복원된 파일 권한 문제

**증상**: Immich가 파일을 읽을 수 없음 (Permission denied)

**원인**: 복원된 파일의 소유자/권한이 잘못됨

**해결**:

```bash
# Immich가 사용하는 UID/GID로 변경 (보통 1000:1000)
sudo chown -R 1000:1000 /mnt/minio/immich

# 파일 권한 확인
ls -la /mnt/minio/immich/library/

# 필요시 권한 수정
find /mnt/minio/immich -type f -exec chmod 644 {} \;
find /mnt/minio/immich -type d -exec chmod 755 {} \;
```

### 문제 4: Docker 볼륨 마운트 실패

**증상**: Immich 컨테이너가 `/mnt/minio/immich`를 마운트하지 못함

**원인**: 디렉토리가 존재하지 않거나 권한 문제

**해결**:

```bash
# 디렉토리 존재 확인
ls -ld /mnt/minio/immich

# 없으면 생성
sudo mkdir -p /mnt/minio/immich
sudo chown -R 1000:1000 /mnt/minio/immich

# Docker compose 파일의 볼륨 설정 확인
grep -A 5 "volumes:" docker-compose.yml
```

### 문제 5: 일부 사진만 보이거나 썸네일 깨짐

**증상**: 복원 후 일부 사진이 누락되거나 썸네일이 표시되지 않음

**원인**:
- 불완전한 복원
- PostgreSQL 메타데이터와 파일 불일치

**해결**:

```bash
# Immich 라이브러리 재스캔
docker compose exec immich-server immich-admin library scan --recursive

# 또는 Web UI에서: 관리자 → 라이브러리 → 스캔 실행

# 썸네일 재생성
docker compose exec immich-server immich-admin jobs run thumbnail-generation
```

---

## 🧪 테스트 계획

### 정기 복원 테스트 (분기별 권장)

> **중요**: 백업은 복원할 수 있을 때만 의미가 있습니다. 정기적인 복원 테스트로 백업의 유효성을 검증하세요.

#### 테스트 1: 로컬 저장소 복원 테스트 (매 분기)

**목적**: 로컬 restic 저장소가 정상 작동하는지 확인

**절차**:

```bash
# 1. 테스트 복원 디렉토리 생성
mkdir -p /tmp/immich-restore-test

# 2. 최신 스냅샷의 일부 파일만 복원
restic -r /mnt/exthdd02/immich-archive-restic/restic \
  --insecure-no-password restore latest \
  --target /tmp/immich-restore-test \
  --include '/mnt/minio/immich/library/*/2024/01/*' \
  --max-files 100

# 3. 복원된 파일 확인
ls -lh /tmp/immich-restore-test/mnt/minio/immich/library/*/2024/01/ | head -10

# 4. 무작위 이미지 파일 열기 (손상 여부 확인)
# 예: eog, feh, 또는 다른 이미지 뷰어 사용

# 5. 정리
rm -rf /tmp/immich-restore-test
```

**성공 기준**:
- 복원 에러 없음
- 파일이 정상적으로 열림
- 복원 시간 10분 이내 (100개 파일 기준)

#### 테스트 2: S3 Glacier 복원 테스트 (매 반기)

**목적**: S3 Glacier 복원 프로세스 전체를 검증

**절차**:

```bash
# 1. 소량의 테스트 객체만 복원 (비용 절감)
# config 파일만 복원해서 저장소 접근 가능 여부 확인
aws s3api restore-object \
  --bucket immich-archive-restic \
  --key config \
  --restore-request '{"Days":1,"GlacierJobParameters":{"Tier":"Standard"}}'

# 2. 복원 완료 대기 (약 12시간)
aws s3api head-object \
  --bucket immich-archive-restic \
  --key config | jq '.Restore'

# 3. 복원된 파일 다운로드
mkdir -p /tmp/glacier-test
mc cp aws/immich-archive-restic/config /tmp/glacier-test/

# 4. Restic으로 읽기 시도 (저장소 유효성 확인)
# 전체 저장소 없이 config만으로는 제한적이지만, 파일 자체의 무결성은 확인 가능

# 5. 정리
rm -rf /tmp/glacier-test
```

**성공 기준**:
- Glacier 복원 요청 성공
- 12시간 이내 복원 완료
- 파일 다운로드 성공

#### 테스트 3: 전체 복원 시뮬레이션 (연 1회)

**목적**: 실제 재난 상황을 가정한 전체 복원 연습

**절차**:

1. **준비**: 별도의 테스트 서버 또는 Docker 네임스페이스 사용
2. **복원**: 절차 B 또는 C를 완전히 실행
3. **검증**: 복원된 Immich에서 실제 사진 확인
4. **문서화**: 소요 시간, 발생한 문제, 해결 방법 기록

**성공 기준**:
- 모든 단계 완료
- Immich 정상 작동
- 사진/비디오 정상 재생

---

## 📊 복원 시간 및 비용 예상

### 복원 소요 시간 (63GB 기준)

| 단계 | 로컬 저장소 | S3 Glacier (Standard) | S3 Glacier (Bulk) |
|------|------------|----------------------|-------------------|
| Glacier 복원 대기 | - | 12시간 | 48시간 |
| 데이터 다운로드 | - | 1-2시간 (100Mbps 기준) | 1-2시간 |
| Restic 추출 | 30분-1시간 | 30분-1시간 | 30분-1시간 |
| **총 소요 시간** | **1-2시간** | **14-15시간** | **50-51시간** |

### 복원 비용 (63GB 기준)

| 항목 | Standard 복원 | Bulk 복원 |
|------|--------------|-----------|
| 복원 요청 비용 | 63GB × $0.03/GB = **$1.89** | 63GB × $0.0025/GB = **$0.16** |
| 데이터 전송 비용 | 63GB × $0.126/GB = **$7.94** | 63GB × $0.126/GB = **$7.94** |
| **총 비용** | **$9.83** | **$8.10** |

> **참고**: 비용은 서울 리전(ap-northeast-2) 기준이며, 변동될 수 있습니다.

---

## 📚 참고 자료

### 공식 문서

- [Restic 복원 가이드](https://restic.readthedocs.io/en/stable/050_restore.html)
- [AWS S3 Glacier 복원](https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects.html)
- [AWS S3 Glacier 복원 방법 (한글 블로그)](https://goodahn.tistory.com/280)

### 내부 문서

- [immich-backup.notion.md](immich-backup.notion.md): 백업 전략 문서
- [restic-backup-immich.sh](restic-backup-immich.sh): 백업 스크립트
- [restic-sync-to-s3.sh](restic-sync-to-s3.sh): S3 동기화 스크립트

---

## 🔐 보안 고려사항

### 1. Restic 비밀번호 미사용 주의

현재 설정은 `--insecure-no-password`를 사용하므로 저장소 접근 시 암호가 필요 없습니다.

**위험**:
- 누구나 저장소에 접근하면 데이터 복원 가능
- S3 자격 증명만으로 모든 백업 데이터 접근 가능

**권장 사항**:
```bash
# 프로덕션 환경에서는 비밀번호 사용 권장
export RESTIC_PASSWORD="강력한_비밀번호"
restic -r /path/to/repo backup /data

# 복원 시
export RESTIC_PASSWORD="강력한_비밀번호"
restic -r /path/to/repo restore latest --target /restore
```

### 2. AWS 자격 증명 보호

```bash
# AWS 자격 증명 파일 권한 확인
chmod 600 ~/.aws/credentials

# mc 설정 파일 권한 확인
chmod 600 ~/.mc/config.json
```

### 3. 복원된 데이터 보안

```bash
# 복원 작업 완료 후 임시 파일 삭제
rm -rf /mnt/exthdd02/restored-immich
rm -rf /mnt/exthdd02/restored-restic-repo

# 테스트용 복원 데이터는 즉시 삭제
```

---

## ✅ 복원 준비 체크리스트

### 재난 발생 전 (사전 준비)

- [ ] 이 문서를 안전한 외부 위치에 백업 (예: 개인 클라우드, 이메일)
- [ ] AWS 자격 증명을 안전한 곳에 보관 (비밀번호 관리자 등)
- [ ] Restic 비밀번호 기록 (사용하는 경우)
- [ ] 분기별 복원 테스트 실시
- [ ] 백업 스크립트 정상 작동 확인 (로그 모니터링)

### 재난 발생 시 (복원 준비)

- [ ] 복원 시나리오 파악 (로컬 손실? 서버 손실?)
- [ ] 필요 도구 설치 (restic, mc, awscli)
- [ ] AWS 자격 증명 확인
- [ ] 복원 대상 스토리지 용량 확인 (최소 100GB 여유 필요)
- [ ] Glacier 복원 요청 (S3 사용 시, 48시간 전에 미리 요청)

---

## 📝 변경 이력

- **2025-12-27**: 초기 문서 작성
  - 4가지 복원 시나리오 정의
  - 로컬/S3/신규 서버 복원 절차 작성
  - 트러블슈팅 및 테스트 계획 추가
