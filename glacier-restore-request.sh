#!/bin/bash
#
# S3 Glacier Deep Archive 복원 요청 스크립트
#
# 사용법:
#   ./glacier-restore-request.sh [tier] [days]
#
# 예시:
#   ./glacier-restore-request.sh Bulk 7          # Bulk 복원 (48시간, 저렴)
#   ./glacier-restore-request.sh Standard 7      # Standard 복원 (12시간)
#   ./glacier-restore-request.sh Expedited 1     # Expedited 복원 (1-5분, 비싸고 용량 제한 있음)
#   ./glacier-restore-request.sh                 # 대화형 모드
#

set -e

# 설정
BUCKET_NAME="immich-archive-restic"
LOG_FILE="$HOME/.log/glacier-restore-request.log"

# 로그 디렉토리 생성
mkdir -p "$(dirname "$LOG_FILE")"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "===== Glacier Restore Request Start ====="

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

# 파라미터 처리
TIER="$1"
DAYS="$2"

if [ -z "$TIER" ] || [ -z "$DAYS" ]; then
    # 대화형 모드
    echo ""
    echo "Glacier Restore Tiers:"
    echo "1) Expedited - 1-5 minutes (expensive, limited availability)"
    echo "   Cost: \$0.033/GB + \$10/1000 requests"
    echo "   Max size: 250MB per object"
    echo ""
    echo "2) Standard - 3-5 hours (recommended for urgent restore)"
    echo "   Cost: \$0.030/GB + \$0.05/1000 requests"
    echo ""
    echo "3) Bulk - 5-12 hours (cheapest, recommended for planned restore)"
    echo "   Cost: \$0.0025/GB + \$0.025/1000 requests"
    echo ""
    read -p "Select tier (1/2/3, default: 3): " TIER_CHOICE

    case "$TIER_CHOICE" in
        1) TIER="Expedited" ;;
        2) TIER="Standard" ;;
        3|"") TIER="Bulk" ;;
        *)
            log "ERROR: Invalid tier selection."
            exit 1
            ;;
    esac

    read -p "How many days to keep restored data available? (1-30, default: 7): " DAYS
    if [ -z "$DAYS" ]; then
        DAYS=7
    fi
fi

# 유효성 검사
if [[ ! "$TIER" =~ ^(Expedited|Standard|Bulk)$ ]]; then
    log "ERROR: Invalid tier. Must be: Expedited, Standard, or Bulk"
    exit 1
fi

if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || [ "$DAYS" -lt 1 ] || [ "$DAYS" -gt 30 ]; then
    log "ERROR: Days must be a number between 1 and 30"
    exit 1
fi

log "Restore configuration:"
log "  Bucket: $BUCKET_NAME"
log "  Tier: $TIER"
log "  Days: $DAYS"

# 예상 비용 계산 (63GB 기준)
REPO_SIZE_GB=63

case "$TIER" in
    Expedited)
        RESTORE_COST=$(echo "$REPO_SIZE_GB * 0.033" | bc)
        RESTORE_TIME="1-5 minutes"
        log "  WARNING: Expedited tier has 250MB per object limit!"
        log "  This may fail for large pack files."
        ;;
    Standard)
        RESTORE_COST=$(echo "$REPO_SIZE_GB * 0.030" | bc)
        RESTORE_TIME="3-5 hours"
        ;;
    Bulk)
        RESTORE_COST=$(echo "$REPO_SIZE_GB * 0.0025" | bc)
        RESTORE_TIME="5-12 hours"
        ;;
esac

TRANSFER_COST=$(echo "$REPO_SIZE_GB * 0.126" | bc)
TOTAL_COST=$(echo "$RESTORE_COST + $TRANSFER_COST" | bc)

log "Estimated restore time: $RESTORE_TIME"
log "Estimated cost (for ${REPO_SIZE_GB}GB):"
log "  Restore: \$$RESTORE_COST"
log "  Transfer: \$$TRANSFER_COST"
log "  Total: \$$TOTAL_COST"

echo ""
read -p "Do you want to proceed with the restore request? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log "Restore request cancelled by user."
    exit 0
fi

log "Fetching object list from S3..."

# 버킷의 모든 객체 목록 가져오기
OBJECT_KEYS=$(aws s3api list-objects-v2 \
    --bucket "$BUCKET_NAME" \
    --query 'Contents[].Key' \
    --output text)

if [ -z "$OBJECT_KEYS" ]; then
    log "ERROR: No objects found in bucket or access denied."
    exit 1
fi

TOTAL_OBJECTS=$(echo "$OBJECT_KEYS" | wc -w)
log "Found $TOTAL_OBJECTS objects to restore."

# 복원 요청 카운터
SUCCESS_COUNT=0
FAIL_COUNT=0
ALREADY_RESTORED=0

log "Starting restore requests..."

# 각 객체에 대해 복원 요청
for KEY in $OBJECT_KEYS; do
    # 이미 복원 중이거나 복원된 객체인지 확인
    RESTORE_STATUS=$(aws s3api head-object \
        --bucket "$BUCKET_NAME" \
        --key "$KEY" \
        2>/dev/null | jq -r '.Restore // "not_started"' || echo "not_started")

    if [[ "$RESTORE_STATUS" != "not_started" ]]; then
        log "  $KEY: Already restoring or restored (skipped)"
        ((ALREADY_RESTORED++))
        continue
    fi

    # 복원 요청
    if aws s3api restore-object \
        --bucket "$BUCKET_NAME" \
        --key "$KEY" \
        --restore-request "{\"Days\":$DAYS,\"GlacierJobParameters\":{\"Tier\":\"$TIER\"}}" \
        2>&1 | tee -a "$LOG_FILE"; then
        ((SUCCESS_COUNT++))
        # 진행률 표시 (100개마다)
        if [ $((SUCCESS_COUNT % 100)) -eq 0 ]; then
            log "  Progress: $SUCCESS_COUNT/$TOTAL_OBJECTS objects requested..."
        fi
    else
        log "  ERROR: Failed to restore $KEY"
        ((FAIL_COUNT++))
    fi
done

log ""
log "===== Restore Request Summary ====="
log "Total objects: $TOTAL_OBJECTS"
log "Successfully requested: $SUCCESS_COUNT"
log "Already restoring: $ALREADY_RESTORED"
log "Failed: $FAIL_COUNT"

if [ $SUCCESS_COUNT -gt 0 ] || [ $ALREADY_RESTORED -gt 0 ]; then
    log ""
    log "Restore request completed successfully!"
    log "Expected completion time: $RESTORE_TIME"
    log ""
    log "Next steps:"
    log "1. Monitor restore status:"
    log "   ./check-glacier-restore-status.sh"
    log ""
    log "2. After restore completes, download from S3:"
    log "   ./s3-to-local-download.sh"
else
    log "ERROR: All restore requests failed."
    exit 1
fi

log "===== Glacier Restore Request End ====="
