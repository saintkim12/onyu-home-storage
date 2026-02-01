# Immich 백업 전략 (Restic + AWS S3 Glacier Deep Archive)

> 💡 **목적**: Immich 데이터의 장기 보관 백업 (월 1회)
>
> **전략**: Restic 증분 백업 → AWS S3 Glacier Deep Archive
>
> **비용 최적화**: 객체 수 최소화 (수만 개 → 수백 개)

---

## 📊 현재 백업 플로우

```
Immich 원본 데이터 (62GB)
    ↓ restic backup (증분, 압축, dedupe)
Restic 로컬 저장소 (63GB) - /mnt/exthdd02/immich-archive-restic/restic
    ↓ mc mirror (월 1회)
AWS S3 Glacier Deep Archive
```

### 크론탭 스케줄 (매월 1일 새벽)

```
1:00 AM - Restic 백업 (11분 소요)
2:00 AM - S3 동기화 (최초 1시간 41분, 증분은 빠름)
4:00 AM - Docker 볼륨 백업
```

---

## 📜 변경 히스토리

### 1단계: 직접 백업 방식 (2024 ~ 2025-10)

**방법**: MinIO → S3 직접 동기화 (`mc mirror`)

- **장점**: 구조 단순, 설정 간편
- **문제점**:
    - 객체 수 폭탄 (25,950개 파일 → 25,950개 S3 객체)
    - S3 요청 비용 증가 우려
    - 증분 백업 불가 (전체 동기화만 가능)

### 2단계: Restic 도입 (2025-10-09)

**선택 이유**:

- ✅ 증분 백업 + 중복 제거
- ✅ 압축 및 암호화 기본 지원
- ✅ Pack 파일로 객체 수 최소화 (64MB 단위)
- ✅ MinIO 직접 연결 가능 (캐시 불필요)

**테스트 결과**:

| 날짜 | 작업 | 결과 |
| --- | --- | --- |
| 2025-10-10 | 초기 백업 | 50.0GB (779개 pack 파일) |
| 2025-11-01 | 증분 백업 | +2.9GB (424개 신규, 6개 변경) |
| 2025-12-27 | 증분 백업 | +2.6GB (246개 신규, 6개 변경) |

**비용 효과**:

- 객체 수: 25,950개 → 약 1,000개 (95% 감소)
- 저장 용량: 압축 및 중복 제거로 효율 증가

### 3단계: 완전 자동화 (2025-12-27)

**구현 내용**:

- ✅ 백업 스크립트 완성 (`restic-backup-immich.sh`)
- ✅ S3 동기화 스크립트 완성 (`restic-sync-to-s3.sh`)
- ✅ 크론탭 자동화 등록
- ✅ 로그 시스템 구축 (상세/요약 분리)

**실측 성능**:

- Restic 백업: **11분** (62GB → 2.6GB 증분)
- S3 최초 동기화: **1시간 41분** (63GB)
- S3 증분 동기화: 예상 훨씬 빠름 (다음 달 확인 예정)

**주요 트러블슈팅**:

- **문제**: S3 업로드 실패 (로그에는 성공 표시, 실제 파일 없음)
- **원인**: `sudo`로 실행 시 root가 restic 파일(권한 400) 읽기 불가
- **해결**: `sudo` 제거, 일반 사용자로 실행

---

## ⚙️ 운영 가이드

### 스크립트 설치

```bash
# 1. restic-backup-immich.sh 설치
sudo cp /path/to/onyu-home/storage/restic-backup-immich.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/restic-backup-immich.sh

# 2. restic-sync-to-s3.sh 설치
sudo cp /path/to/onyu-home/storage/restic-sync-to-s3.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/restic-sync-to-s3.sh
```

### 크론탭 설정

> ⚠️ **중요**: restic 파일 권한 문제로 인해 **sudo 없이** 실행해야 함!

```bash
crontab -e  # 일반 사용자 크론탭
```

```cron
# 매월 1일 새벽 1시: Restic으로 Immich 백업 (로컬) - 약 11분 소요
0 1 1 * * /usr/local/bin/restic-backup-immich.sh

# 매월 1일 새벽 2시: Restic 저장소를 S3 Glacier Deep Archive로 동기화
# 최초: 1시간 41분 소요, 증분: 훨씬 빠름
0 2 1 * * /usr/local/bin/restic-sync-to-s3.sh

# 매월 1일 새벽 4시: Docker 볼륨 백업 (2시간 여유)
0 4 1 * * /usr/local/bin/docker-volume-backup.sh
```

### 로그 확인

```bash
# Restic 백업 로그
tail -f ~/.log/restic-backup-immich.log              # 상세 로그
tail -f ~/.log/restic-backup-immich-summary.log      # 요약 로그 (결과만)

# S3 동기화 로그
tail -f ~/.log/restic-sync-to-s3.log                 # 상세 로그
tail -f ~/.log/restic-sync-to-s3-summary.log         # 요약 로그 (결과만)
```

**요약 로그 예시**:

```
[2025-12-27 02:00:00] ===== Restic to S3 Sync Start =====
[2025-12-27 02:00:00] --> Starting sync of restic repository to S3
[2025-12-27 03:41:00] --> S3 sync completed successfully
[2025-12-27 03:41:00] --> Repository size: 63G
[2025-12-27 03:41:00] ===== Restic to S3 Sync End =====
[2025-12-27 03:41:00] --> Total duration: 101m 0s
```

### 스냅샷 관리

```bash
# 스냅샷 목록 확인
restic -r /mnt/exthdd02/immich-archive-restic/restic --insecure-no-password snapshots

# 특정 스냅샷 삭제 (오래된 백업 정리)
restic -r /mnt/exthdd02/immich-archive-restic/restic --insecure-no-password forget <snapshot-id>

# 정책 기반 자동 삭제 (예: 최근 6개월만 유지)
restic -r /mnt/exthdd02/immich-archive-restic/restic --insecure-no-password forget --keep-monthly 6 --prune
```

---

## 🔧 복구 방법

### 1. S3에서 Restic 저장소 복원

```bash
# S3 → 로컬로 저장소 다운로드
mc mirror aws/immich-archive-restic /mnt/exthdd02/immich-archive-restic/restic
```

### 2. 스냅샷 확인

```bash
# 스냅샷 목록 확인
restic -r /mnt/exthdd02/immich-archive-restic/restic --insecure-no-password snapshots
```

### 3. 데이터 복원

```bash
# 최신 스냅샷 복원
restic -r /mnt/exthdd02/immich-archive-restic/restic --insecure-no-password restore latest --target /mnt/exthdd02/restored-immich

# 특정 스냅샷 복원
restic -r /mnt/exthdd02/immich-archive-restic/restic --insecure-no-password restore <snapshot-id> --target /mnt/exthdd02/restored-immich
```

**참고 링크**: [Glacier 복원 방법](https://goodahn.tistory.com/280)

---

## ⚠️ 핵심 주의사항

### 1. 파일 권한 문제

Restic 저장소 파일은 보안을 위해 **400 권한** (소유자만 읽기)으로 생성됩니다.

```bash
-r-------- 1 user user 155 Oct 10 08:57 /mnt/exthdd02/immich-archive-restic/restic/config
```

- ❌ **`sudo`로 실행**: root가 파일을 읽을 수 없어 업로드 실패
- ✅ **일반 사용자로 실행**: 파일 소유자가 읽을 수 있어 정상 작동

### 2. Crontab에서 "mc: command not found" 에러

Crontab 환경에서는 사용자 쉘의 PATH를 로드하지 않아서, `mc` 명령을 찾을 수 없습니다.

**원인**:
- 대화식 쉘에서는 `~/.bashrc`의 PATH가 로드됨
- Crontab은 제한된 기본 PATH만 사용 (보안 상의 이유)

**해결책**:
1. **스크립트에서 명령어를 전체 경로로 명시** (권장)
   ```bash
   MC="/usr/local/bin/mc"
   $MC mirror ...  # 사용 시
   ```

2. **스크립트 시작 부분에 umask 설정 추가** (새 파일 권한 자동 정확화)
   ```bash
   #!/bin/bash
   umask 0022
   ```

3. **저장소 권한 사전 수정** (기존 파일들)
   ```bash
   chmod -R u+rwX,g+rX,o+rX /mnt/exthdd02/immich-archive-restic/
   ```

**실제 해결 사례** (2026-02-01):
- restic-backup-immich.sh: umask 추가, 정상 작동 (7분 9초)
- restic-sync-to-s3.sh: MC 변수 적용 + umask 추가, 정상 작동 (9분 8초)

### 2. S3 Glacier Deep Archive 제약

| 항목 | 내용 |
| --- | --- |
| 저장 요금 | $0.0012/GB/월 (서울 리전) |
| 최소 저장 기간 | **180일** (조기 삭제 시에도 6개월 요금 부과) |
| 복원 소요 시간 | 최대 48시간 |
| 복원 비용 | 별도 과금 (용량 기반) |

### 3. mc mirror의 --storage-class 주의

- `mc cp`는 `--storage-class` 옵션 **미지원**
- `mc mirror`만 `--storage-class "DEEP_ARCHIVE"` 사용 가능

---

## 💰 비용 정보

### 예상 월 비용 (63GB 기준)

| 항목 | 비용 |
| --- | --- |
| 저장 요금 | 63GB × $0.0012 = **$0.076/월** |
| PUT 요청 (최초) | 약 1,000개 객체 × $0.05/1000 = $0.05 (1회성) |
| PUT 요청 (증분) | 증분 파일만 업로드 (매우 저렴) |

**연간 예상 비용**: 약 **$1 이하**

### 비용 절감 효과

| 방식 | 객체 수 | 월 예상 비용 |
| --- | --- | --- |
| 직접 백업 (기존) | 25,950개 | 높음 (작은 파일 페널티) |
| **Restic (현재)** | **~1,000개** | **낮음** (큰 pack 파일) |

---

## 📚 참고 자료

### 공식 문서

- [Restic 공식 문서](https://restic.readthedocs.io/)
- [AWS S3 Glacier Deep Archive 요금](https://aws.amazon.com/ko/s3/pricing/)
- [MinIO Client (mc) 가이드](https://min.io/docs/minio/linux/reference/minio-mc.html)

### 내부 문서

- `restic-backup-immich.sh`: Restic 백업 스크립트
- `restic-sync-to-s3.sh`: S3 동기화 스크립트
- `docker-volume-backup.sh`: Docker 볼륨 백업 스크립트

---

## 📌 확인 사항 (2026-02-01 완료)

- [x]  크론탭 정상 실행 확인
- [x]  증분 백업 소요 시간 측정 → **7분 9초** (만족스러움)
- [x]  S3 증분 동기화 소요 시간 측정 → **9분 8초** (만족스러움)
- [x]  로그 정상 기록 확인 → 정상
- [x]  스냅샷 개수 확인 → 1개 신규 생성 (현재 3개, 적절함)
- [ ]  AWS 청구서 확인 (예상 비용과 비교)
- [x]  Crontab 환경 PATH 문제 해결 → 완료 (MC 변수 + umask 설정)

---

## 🔄 히스토리 메모

### 2025-10-06: mc mirror 사용 중 혼란

- `mc cp`와 `mc mirror`의 `--storage-class` 옵션 차이로 혼란
- 복잡한 예외 규칙보다 비용 감당하기로 결정
- 결론: 전체 데이터를 원 스크립트로 동기화하는 방식 유지

### 2025-10-09: Restic 도입 결정

- 객체 수 문제 해결을 위해 Restic 선택
- Pack 파일 방식으로 S3 객체 수 최소화
- 초기 테스트 성공 (50GB → 779개 pack)

### 2025-11-01: 증분 백업 검증

- 증분 백업 정상 작동 확인 (+2.9GB)
- 변경된 파일만 효율적으로 저장

### 2025-12-27: 완전 자동화 달성

- 스크립트 완성 및 크론탭 등록
- 파일 권한 이슈 해결 (sudo 제거)
- 로그 시스템 구축 (상세/요약 분리)
- S3 최초 동기화 완료 (1시간 41분)

### 2026-02-01: Crontab 환경 PATH 문제 해결

**문제**:
- 지난달(2026-01-01) 백업 스크립트 실행 실패
- Crontab 환경에서 "mc: command not found" 에러 발생

**해결 과정**:
1. Crontab과 대화식 쉘의 PATH 환경 차이 파악
2. `restic-sync-to-s3.sh`: MC 명령어를 변수로 처리 (`MC="/usr/local/bin/mc"`)
3. 두 스크립트 모두에 `umask 0022` 추가 (새 파일 권한 자동 정확화)
4. 저장소 권한 사전 수정 (`chmod -R u+rwX,g+rX,o+rX`)

**검증 결과** (Crontab 환경 시뮬레이션):
- Restic 백업: ✅ 7분 9초 (성공)
- S3 동기화: ✅ 9분 8초 (성공)
- 새로운 스냅샷 1개 생성
- 로그 정상 기록
- Permission denied 에러 해결됨

**변경 파일**:
- `restic-backup-immich.sh`: umask 추가
- `restic-sync-to-s3.sh`: MC 변수 + umask 추가
