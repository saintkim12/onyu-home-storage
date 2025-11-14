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
# PermitRootLogin yes
# PubkeyAuthentication yes
# PasswordAuthentication no
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
LOGFILE="/var/log/docker-volume-backup.log"
DATE=$(date "+%Y-%m-%d %H:%M:%S")

echo "[$DATE] ===== Backup Start =====" >> "$LOGFILE"

# ----------------------------
# 함수: rsync 백업 실행
# ----------------------------
backup_rsync() {
    local TARGET_IP=$1
    local TARGET_DIR=$2
    local NAME=$3

    echo "[$DATE] --> Starting backup of $NAME ($TARGET_IP)" >> "$LOGFILE"

    # rsync 실행
    rsync -avz \
        --delete \
        -e "ssh -o StrictHostKeyChecking=no" \
        root@"$TARGET_IP":"$REMOTE_PATH" \
        "$TARGET_DIR" >> "$LOGFILE" 2>&1

    if [ $? -eq 0 ]; then
        echo "[$DATE] --> Completed: $NAME" >> "$LOGFILE"
    else
        echo "[$DATE] !! ERROR during backup of $NAME" >> "$LOGFILE"
    fi
}

# ----------------------------
# 백업 실행
# ----------------------------
backup_rsync "$SERVICE_VM_IP" "$SERVICE_DIR" "service-vm"
backup_rsync "$ALBUM_VM_IP" "$ALBUM_DIR" "album-vm"

echo "[$DATE] ===== Backup End =====" >> "$LOGFILE"
echo "" >> "$LOGFILE"
