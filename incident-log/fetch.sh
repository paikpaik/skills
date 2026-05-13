#!/usr/bin/env bash
# incident-log fetch — EC2에서 로그를 로컬로 내려받는 스크립트
set -e

usage() {
  echo "사용법:"
  echo "  ./fetch.sh -h HOST -i KEY_PATH [-u USER] [-o OUTPUT_DIR]"
  echo ""
  echo "옵션:"
  echo "  -h  EC2 호스트 (IP 또는 도메인)   예) 10.2.4.58"
  echo "  -i  SSH 키 경로                    예) ~/awskey_avatye.pem"
  echo "  -u  SSH 유저 (기본: ec2-user)"
  echo "  -o  로그 저장 디렉토리 (기본: ./incident-logs-YYYYMMDD-HHmm)"
  echo ""
  echo "예시:"
  echo "  ./fetch.sh -h 10.2.4.58 -i ~/awskey_avatye.pem"
  echo "  ./fetch.sh -h 10.2.4.58 -i ~/awskey_avatye.pem -u ubuntu"
  exit 1
}

HOST=""
KEY=""
USER="ec2-user"
OUT=""

while getopts "h:i:u:o:" opt; do
  case $opt in
    h) HOST="$OPTARG" ;;
    i) KEY="$OPTARG" ;;
    u) USER="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    *) usage ;;
  esac
done

[ -z "$HOST" ] && { echo "오류: -h HOST 필수"; usage; }
[ -z "$KEY" ]  && { echo "오류: -i KEY_PATH 필수"; usage; }

KEY="${KEY/#\~/$HOME}"
[ ! -f "$KEY" ] && { echo "오류: 키 파일을 찾을 수 없습니다 — $KEY"; exit 1; }
chmod 400 "$KEY" 2>/dev/null || true

[ -z "$OUT" ] && OUT="./incident-logs-$(date +%Y%m%d-%H%M)"
mkdir -p "$OUT"

SCP="scp -q -i $KEY -o StrictHostKeyChecking=no"
SSH="ssh -i $KEY -o StrictHostKeyChecking=no $USER@$HOST"

echo ""
echo "EC2 로그 수집 중..."
echo "  호스트: $USER@$HOST"
echo "  저장:   $OUT"
echo ""

fetch_file() {
  local remote="$1"
  local label="$2"
  if $SCP "$USER@$HOST:$remote" "$OUT/" 2>/dev/null; then
    echo "  v $label"
  else
    echo "  - $label (없음, 건너뜀)"
  fi
}

fetch_glob() {
  local remote_pattern="$1"
  local label="$2"
  local files
  files=$($SSH "ls $remote_pattern 2>/dev/null" 2>/dev/null || true)
  if [ -n "$files" ]; then
    echo "$files" | while read -r f; do
      $SCP "$USER@$HOST:$f" "$OUT/" 2>/dev/null || true
    done
    echo "  v $label"
  else
    echo "  - $label (없음, 건너뜀)"
  fi
}

# nginx
fetch_file "/var/log/nginx/access.log"           "nginx access.log"
fetch_file "/var/log/nginx/access.log.1"         "nginx access.log.1"
fetch_file "/var/log/nginx/error.log"            "nginx error.log"
fetch_file "/var/log/nginx/error.log.1"          "nginx error.log.1"

# Elastic Beanstalk
fetch_file "/var/log/eb-engine.log"              "eb-engine.log"
fetch_file "/var/log/eb-activity.log"            "eb-activity.log"
fetch_glob "/var/app/current/logs/*.log"         "EB app logs"

# PM2
fetch_glob "~/.pm2/logs/*.log"                   "pm2 logs"
fetch_glob "/home/$USER/.pm2/logs/*.log"         "pm2 logs (alt)"

# Node/App 일반
fetch_glob "/var/app/current/logs/combined*.log" "app combined log"

# MySQL / Aurora
fetch_file "/var/log/mysqld.log"                 "mysql error log"
fetch_file "/var/log/mysql/error.log"            "mysql error log (alt)"

echo ""
echo "수집 완료 -> $OUT"
echo ""
echo "다음 단계: Claude Code에서 아래 커맨드 실행"
echo ""
echo "  /incident-log $OUT"
echo ""
