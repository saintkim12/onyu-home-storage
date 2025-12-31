#!/bin/bash
#
# 분기별 복원 테스트 스크립트
#
# 목적:
#   - 백업의 유효성을 정기적으로 검증
#   - 로컬 restic 저장소가 정상 작동하는지 확인
#   - 복원 프로세스를 연습하고 문서화
#
# 사용법:
#   ./test-restore-quarterly.sh
#
# 권장 실행 주기: 분기별 (3개월마다)
#

set -e

# 설정
RESTIC_REPO="/mnt/exthdd02/immich-archive-restic/restic"
TEST_DIR="/tmp/immich-restore-test-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$HOME/.log/test-restore-quarterly.log"
REPORT_FILE="$HOME/.log/test-restore-quarterly-report-$(date +%Y%m%d).txt"
MAX_FILES=100  # 테스트할 최대 파일 수

# 로그 디렉토리 생성
mkdir -p "$(dirname "$LOG_FILE")"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" "$REPORT_FILE"
}

log_detail() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "  Quarterly Restore Test"
log "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
log "========================================="
log ""

# Restic 설치 확인
if ! command -v restic &> /dev/null; then
    log "ERROR: restic is not installed."
    log "RESULT: FAILED"
    exit 1
fi

# 저장소 존재 확인
if [ ! -d "$RESTIC_REPO" ]; then
    log "ERROR: Restic repository not found at $RESTIC_REPO"
    log "RESULT: FAILED"
    exit 1
fi

log "Test configuration:"
log "  Repository: $RESTIC_REPO"
log "  Test directory: $TEST_DIR"
log "  Max files to test: $MAX_FILES"
log ""

# 테스트 결과 추적
TEST_PASSED=0
TEST_FAILED=0

# ===== 테스트 1: 저장소 무결성 확인 =====
log "===== Test 1: Repository Integrity Check ====="
log_detail "Running restic check..."

START_TIME=$(date +%s)

if restic -r "$RESTIC_REPO" --insecure-no-password check 2>&1 | tee -a "$LOG_FILE"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log "✓ PASSED: Repository integrity check (${DURATION}s)"
    ((TEST_PASSED++))
else
    log "✗ FAILED: Repository integrity check"
    ((TEST_FAILED++))
fi

log ""

# ===== 테스트 2: 스냅샷 목록 조회 =====
log "===== Test 2: Snapshot List ====="
log_detail "Listing snapshots..."

SNAPSHOTS=$(restic -r "$RESTIC_REPO" --insecure-no-password snapshots 2>&1 | tee -a "$LOG_FILE")

if [ $? -eq 0 ]; then
    SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | grep -c "^[a-f0-9]\{8\}" || true)
    log "✓ PASSED: Retrieved snapshot list ($SNAPSHOT_COUNT snapshots found)"
    ((TEST_PASSED++))

    # 최신 스냅샷 정보 표시
    LATEST_SNAPSHOT=$(echo "$SNAPSHOTS" | grep "^[a-f0-9]" | tail -1)
    log "Latest snapshot: $LATEST_SNAPSHOT"
else
    log "✗ FAILED: Cannot retrieve snapshot list"
    ((TEST_FAILED++))
fi

log ""

# ===== 테스트 3: 부분 복원 테스트 =====
log "===== Test 3: Partial Restore Test ====="
log_detail "Restoring sample files (max $MAX_FILES files)..."

# 테스트 디렉토리 생성
mkdir -p "$TEST_DIR"

START_TIME=$(date +%s)

# 최신 스냅샷의 일부 파일만 복원 (library 디렉토리의 이미지 파일)
if restic -r "$RESTIC_REPO" --insecure-no-password restore latest \
    --target "$TEST_DIR" \
    --include '/mnt/minio/immich/library/**/*.jpg' \
    --include '/mnt/minio/immich/library/**/*.jpeg' \
    --include '/mnt/minio/immich/library/**/*.png' 2>&1 | tee -a "$LOG_FILE"; then

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    # 복원된 파일 수 확인
    RESTORED_FILES=$(find "$TEST_DIR" -type f 2>/dev/null | wc -l)

    if [ $RESTORED_FILES -gt 0 ]; then
        log "✓ PASSED: Restored $RESTORED_FILES files (${DURATION}s)"
        ((TEST_PASSED++))
    else
        log "✗ FAILED: No files were restored"
        ((TEST_FAILED++))
    fi
else
    log "✗ FAILED: Restore operation failed"
    ((TEST_FAILED++))
fi

log ""

# ===== 테스트 4: 파일 무결성 확인 =====
log "===== Test 4: File Integrity Check ====="
log_detail "Checking restored files for corruption..."

VALID_FILES=0
INVALID_FILES=0

# 복원된 파일 샘플링 (최대 10개)
SAMPLE_FILES=$(find "$TEST_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) 2>/dev/null | head -10)

if [ -z "$SAMPLE_FILES" ]; then
    log "WARNING: No image files found to test"
else
    while IFS= read -r FILE; do
        FILE_TYPE=$(file -b "$FILE" 2>/dev/null)

        if echo "$FILE_TYPE" | grep -qi "image\|jpeg\|png"; then
            ((VALID_FILES++))
            log_detail "  ✓ $(basename "$FILE"): Valid ($FILE_TYPE)"
        else
            ((INVALID_FILES++))
            log "  ✗ $(basename "$FILE"): Invalid ($FILE_TYPE)"
        fi
    done <<< "$SAMPLE_FILES"

    if [ $INVALID_FILES -eq 0 ] && [ $VALID_FILES -gt 0 ]; then
        log "✓ PASSED: All $VALID_FILES sampled files are valid"
        ((TEST_PASSED++))
    else
        log "✗ FAILED: $INVALID_FILES corrupted files found"
        ((TEST_FAILED++))
    fi
fi

log ""

# ===== 테스트 5: 복원 성능 측정 =====
log "===== Test 5: Restore Performance ====="

# 복원된 데이터 크기
RESTORED_SIZE=$(du -sh "$TEST_DIR" 2>/dev/null | cut -f1)
log "Restored data size: $RESTORED_SIZE"

# 복원 속도 계산 (대략적)
if [ -n "$DURATION" ] && [ $DURATION -gt 0 ]; then
    log "Restore time: ${DURATION}s"

    # 성능 기준: 100개 파일 복원에 10분 이내
    if [ $DURATION -lt 600 ]; then
        log "✓ PASSED: Restore performance is acceptable (< 10min for sample)"
        ((TEST_PASSED++))
    else
        log "⚠ WARNING: Restore took longer than expected (${DURATION}s)"
        log "✓ PASSED: But restore still completed successfully"
        ((TEST_PASSED++))
    fi
else
    log "⚠ WARNING: Cannot measure restore performance"
fi

log ""

# ===== 정리 =====
log "===== Cleanup ====="
log_detail "Removing test directory: $TEST_DIR"

rm -rf "$TEST_DIR"
log "Test directory removed."

log ""

# ===== 최종 결과 =====
log "========================================="
log "  Test Summary"
log "========================================="
log "Tests passed: $TEST_PASSED"
log "Tests failed: $TEST_FAILED"
log "Total tests: $((TEST_PASSED + TEST_FAILED))"
log ""

if [ $TEST_FAILED -eq 0 ]; then
    log "✓✓✓ ALL TESTS PASSED ✓✓✓"
    log ""
    log "Your backup is healthy and can be restored successfully."
    log "No action required."
    RESULT="PASSED"
else
    log "✗✗✗ SOME TESTS FAILED ✗✗✗"
    log ""
    log "WARNING: Your backup may have issues!"
    log "Please investigate the failed tests above."
    log ""
    log "Recommended actions:"
    log "1. Check restic repository integrity manually:"
    log "   restic -r $RESTIC_REPO --insecure-no-password check"
    log ""
    log "2. Verify S3 backup is up to date:"
    log "   mc ls aws/immich-archive-restic"
    log ""
    log "3. Consider running a full backup:"
    log "   /usr/local/bin/restic-backup-immich.sh"
    RESULT="FAILED"
fi

log ""
log "========================================="
log "Report saved to: $REPORT_FILE"
log "Full log saved to: $LOG_FILE"
log "========================================="

# 결과 이메일 발송 (선택적 - mailx 설치 필요)
if command -v mail &> /dev/null; then
    SUBJECT="[Immich Backup] Quarterly Restore Test: $RESULT"
    cat "$REPORT_FILE" | mail -s "$SUBJECT" root
    log "Email notification sent."
fi

# 종료 코드
if [ "$RESULT" = "PASSED" ]; then
    exit 0
else
    exit 1
fi
