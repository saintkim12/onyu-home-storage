#!/bin/bash
# -------------------------------------------------------------
# Restic backup script for Immich
# 실행 서버: 15번 서버 (raspberrypi)
# -------------------------------------------------------------
# /usr/local/bin/restic-backup-immich.sh

# 백업 소스 경로
SOURCE_PATH="/mnt/exthdd02/minio/data/immich/"

# restic 저장소 경로
RESTIC_REPO="/mnt/exthdd02/immich-archive-restic/restic"

# 로그
LOG_DIR="$HOME/.log"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/restic-backup-immich.log"              # 상세 로그
SUMMARY_LOGFILE="$LOG_DIR/restic-backup-immich-summary.log"  # 요약 로그
START_TIME=$(date "+%Y-%m-%d %H:%M:%S")
START_TIMESTAMP=$(date +%s)

echo "[$START_TIME] ===== Restic Backup Start =====" >> "$LOGFILE"
echo "[$START_TIME] ===== Restic Backup Start =====" >> "$SUMMARY_LOGFILE"

# ----------------------------
# Restic 백업 실행
# ----------------------------
echo "[$START_TIME] --> Starting restic backup of $SOURCE_PATH" >> "$LOGFILE"
echo "[$START_TIME] --> Starting restic backup of $SOURCE_PATH" >> "$SUMMARY_LOGFILE"

# restic 백업 실행
restic -r "$RESTIC_REPO" \
    --insecure-no-password \
    --verbose \
    backup \
    --pack-size 64 \
    "$SOURCE_PATH" >> "$LOGFILE" 2>&1

END_TIME=$(date "+%Y-%m-%d %H:%M:%S")
END_TIMESTAMP=$(date +%s)
DURATION=$((END_TIMESTAMP - START_TIMESTAMP))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

if [ $? -eq 0 ]; then
    echo "[$END_TIME] --> Backup completed successfully" >> "$LOGFILE"
    echo "[$END_TIME] --> Backup completed successfully" >> "$SUMMARY_LOGFILE"
else
    echo "[$END_TIME] !! ERROR during restic backup" >> "$LOGFILE"
    echo "[$END_TIME] !! ERROR during restic backup" >> "$SUMMARY_LOGFILE"
fi

# ----------------------------
# 스냅샷 목록 확인
# ----------------------------
echo "[$END_TIME] --> Checking snapshots" >> "$LOGFILE"

restic -r "$RESTIC_REPO" \
    --insecure-no-password \
    --verbose \
    snapshots >> "$LOGFILE" 2>&1

# 요약 로그에 스냅샷 개수만 기록
SNAPSHOT_COUNT=$(restic -r "$RESTIC_REPO" --insecure-no-password snapshots --json 2>/dev/null | grep -c '"time"')
echo "[$END_TIME] --> Total snapshots: $SNAPSHOT_COUNT" >> "$SUMMARY_LOGFILE"

echo "[$END_TIME] ===== Restic Backup End =====" >> "$LOGFILE"
echo "[$END_TIME] --> Total duration: ${DURATION_MIN}m ${DURATION_SEC}s" >> "$LOGFILE"
echo "" >> "$LOGFILE"

echo "[$END_TIME] ===== Restic Backup End =====" >> "$SUMMARY_LOGFILE"
echo "[$END_TIME] --> Total duration: ${DURATION_MIN}m ${DURATION_SEC}s" >> "$SUMMARY_LOGFILE"
echo "" >> "$SUMMARY_LOGFILE"
