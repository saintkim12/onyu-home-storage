#!/bin/bash
# -------------------------------------------------------------
# Docker volume backup script (rsync pull 방식)
# 실행 서버: 15번 서버 (raspberrypi)

## 선작업 내용(13, 17)
# mkdir -p /root/.ssh
# chmod 700 /root/.ssh
# vi /root/.ssh/authorized_keys
# ```
# # saintkim12@raspberrypi:~ $ ssh-keygen -t ed25519
# # saintkim12@raspberrypi:~ $ cat ~/.ssh/id_ed25519.pub
# ssh-ed25519 *** saintkim12@raspberrypi
# ```
# chmod 600 /root/.ssh/authorized_keys
# vi /etc/ssh/sshd_config
# ```
# PubkeyAuthentication yes
# PasswordAuthentication yes
# Match User root
#    PasswordAuthentication no
#    PermitRootLogin yes
# ```
# rc-service sshd restart
## 선작업 내용(13, 17)
# -------------------------------------------------------------
# /usr/local/bin/docker-volume-backup.sh

# 백업 대상 서버 정보
SERVICE_VM_IP="192.168.1.13"
ALBUM_VM_IP="192.168.1.17"

# 원격 경로
REMOTE_PATH="/opt/data/"

# 로컬 백업 경로
BASE="/mnt/exthdd02/backup-docker"
SERVICE_DIR="$BASE/service-vm"
ALBUM_DIR="$BASE/album-vm"

# 로그
LOG_DIR="$HOME/.log"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/docker-volume-backup.log"              # 상세 로그 (모든 파일 업로드 내역)
SUMMARY_LOGFILE="$LOG_DIR/docker-volume-backup-summary.log"  # 요약 로그 (결과만)
START_TIME=$(date "+%Y-%m-%d %H:%M:%S")
START_TIMESTAMP=$(date +%s)

echo "[$START_TIME] ===== Backup Start =====" >> "$LOGFILE"
echo "[$START_TIME] ===== Backup Start =====" >> "$SUMMARY_LOGFILE"

# ----------------------------
# 함수: rsync 백업 실행
# ----------------------------
backup_rsync() {
    local TARGET_IP=$1
    local TARGET_DIR=$2
    local NAME=$3

    DATE=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$DATE] --> Starting backup of $NAME ($TARGET_IP)" >> "$LOGFILE"

    # rsync 실행
    rsync -avz \
        --delete \
        -e "ssh -o StrictHostKeyChecking=no" \
        root@"$TARGET_IP":"$REMOTE_PATH" \
        "$TARGET_DIR" >> "$LOGFILE" 2>&1

    DATE=$(date "+%Y-%m-%d %H:%M:%S")
    if [ $? -eq 0 ]; then
        echo "[$DATE] --> Completed: $NAME" >> "$LOGFILE"
        echo "[$DATE] --> Completed: $NAME" >> "$SUMMARY_LOGFILE"
    else
        echo "[$DATE] !! ERROR during backup of $NAME" >> "$LOGFILE"
        echo "[$DATE] !! ERROR during backup of $NAME" >> "$SUMMARY_LOGFILE"
    fi
}

# ----------------------------
# 백업 실행
# ----------------------------
backup_rsync "$SERVICE_VM_IP" "$SERVICE_DIR" "service-vm"
backup_rsync "$ALBUM_VM_IP" "$ALBUM_DIR" "album-vm"

END_TIME=$(date "+%Y-%m-%d %H:%M:%S")
END_TIMESTAMP=$(date +%s)
DURATION=$((END_TIMESTAMP - START_TIMESTAMP))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

# ----------------------------
# 백업 종료 및 통계 출력
# ----------------------------
echo "[$END_TIME] ===== Backup End =====" >> "$LOGFILE"
echo "[$END_TIME] --> Total duration: ${DURATION_MIN}m ${DURATION_SEC}s" >> "$LOGFILE"
echo "" >> "$LOGFILE"

echo "[$END_TIME] ===== Backup End =====" >> "$SUMMARY_LOGFILE"
echo "[$END_TIME] --> Total duration: ${DURATION_MIN}m ${DURATION_SEC}s" >> "$SUMMARY_LOGFILE"
echo "" >> "$SUMMARY_LOGFILE"
