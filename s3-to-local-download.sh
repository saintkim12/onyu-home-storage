#!/bin/bash
#
# S3에서 Restic 저장소를 로컬로 다운로드하는 스크립트
#
# 사용법:
#   ./s3-to-local-download.sh [target-directory]
#
# 예시:
#   ./s3-to-local-download.sh /mnt/exthdd02/restored-restic-repo
#   ./s3-to-local-download.sh                    # 기본 위치 사용
#

set -e

# 설정
BUCKET_NAME="immich-archive-restic"
DEFAULT_TARGET="/mnt/exthdd02/restored-restic-repo"
LOG_FILE="$HOME/.log/s3-to-local-download.log"
LOG_SUMMARY="$HOME/.log/s3-to-local-download-summary.log"

# 로그 디렉토리 생성
mkdir -p "$(dirname "$LOG_FILE")"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" "$LOG_SUMMARY"
}

log_detail() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "===== S3 to Local Download Start ====="

# MinIO Client 설치 확인
if ! command -v mc &> /dev/null; then
    log "ERROR: mc (MinIO Client) is not installed. Please install it first."
    log "  wget https://dl.min.io/client/mc/release/linux-amd64/mc"
    log "  chmod +x mc && sudo mv mc /usr/local/bin/"
    exit 1
fi

# mc alias 확인
if ! mc alias list aws &> /dev/null; then
    log "ERROR: AWS S3 alias not configured in mc."
    log "Please configure it first:"
    log "  mc alias set aws https://s3.amazonaws.com <ACCESS_KEY> <SECRET_KEY>"
    exit 1
fi

# 다운로드 대상 디렉토리 결정
TARGET_DIR="${1:-$DEFAULT_TARGET}"

log "Download configuration:"
log "  Source: s3://$BUCKET_NAME"
log "  Target: $TARGET_DIR"

# 대상 디렉토리 확인
if [ -d "$TARGET_DIR" ]; then
    log "WARNING: Target directory already exists: $TARGET_DIR"

    # 기존 파일 수 확인
    EXISTING_FILES=$(find "$TARGET_DIR" -type f 2>/dev/null | wc -l)
    log "Existing files: $EXISTING_FILES"

    read -p "Do you want to remove it and re-download? (yes/no): " CONFIRM

    if [ "$CONFIRM" = "yes" ]; then
        log_detail "Removing existing directory..."
        rm -rf "$TARGET_DIR"
    else
        log "Continuing with existing directory (will sync changes only)."
    fi
fi

# 대상 디렉토리 생성
mkdir -p "$TARGET_DIR"

# S3 버킷 접근 확인
log_detail "Checking S3 bucket access..."
if ! mc ls "aws/$BUCKET_NAME" &> /dev/null; then
    log "ERROR: Cannot access S3 bucket: $BUCKET_NAME"
    log "Please check:"
    log "  1. Bucket name is correct"
    log "  2. AWS credentials have access to this bucket"
    log "  3. Glacier objects have been restored"
    exit 1
fi

log "S3 bucket access confirmed."

# S3 객체 복원 상태 확인 (샘플)
log_detail "Checking if Glacier restore is complete..."
RESTORE_STATUS=$(mc stat "aws/$BUCKET_NAME/config" 2>/dev/null | grep -i "x-amz-restore" || echo "")

if [ -z "$RESTORE_STATUS" ]; then
    log "WARNING: Cannot verify Glacier restore status."
    log "If objects are still in Glacier (not restored), download will fail."
    read -p "Do you want to continue anyway? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log "Download cancelled by user."
        log "Please run glacier-restore-request.sh first and wait for completion."
        exit 0
    fi
elif echo "$RESTORE_STATUS" | grep -q "ongoing-request=\"true\""; then
    log "ERROR: Glacier restore is still in progress."
    log "Please wait for restore to complete, then try again."
    log "Monitor status: ./check-glacier-restore-status.sh"
    exit 1
else
    log "Glacier restore confirmed complete. Proceeding with download."
fi

# 디스크 공간 확인
log_detail "Checking available disk space..."
AVAILABLE_SPACE_KB=$(df "$TARGET_DIR" | tail -1 | awk '{print $4}')
AVAILABLE_SPACE_GB=$((AVAILABLE_SPACE_KB / 1024 / 1024))

log "Available disk space: ${AVAILABLE_SPACE_GB}GB"

if [ $AVAILABLE_SPACE_GB -lt 70 ]; then
    log "WARNING: Low disk space! Repository size is ~63GB."
    log "Available space: ${AVAILABLE_SPACE_GB}GB"
    read -p "Do you want to continue? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log "Download cancelled due to low disk space."
        exit 1
    fi
fi

# 다운로드 시작
START_TIME=$(date +%s)

log "Starting download from S3..."
log_detail "This may take 1-2 hours depending on your internet speed."
log_detail "Progress will be displayed below:"
log ""

# mc mirror 실행
if mc mirror "aws/$BUCKET_NAME" "$TARGET_DIR" 2>&1 | tee -a "$LOG_FILE"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))

    log ""
    log "Download completed successfully!"
    log "Duration: ${MINUTES}m ${SECONDS}s"
else
    log "ERROR: Download failed."
    log "Please check the log for details: $LOG_FILE"
    exit 1
fi

# 다운로드 결과 확인
log_detail "Verifying downloaded data..."

DOWNLOADED_SIZE=$(du -sh "$TARGET_DIR" | cut -f1)
DOWNLOADED_FILES=$(find "$TARGET_DIR" -type f | wc -l)

log "Downloaded repository:"
log "  Location: $TARGET_DIR"
log "  Size: $DOWNLOADED_SIZE"
log "  Files: $DOWNLOADED_FILES"

# Restic 저장소 무결성 확인
log_detail "Checking restic repository integrity..."

if command -v restic &> /dev/null; then
    if restic -r "$TARGET_DIR" --insecure-no-password check 2>&1 | tee -a "$LOG_FILE"; then
        log "Repository integrity check PASSED!"
    else
        log "WARNING: Repository integrity check FAILED!"
        log "The repository may be corrupted or incomplete."
        log "You may need to re-download from S3."
    fi
else
    log "WARNING: restic not installed, skipping integrity check."
    log "Install restic to verify repository: sudo apt install restic"
fi

log "===== S3 to Local Download End ====="
log ""
log "Next steps:"
log "1. Verify repository integrity:"
log "   restic -r $TARGET_DIR --insecure-no-password check"
log ""
log "2. List available snapshots:"
log "   restic -r $TARGET_DIR --insecure-no-password snapshots"
log ""
log "3. Restore data:"
log "   ./restic-restore-local.sh"
log "   (Make sure to update RESTIC_REPO in the script to: $TARGET_DIR)"
