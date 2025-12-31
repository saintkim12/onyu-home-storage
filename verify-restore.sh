#!/bin/bash
#
# 복원된 Immich 데이터 검증 스크립트
#
# 사용법:
#   ./verify-restore.sh <restored-path> [original-path]
#
# 예시:
#   ./verify-restore.sh /mnt/exthdd02/restored-immich/mnt/minio/immich
#   ./verify-restore.sh /mnt/exthdd02/restored-immich/mnt/minio/immich /mnt/minio/immich
#

set -e

# 로그 설정
LOG_FILE="$HOME/.log/verify-restore.log"
mkdir -p "$(dirname "$LOG_FILE")"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "===== Restore Verification Start ====="

# 복원된 경로 파라미터
RESTORED_PATH="$1"
ORIGINAL_PATH="$2"

if [ -z "$RESTORED_PATH" ]; then
    echo "Usage: $0 <restored-path> [original-path]"
    echo ""
    echo "Example:"
    echo "  $0 /mnt/exthdd02/restored-immich/mnt/minio/immich"
    echo "  $0 /mnt/exthdd02/restored-immich/mnt/minio/immich /mnt/minio/immich"
    exit 1
fi

# 복원된 경로 존재 확인
if [ ! -d "$RESTORED_PATH" ]; then
    log "ERROR: Restored path does not exist: $RESTORED_PATH"
    exit 1
fi

log "Restored path: $RESTORED_PATH"
if [ -n "$ORIGINAL_PATH" ]; then
    log "Original path: $ORIGINAL_PATH (for comparison)"
fi

log ""
log "===== Step 1: Basic Statistics ====="

# 복원된 데이터 통계
log "Calculating restored data statistics..."
RESTORED_SIZE=$(du -sh "$RESTORED_PATH" 2>/dev/null | cut -f1)
RESTORED_FILES=$(find "$RESTORED_PATH" -type f 2>/dev/null | wc -l)
RESTORED_DIRS=$(find "$RESTORED_PATH" -type d 2>/dev/null | wc -l)

log "Restored data:"
log "  Total size: $RESTORED_SIZE"
log "  Files: $RESTORED_FILES"
log "  Directories: $RESTORED_DIRS"

# 원본 데이터와 비교 (선택적)
if [ -n "$ORIGINAL_PATH" ] && [ -d "$ORIGINAL_PATH" ]; then
    log ""
    log "Comparing with original data..."

    ORIGINAL_SIZE=$(du -sh "$ORIGINAL_PATH" 2>/dev/null | cut -f1)
    ORIGINAL_FILES=$(find "$ORIGINAL_PATH" -type f 2>/dev/null | wc -l)
    ORIGINAL_DIRS=$(find "$ORIGINAL_PATH" -type d 2>/dev/null | wc -l)

    log "Original data:"
    log "  Total size: $ORIGINAL_SIZE"
    log "  Files: $ORIGINAL_FILES"
    log "  Directories: $ORIGINAL_DIRS"

    log ""
    log "Comparison:"
    FILE_DIFF=$((ORIGINAL_FILES - RESTORED_FILES))
    if [ $FILE_DIFF -eq 0 ]; then
        log "  File count: MATCH (both have $RESTORED_FILES files)"
    elif [ $FILE_DIFF -gt 0 ]; then
        log "  File count: MISSING $FILE_DIFF files in restored data"
    else
        log "  File count: $((FILE_DIFF * -1)) EXTRA files in restored data"
    fi
fi

log ""
log "===== Step 2: Directory Structure ====="

log "Checking expected Immich directory structure..."

EXPECTED_DIRS=(
    "library"
    "upload"
    "thumbs"
    "encoded-video"
    "profile"
)

MISSING_DIRS=0
for DIR in "${EXPECTED_DIRS[@]}"; do
    if [ -d "$RESTORED_PATH/$DIR" ]; then
        log "  ✓ $DIR/ exists"
    else
        log "  ✗ $DIR/ MISSING"
        ((MISSING_DIRS++))
    fi
done

if [ $MISSING_DIRS -eq 0 ]; then
    log "Directory structure: OK"
else
    log "WARNING: $MISSING_DIRS expected directories are missing!"
fi

log ""
log "===== Step 3: File Integrity Sampling ====="

log "Checking sample files for corruption..."

# 이미지 파일 샘플링 (무작위 10개)
IMAGE_FILES=$(find "$RESTORED_PATH" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) 2>/dev/null | shuf -n 10)

if [ -z "$IMAGE_FILES" ]; then
    log "WARNING: No image files found in restored data!"
else
    CHECKED_FILES=0
    VALID_FILES=0
    INVALID_FILES=0

    while IFS= read -r FILE; do
        ((CHECKED_FILES++))

        # file 명령어로 파일 타입 확인
        FILE_TYPE=$(file -b "$FILE" 2>/dev/null)

        if echo "$FILE_TYPE" | grep -qi "image\|jpeg\|png\|gif"; then
            ((VALID_FILES++))
            log "  ✓ $(basename "$FILE"): $FILE_TYPE"
        else
            ((INVALID_FILES++))
            log "  ✗ $(basename "$FILE"): INVALID ($FILE_TYPE)"
        fi
    done <<< "$IMAGE_FILES"

    log ""
    log "Sample file check results:"
    log "  Total checked: $CHECKED_FILES"
    log "  Valid: $VALID_FILES"
    log "  Invalid: $INVALID_FILES"

    if [ $INVALID_FILES -gt 0 ]; then
        log "WARNING: Some files may be corrupted!"
    else
        log "All sampled files appear valid."
    fi
fi

log ""
log "===== Step 4: File Permissions ====="

log "Checking file permissions..."

# 파일 권한 샘플 확인 (처음 5개 파일)
SAMPLE_FILES=$(find "$RESTORED_PATH" -type f 2>/dev/null | head -5)

if [ -n "$SAMPLE_FILES" ]; then
    log "Sample file permissions:"
    while IFS= read -r FILE; do
        PERMS=$(stat -c "%a %U:%G" "$FILE" 2>/dev/null)
        log "  $(basename "$FILE"): $PERMS"
    done <<< "$SAMPLE_FILES"

    # 권한 문제 확인
    UNREADABLE_FILES=$(find "$RESTORED_PATH" -type f ! -readable 2>/dev/null | wc -l)
    if [ $UNREADABLE_FILES -gt 0 ]; then
        log "WARNING: $UNREADABLE_FILES files are not readable by current user!"
        log "You may need to run: sudo chown -R 1000:1000 $RESTORED_PATH"
    else
        log "All sampled files are readable."
    fi
fi

log ""
log "===== Step 5: File Type Distribution ====="

log "Analyzing file types..."

# 확장자별 파일 개수 (상위 10개)
log "Top 10 file types:"
find "$RESTORED_PATH" -type f 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10 | while read COUNT EXT; do
    log "  $EXT: $COUNT files"
done

log ""
log "===== Step 6: Timestamp Check ====="

log "Checking file modification times..."

# 가장 오래된 파일
OLDEST_FILE=$(find "$RESTORED_PATH" -type f -printf '%T+ %p\n' 2>/dev/null | sort | head -1)
if [ -n "$OLDEST_FILE" ]; then
    log "Oldest file: $OLDEST_FILE"
fi

# 가장 최근 파일
NEWEST_FILE=$(find "$RESTORED_PATH" -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | head -1)
if [ -n "$NEWEST_FILE" ]; then
    log "Newest file: $NEWEST_FILE"
fi

log ""
log "===== Verification Summary ====="

# 검증 결과 요약
ISSUES_FOUND=0

if [ $MISSING_DIRS -gt 0 ]; then
    log "⚠ WARNING: Missing directories detected"
    ((ISSUES_FOUND++))
fi

if [ "${INVALID_FILES:-0}" -gt 0 ]; then
    log "⚠ WARNING: Corrupted files detected"
    ((ISSUES_FOUND++))
fi

if [ "${UNREADABLE_FILES:-0}" -gt 0 ]; then
    log "⚠ WARNING: Permission issues detected"
    ((ISSUES_FOUND++))
fi

if [ "${RESTORED_FILES:-0}" -eq 0 ]; then
    log "⚠ ERROR: No files found in restored data!"
    ((ISSUES_FOUND++))
fi

log ""
if [ $ISSUES_FOUND -eq 0 ]; then
    log "✓ VERIFICATION PASSED"
    log "The restored data appears to be complete and valid."
    log ""
    log "Next steps:"
    log "1. If this looks good, copy to Immich location:"
    log "   sudo systemctl stop docker"
    log "   sudo cp -a $RESTORED_PATH /mnt/minio/immich"
    log "   sudo chown -R 1000:1000 /mnt/minio/immich"
    log "   sudo systemctl start docker"
    log ""
    log "2. Or if using Docker Compose:"
    log "   cd /path/to/immich && docker compose down"
    log "   sudo cp -a $RESTORED_PATH /mnt/minio/immich"
    log "   sudo chown -R 1000:1000 /mnt/minio/immich"
    log "   docker compose up -d"
else
    log "✗ VERIFICATION FAILED"
    log "$ISSUES_FOUND issue(s) found in restored data."
    log "Please review the warnings above before using this data."
fi

log ""
log "===== Restore Verification End ====="
log "Full log saved to: $LOG_FILE"
