# Immich 복원 스크립트 사용 가이드

이 디렉토리에는 Immich 백업 데이터를 복원하기 위한 스크립트들이 포함되어 있습니다.

---

## 📁 스크립트 목록

### 1. 재난 복구 스크립트 (S3 Glacier 사용)

실제 재난 상황에서 사용하는 스크립트들입니다.

| 스크립트 | 용도 | 예상 소요 시간 |
|---------|------|--------------|
| [glacier-restore-request.sh](glacier-restore-request.sh) | S3 Glacier에서 복원 요청 | 5분 |
| [check-glacier-restore-status.sh](check-glacier-restore-status.sh) | Glacier 복원 상태 모니터링 | 12-48시간 대기 |
| [s3-to-local-download.sh](s3-to-local-download.sh) | S3에서 로컬로 다운로드 | 1-2시간 |

### 2. 로컬 복원 스크립트

로컬 restic 저장소가 정상인 경우 사용합니다.

| 스크립트 | 용도 | 예상 소요 시간 |
|---------|------|--------------|
| [restic-restore-local.sh](restic-restore-local.sh) | 로컬 저장소에서 데이터 복원 | 30분-1시간 |

### 3. 검증 및 테스트 스크립트

복원 데이터를 검증하거나 정기적인 테스트를 수행합니다.

| 스크립트 | 용도 | 실행 주기 |
|---------|------|----------|
| [verify-restore.sh](verify-restore.sh) | 복원된 데이터 무결성 검증 | 복원 후 필수 |
| [test-restore-quarterly.sh](test-restore-quarterly.sh) | 정기 백업 테스트 | 분기별 (3개월) |

---

## 🚀 빠른 시작 가이드

### 시나리오 A: 로컬 데이터만 손실 (서버는 정상)

**복원 시간**: 약 1-2시간

```bash
# 1. 로컬 저장소에서 복원
./restic-restore-local.sh latest

# 2. 복원 데이터 검증
./verify-restore.sh /mnt/exthdd02/restored-immich/mnt/minio/immich

# 3. Immich에 적용
sudo systemctl stop docker
sudo cp -a /mnt/exthdd02/restored-immich/mnt/minio/immich /mnt/minio/immich
sudo chown -R 1000:1000 /mnt/minio/immich
sudo systemctl start docker
```

### 시나리오 B: 로컬 저장소 손실 (외장 HDD 고장)

**복원 시간**: 48시간 + 2-3시간

```bash
# 1. Glacier 복원 요청 (Bulk: 48시간)
./glacier-restore-request.sh Bulk 7

# 2. 복원 완료 대기 (자동 모니터링)
./check-glacier-restore-status.sh

# 3. S3에서 로컬로 다운로드 (복원 완료 후)
./s3-to-local-download.sh /mnt/exthdd02/restored-restic-repo

# 4. 로컬 저장소에서 데이터 복원
# restic-restore-local.sh의 RESTIC_REPO를 수정하거나:
RESTIC_REPO=/mnt/exthdd02/restored-restic-repo
restic -r $RESTIC_REPO --insecure-no-password restore latest \
  --target /mnt/exthdd02/restored-immich

# 5. 검증 및 적용 (시나리오 A와 동일)
./verify-restore.sh /mnt/exthdd02/restored-immich/mnt/minio/immich
# ... (이하 동일)
```

### 시나리오 C: 긴급 복원 (빠르게 필요한 경우)

**복원 시간**: 3-5시간 + 2-3시간

```bash
# 1. Glacier 복원 요청 (Standard: 3-5시간, 비용 높음)
./glacier-restore-request.sh Standard 7

# 2. 이후 절차는 시나리오 B와 동일
```

---

## 📖 상세 사용법

### 1. glacier-restore-request.sh

S3 Glacier Deep Archive에서 복원을 요청합니다.

**사용법**:
```bash
./glacier-restore-request.sh [tier] [days]
```

**파라미터**:
- `tier`: 복원 계층 (Expedited/Standard/Bulk)
- `days`: 복원된 데이터 유지 기간 (1-30일)

**예시**:
```bash
# 대화형 모드 (권장)
./glacier-restore-request.sh

# Bulk 복원 (저렴, 48시간)
./glacier-restore-request.sh Bulk 7

# Standard 복원 (보통, 12시간)
./glacier-restore-request.sh Standard 7

# Expedited 복원 (비쌈, 1-5분, 용량 제한 있음)
./glacier-restore-request.sh Expedited 1
```

**복원 계층 비교**:

| 계층 | 소요 시간 | 비용 (63GB 기준) | 용도 |
|------|----------|-----------------|------|
| Bulk | 5-12시간 | $0.16 + $7.94 = $8.10 | 계획된 복원 (권장) |
| Standard | 3-5시간 | $1.89 + $7.94 = $9.83 | 긴급 복원 |
| Expedited | 1-5분 | 매우 비쌈 + 용량 제한 | 극도 긴급 (비권장) |

---

### 2. check-glacier-restore-status.sh

Glacier 복원 진행 상태를 모니터링합니다.

**사용법**:
```bash
./check-glacier-restore-status.sh
```

**동작**:
- 1시간마다 복원 상태 확인
- 복원 완료 시 자동으로 알림 후 종료
- 로그: `~/.log/glacier-restore-status.log`

**예상 출력**:
```
[2025-12-27 10:00:00] ===== Glacier Restore Status Monitoring Started =====
[2025-12-27 10:00:00] Bucket: immich-archive-restic
[2025-12-27 10:00:00] Sample object (config) restore status: ongoing-request="true"
[2025-12-27 10:00:00] Restore in progress... (still waiting)
[2025-12-27 10:00:00] Next check in 60 minutes.
...
[2025-12-28 06:00:00] ========================================
[2025-12-28 06:00:00] RESTORE COMPLETED!
[2025-12-28 06:00:00] ========================================
```

---

### 3. s3-to-local-download.sh

S3에서 restic 저장소를 로컬로 다운로드합니다.

**사용법**:
```bash
./s3-to-local-download.sh [target-directory]
```

**파라미터**:
- `target-directory`: 다운로드 대상 경로 (기본값: `/mnt/exthdd02/restored-restic-repo`)

**예시**:
```bash
# 기본 위치에 다운로드
./s3-to-local-download.sh

# 특정 위치에 다운로드
./s3-to-local-download.sh /mnt/backup/restic-repo
```

**주의사항**:
- 디스크 공간 최소 100GB 필요
- 다운로드 시간: 1-2시간 (인터넷 속도에 따라 다름)
- Glacier 복원 완료 후에만 사용 가능

---

### 4. restic-restore-local.sh

로컬 restic 저장소에서 데이터를 복원합니다.

**사용법**:
```bash
./restic-restore-local.sh [snapshot-id]
```

**파라미터**:
- `snapshot-id`: 복원할 스냅샷 ID 또는 `latest` (기본값: 대화형 선택)

**예시**:
```bash
# 대화형 모드 (스냅샷 선택)
./restic-restore-local.sh

# 최신 스냅샷 복원
./restic-restore-local.sh latest

# 특정 스냅샷 복원
./restic-restore-local.sh 4f3c2a1b
```

**복원 옵션**:
1. **전체 복원**: 모든 파일 복원 (기본값)
2. **부분 복원**: 특정 경로만 복원 (예: `/mnt/minio/immich/library/*/2024/01/*`)

**로그**:
- 상세 로그: `~/.log/restic-restore-local.log`
- 요약 로그: `~/.log/restic-restore-local-summary.log`

---

### 5. verify-restore.sh

복원된 데이터의 무결성을 검증합니다.

**사용법**:
```bash
./verify-restore.sh <restored-path> [original-path]
```

**파라미터**:
- `restored-path`: 복원된 데이터 경로 (필수)
- `original-path`: 원본 데이터 경로 (선택, 비교용)

**예시**:
```bash
# 복원된 데이터만 검증
./verify-restore.sh /mnt/exthdd02/restored-immich/mnt/minio/immich

# 원본과 비교하며 검증
./verify-restore.sh /mnt/exthdd02/restored-immich/mnt/minio/immich /mnt/minio/immich
```

**검증 항목**:
1. 기본 통계 (파일 수, 용량)
2. 디렉토리 구조 (library, upload, thumbs 등)
3. 파일 무결성 (샘플링 10개)
4. 파일 권한
5. 파일 타입 분포
6. 타임스탬프

**예상 출력**:
```
[2025-12-27 10:00:00] ===== Step 1: Basic Statistics =====
[2025-12-27 10:00:00] Restored data:
[2025-12-27 10:00:00]   Total size: 62G
[2025-12-27 10:00:00]   Files: 25950
[2025-12-27 10:00:00]   Directories: 1234

...

[2025-12-27 10:01:00] ===== Verification Summary =====
[2025-12-27 10:01:00] ✓ VERIFICATION PASSED
[2025-12-27 10:01:00] The restored data appears to be complete and valid.
```

---

### 6. test-restore-quarterly.sh

정기적인 백업 테스트를 수행합니다.

**사용법**:
```bash
./test-restore-quarterly.sh
```

**테스트 항목**:
1. 저장소 무결성 확인
2. 스냅샷 목록 조회
3. 부분 복원 테스트 (샘플 100개 파일)
4. 파일 무결성 확인
5. 복원 성능 측정

**권장 실행 주기**: 분기별 (3개월마다)

**Crontab 예시**:
```bash
# 매 분기 첫째 날 새벽 5시
0 5 1 1,4,7,10 * /home/beancodebox/workspace/onyu-home/storage/test-restore-quarterly.sh
```

**로그**:
- 상세 로그: `~/.log/test-restore-quarterly.log`
- 테스트 리포트: `~/.log/test-restore-quarterly-report-YYYYMMDD.txt`

**예상 출력**:
```
=========================================
  Quarterly Restore Test
  Date: 2025-12-27 05:00:00
=========================================

===== Test 1: Repository Integrity Check =====
✓ PASSED: Repository integrity check (45s)

===== Test 2: Snapshot List =====
✓ PASSED: Retrieved snapshot list (3 snapshots found)

===== Test 3: Partial Restore Test =====
✓ PASSED: Restored 87 files (120s)

===== Test 4: File Integrity Check =====
✓ PASSED: All 10 sampled files are valid

===== Test 5: Restore Performance =====
✓ PASSED: Restore performance is acceptable (< 10min for sample)

=========================================
  Test Summary
=========================================
Tests passed: 5
Tests failed: 0
Total tests: 5

✓✓✓ ALL TESTS PASSED ✓✓✓
```

---

## 🔧 설치 및 설정

### 스크립트 설치 (선택적)

시스템 전역에서 사용하려면:

```bash
# 스크립트를 /usr/local/bin에 복사
sudo cp *.sh /usr/local/bin/

# 실행 권한 부여
sudo chmod +x /usr/local/bin/*.sh

# 이제 어디서든 실행 가능
glacier-restore-request.sh
restic-restore-local.sh
```

### 필수 도구 설치

```bash
# Restic 설치
sudo apt install restic

# AWS CLI 설치
sudo apt install awscli
aws configure  # Access Key, Secret Key 입력

# MinIO Client 설치
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# mc alias 설정
mc alias set aws https://s3.amazonaws.com <ACCESS_KEY> <SECRET_KEY>
```

---

## 📋 체크리스트

### 재난 발생 전 (사전 준비)

- [ ] 모든 스크립트 실행 권한 확인 (`chmod +x *.sh`)
- [ ] AWS 자격 증명 설정 (`aws configure`)
- [ ] mc alias 설정 (`mc alias set aws ...`)
- [ ] 분기별 테스트 실행 (`./test-restore-quarterly.sh`)
- [ ] 복원 가이드 문서 백업 (외부 저장소에 보관)

### 재난 발생 시 (복원 준비)

- [ ] 복원 시나리오 파악 (로컬 손실? 서버 손실?)
- [ ] 필요 도구 설치 확인 (restic, mc, awscli)
- [ ] 디스크 공간 확인 (최소 100GB 필요)
- [ ] Glacier 복원 요청 (S3 사용 시)
- [ ] 복원 완료 대기 (12-48시간)

### 복원 완료 후

- [ ] 복원 데이터 검증 (`./verify-restore.sh`)
- [ ] 샘플 파일 확인 (이미지 열어보기)
- [ ] 파일 권한 수정 (`sudo chown -R 1000:1000 /mnt/minio/immich`)
- [ ] Immich 재시작
- [ ] Web UI 접속 및 기능 테스트

---

## 📚 참고 문서

- [immich-restore-guide.md](immich-restore-guide.md): 상세 복원 가이드
- [immich-backup.notion.md](immich-backup.notion.md): 백업 전략 문서
- [Restic 공식 문서](https://restic.readthedocs.io/)
- [AWS S3 Glacier 복원 가이드](https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects.html)

---

## 🐛 트러블슈팅

### 문제: "aws: command not found"

**해결**:
```bash
sudo apt install awscli
aws configure
```

### 문제: "mc: command not found"

**해결**:
```bash
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/
```

### 문제: "Glacier restore is still in progress"

**해결**:
- Bulk 복원: 최대 48시간 대기
- Standard 복원: 최대 12시간 대기
- `./check-glacier-restore-status.sh`로 상태 모니터링

### 문제: "Repository integrity check failed"

**해결**:
```bash
# S3에서 재다운로드
./s3-to-local-download.sh /mnt/exthdd02/new-repo

# 저장소 수리 시도
restic -r /path/to/repo --insecure-no-password rebuild-index
restic -r /path/to/repo --insecure-no-password check --read-data
```

### 문제: "Permission denied" (복원 후 Immich 접근 불가)

**해결**:
```bash
sudo chown -R 1000:1000 /mnt/minio/immich
find /mnt/minio/immich -type f -exec chmod 644 {} \;
find /mnt/minio/immich -type d -exec chmod 755 {} \;
```

---

## 📞 지원

문제가 발생하거나 질문이 있으면:

1. 로그 파일 확인: `~/.log/*.log`
2. [immich-restore-guide.md](immich-restore-guide.md)의 트러블슈팅 섹션 참조
3. GitHub Issues: [onyu-home repository](https://github.com/yourusername/onyu-home/issues)

---

**작성일**: 2025-12-27
**버전**: 1.0.0
