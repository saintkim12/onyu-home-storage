#!/bin/bash
# -------------------------------------------------------------
# Restic repository sync to AWS S3 script
# 실행 서버: 15번 서버 (raspberrypi)
# restic 저장소 전체를 S3로 동기화 (월 1회)
#
# 주의: sudo로 실행하지 마세요! (파일 권한 문제)
# 크론탭: $USER 사용자로 실행
# -------------------------------------------------------------
# /usr/local/bin/restic-sync-to-s3.sh

# restic 저장소 경로
RESTIC_REPO="/mnt/exthdd02/immich-archive-restic/restic"

# S3 경로 (mc alias/bucket/path 형식)
S3_TARGET="aws/immich-archive-restic"

# 로그
LOG_DIR="$HOME/.log"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/restic-sync-to-s3.log"              # 상세 로그 (모든 파일 업로드 내역)
SUMMARY_LOGFILE="$LOG_DIR/restic-sync-to-s3-summary.log"  # 요약 로그 (결과만)
START_TIME=$(date "+%Y-%m-%d %H:%M:%S")
START_TIMESTAMP=$(date +%s)

echo "[$START_TIME] ===== Restic to S3 Sync Start =====" >> "$LOGFILE"
echo "[$START_TIME] ===== Restic to S3 Sync Start =====" >> "$SUMMARY_LOGFILE"

# ----------------------------
# mc mirror로 S3 동기화
# ----------------------------
echo "[$START_TIME] --> Starting sync of restic repository to S3" >> "$LOGFILE"
echo "[$START_TIME] --> Starting sync of restic repository to S3" >> "$SUMMARY_LOGFILE"

# mc mirror 실행
# --storage-class DEEP_ARCHIVE: Glacier Deep Archive 사용
# --remove: 소스에 없는 파일은 대상에서 삭제 (동기화)
mc mirror \
    --storage-class "DEEP_ARCHIVE" \
    --remove \
    "$RESTIC_REPO" \
    "$S3_TARGET" >> "$LOGFILE" 2>&1

END_TIME=$(date "+%Y-%m-%d %H:%M:%S")
END_TIMESTAMP=$(date +%s)
DURATION=$((END_TIMESTAMP - START_TIMESTAMP))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

if [ $? -eq 0 ]; then
    echo "[$END_TIME] --> S3 sync completed successfully" >> "$LOGFILE"
    echo "[$END_TIME] --> S3 sync completed successfully" >> "$SUMMARY_LOGFILE"
else
    echo "[$END_TIME] !! ERROR during S3 sync" >> "$LOGFILE"
    echo "[$END_TIME] !! ERROR during S3 sync" >> "$SUMMARY_LOGFILE"
fi

# ----------------------------
# 동기화 후 통계 출력
# ----------------------------
echo "[$END_TIME] --> Checking local restic repository size" >> "$LOGFILE"
REPO_SIZE=$(du -sh "$RESTIC_REPO" 2>&1)
echo "$REPO_SIZE" >> "$LOGFILE"
echo "[$END_TIME] --> Repository size: $REPO_SIZE" >> "$SUMMARY_LOGFILE"

echo "[$END_TIME] ===== Restic to S3 Sync End =====" >> "$LOGFILE"
echo "[$END_TIME] --> Total duration: ${DURATION_MIN}m ${DURATION_SEC}s" >> "$LOGFILE"
echo "" >> "$LOGFILE"

echo "[$END_TIME] ===== Restic to S3 Sync End =====" >> "$SUMMARY_LOGFILE"
echo "[$END_TIME] --> Total duration: ${DURATION_MIN}m ${DURATION_SEC}s" >> "$SUMMARY_LOGFILE"
echo "" >> "$SUMMARY_LOGFILE"
