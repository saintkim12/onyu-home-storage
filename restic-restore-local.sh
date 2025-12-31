#!/bin/bash
#
# Restic 로컬 저장소 복원 스크립트
#
# 사용법:
#   ./restic-restore-local.sh [snapshot-id]
#
# 예시:
#   ./restic-restore-local.sh latest          # 최신 스냅샷 복원
#   ./restic-restore-local.sh 4f3c2a1b        # 특정 스냅샷 복원
#   ./restic-restore-local.sh                 # 대화형 모드 (스냅샷 선택)
#

set -e

# 설정
RESTIC_REPO="/mnt/exthdd02/immich-archive-restic/restic"
RESTORE_TARGET="/mnt/exthdd02/restored-immich"
LOG_FILE="$HOME/.log/restic-restore-local.log"
LOG_SUMMARY="$HOME/.log/restic-restore-local-summary.log"

# 로그 디렉토리 생성
mkdir -p "$(dirname "$LOG_FILE")"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" "$LOG_SUMMARY"
}

log_detail() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "===== Restic Local Restore Start ====="

# Restic 설치 확인
if ! command -v restic &> /dev/null; then
    log "ERROR: restic is not installed. Please install it first."
    log "  sudo apt install restic"
    exit 1
fi

# 저장소 존재 확인
if [ ! -d "$RESTIC_REPO" ]; then
    log "ERROR: Restic repository not found at $RESTIC_REPO"
    log "If using S3 restore, run s3-to-local-download.sh first."
    exit 1
fi

# 저장소 무결성 확인
log_detail "Checking repository integrity..."
if ! restic -r "$RESTIC_REPO" --insecure-no-password check 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Repository integrity check failed."
    log "The repository may be corrupted. Try downloading from S3 again."
    exit 1
fi
log "Repository integrity check passed."

# 스냅샷 ID 파라미터 처리
SNAPSHOT_ID="$1"

if [ -z "$SNAPSHOT_ID" ]; then
    # 대화형 모드: 스냅샷 목록 표시
    log_detail "Available snapshots:"
    restic -r "$RESTIC_REPO" --insecure-no-password snapshots | tee -a "$LOG_FILE"

    echo ""
    read -p "Enter snapshot ID (or 'latest' for most recent): " SNAPSHOT_ID

    if [ -z "$SNAPSHOT_ID" ]; then
        SNAPSHOT_ID="latest"
    fi
fi

log "Selected snapshot: $SNAPSHOT_ID"

# 스냅샷 정보 확인
log_detail "Snapshot details:"
restic -r "$RESTIC_REPO" --insecure-no-password snapshots "$SNAPSHOT_ID" 2>&1 | tee -a "$LOG_FILE"

# 복원 대상 디렉토리 확인
if [ -d "$RESTORE_TARGET" ]; then
    log "WARNING: Restore target directory already exists: $RESTORE_TARGET"
    read -p "Do you want to remove it and continue? (yes/no): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        log "Restore cancelled by user."
        exit 0
    fi

    log_detail "Removing existing directory..."
    rm -rf "$RESTORE_TARGET"
fi

# 복원 대상 디렉토리 생성
mkdir -p "$RESTORE_TARGET"
log "Restore target: $RESTORE_TARGET"

# 복원 옵션 선택
echo ""
echo "Restore options:"
echo "1) Full restore (all files)"
echo "2) Partial restore (specific path)"
read -p "Select option (1 or 2, default: 1): " RESTORE_OPTION

START_TIME=$(date +%s)

if [ "$RESTORE_OPTION" = "2" ]; then
    # 부분 복원
    read -p "Enter path pattern to restore (e.g., /mnt/minio/immich/library/*/2024/01/*): " PATH_PATTERN

    if [ -z "$PATH_PATTERN" ]; then
        log "ERROR: Path pattern cannot be empty."
        exit 1
    fi

    log "Starting partial restore with pattern: $PATH_PATTERN"
    log_detail "This may take a while..."

    restic -r "$RESTIC_REPO" --insecure-no-password restore "$SNAPSHOT_ID" \
        --target "$RESTORE_TARGET" \
        --include "$PATH_PATTERN" 2>&1 | tee -a "$LOG_FILE"
else
    # 전체 복원
    log "Starting full restore..."
    log_detail "This may take a while (30min - 1hour for 63GB)..."

    restic -r "$RESTIC_REPO" --insecure-no-password restore "$SNAPSHOT_ID" \
        --target "$RESTORE_TARGET" 2>&1 | tee -a "$LOG_FILE"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

log "Restore completed successfully!"
log "Duration: ${MINUTES}m ${SECONDS}s"

# 복원된 데이터 정보
RESTORED_PATH="$RESTORE_TARGET/mnt/minio/immich"
if [ -d "$RESTORED_PATH" ]; then
    RESTORED_SIZE=$(du -sh "$RESTORED_PATH" | cut -f1)
    RESTORED_FILES=$(find "$RESTORED_PATH" -type f | wc -l)

    log "Restored data location: $RESTORED_PATH"
    log "Restored size: $RESTORED_SIZE"
    log "Restored files: $RESTORED_FILES"
else
    log "WARNING: Expected path not found: $RESTORED_PATH"
    log "Restored to: $RESTORE_TARGET"
fi

log "===== Restic Local Restore End ====="
log ""
log "Next steps:"
log "1. Verify restored data:"
log "   ls -lh $RESTORED_PATH"
log "2. Check file count and size"
log "3. If everything looks good, copy to Immich:"
log "   sudo systemctl stop docker  # or: cd /path/to/immich && docker compose down"
log "   sudo cp -a $RESTORED_PATH /mnt/minio/immich"
log "   sudo chown -R 1000:1000 /mnt/minio/immich"
log "   sudo systemctl start docker  # or: docker compose up -d"
