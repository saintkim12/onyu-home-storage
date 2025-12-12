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
LOGFILE="/var/log/restic-backup-immich.log"
DATE=$(date "+%Y-%m-%d %H:%M:%S")

echo "[$DATE] ===== Restic Backup Start =====" >> "$LOGFILE"

# ----------------------------
# Restic 백업 실행
# ----------------------------
echo "[$DATE] --> Starting restic backup of $SOURCE_PATH" >> "$LOGFILE"

# restic 백업 실행
restic -r "$RESTIC_REPO" \
    --insecure-no-password \
    --verbose \
    backup \
    --pack-size 64 \
    "$SOURCE_PATH" >> "$LOGFILE" 2>&1

if [ $? -eq 0 ]; then
    echo "[$DATE] --> Backup completed successfully" >> "$LOGFILE"
else
    echo "[$DATE] !! ERROR during restic backup" >> "$LOGFILE"
fi

# ----------------------------
# 스냅샷 목록 확인
# ----------------------------
echo "[$DATE] --> Checking snapshots" >> "$LOGFILE"

restic -r "$RESTIC_REPO" \
    --insecure-no-password \
    --verbose \
    snapshots >> "$LOGFILE" 2>&1

echo "[$DATE] ===== Restic Backup End =====" >> "$LOGFILE"
echo "" >> "$LOGFILE"
