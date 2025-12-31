#!/bin/bash
#
# Glacier 복원 상태 모니터링 스크립트
#
# 사용법:
#   ./check-glacier-restore-status.sh
#
# 설명:
#   - S3 Glacier Deep Archive에서 복원 요청한 객체의 상태를 모니터링
#   - 1시간마다 상태 확인
#   - 복원 완료 시 알림 후 종료
#

set -e

# 설정
BUCKET_NAME="immich-archive-restic"
CHECK_INTERVAL=3600  # 1시간 (초 단위)
LOG_FILE="$HOME/.log/glacier-restore-status.log"

# 로그 디렉토리 생성
mkdir -p "$(dirname "$LOG_FILE")"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# AWS CLI 설치 확인
if ! command -v aws &> /dev/null; then
    log "ERROR: aws CLI is not installed. Please install it first."
    log "  sudo apt install awscli"
    log "  aws configure"
    exit 1
fi

# AWS 자격 증명 확인
if ! aws sts get-caller-identity &> /dev/null; then
    log "ERROR: AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

log "===== Glacier Restore Status Monitoring Started ====="
log "Bucket: $BUCKET_NAME"
log "Check interval: ${CHECK_INTERVAL}s ($(($CHECK_INTERVAL / 60)) minutes)"
log ""

# 복원 중인 객체 수 확인
log "Checking restoration status..."

while true; do
    # 버킷의 모든 객체 목록 가져오기
    OBJECT_KEYS=$(aws s3api list-objects-v2 \
        --bucket "$BUCKET_NAME" \
        --query 'Contents[].Key' \
        --output text 2>/dev/null)

    if [ -z "$OBJECT_KEYS" ]; then
        log "ERROR: No objects found in bucket or access denied."
        exit 1
    fi

    # 총 객체 수
    TOTAL_OBJECTS=$(echo "$OBJECT_KEYS" | wc -w)

    # 복원 상태 카운터
    RESTORE_IN_PROGRESS=0
    RESTORE_COMPLETED=0
    NOT_RESTORING=0

    # 샘플 객체 확인 (모든 객체 확인하면 시간이 오래 걸리므로 대표 객체만 확인)
    # config 파일로 대표 확인
    SAMPLE_KEY="config"

    RESTORE_STATUS=$(aws s3api head-object \
        --bucket "$BUCKET_NAME" \
        --key "$SAMPLE_KEY" \
        2>/dev/null | jq -r '.Restore // "not_started"')

    log "Sample object ($SAMPLE_KEY) restore status: $RESTORE_STATUS"

    # 복원 상태 파싱
    if [[ "$RESTORE_STATUS" == "not_started" ]]; then
        log "WARNING: Restore has not been initiated yet."
        log "Please run the restore request script first:"
        log "  ./glacier-restore-request.sh"
        exit 1
    elif [[ "$RESTORE_STATUS" == *"ongoing-request=\"true\""* ]]; then
        log "Restore in progress... (still waiting)"
        log "Next check in $(($CHECK_INTERVAL / 60)) minutes."
    elif [[ "$RESTORE_STATUS" == *"ongoing-request=\"false\""* ]]; then
        log "========================================"
        log "RESTORE COMPLETED!"
        log "========================================"
        log "Objects are now available for download."
        log "Expiry date: $(echo "$RESTORE_STATUS" | grep -oP 'expiry-date="\K[^"]*')"
        log ""
        log "Next step: Download the repository from S3"
        log "  ./s3-to-local-download.sh"
        exit 0
    else
        log "Unknown restore status: $RESTORE_STATUS"
    fi

    log ""
    sleep "$CHECK_INTERVAL"
done
