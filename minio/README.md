# MinIO

MinIO는 고성능 S3 호환 객체 스토리지 서버입니다.

## 서비스 정보

- **API 엔드포인트**: `http://localhost:9000`
- **웹 콘솔**: `http://localhost:9001`
- **기본 사용자**: `admin`
- **기본 비밀번호**: `minio123456`

## 시작하기

### 1. 서비스 시작
```bash
docker-compose up -d
```

### 2. 서비스 상태 확인
```bash
docker-compose ps
```

### 3. 로그 확인
```bash
docker-compose logs -f minio
```

### 4. 서비스 중지
```bash
docker-compose down
```

## 설정

### 환경 변수

- `MINIO_ROOT_USER`: 관리자 사용자명 (기본값: admin)
- `MINIO_ROOT_PASSWORD`: 관리자 비밀번호 (기본값: minio123456)
- `MINIO_CONSOLE_ADDRESS`: 웹 콘솔 주소 (기본값: :9001)

### 볼륨

- `minio_data`: MinIO 데이터 저장소

### 포트

- `9000`: MinIO API 포트
- `9001`: MinIO 웹 콘솔 포트

## 사용법

### 1. 웹 콘솔 접속
브라우저에서 `http://localhost:9001`에 접속하여 웹 콘솔을 사용할 수 있습니다.

### 2. S3 클라이언트 설정
MinIO는 S3 API와 호환되므로, S3 클라이언트를 사용하여 접근할 수 있습니다:

```bash
# AWS CLI 예시
aws configure set aws_access_key_id admin
aws configure set aws_secret_access_key minio123456
aws configure set default.region us-east-1
aws configure set default.s3.endpoint_url http://localhost:9000
```

### 3. 버킷 생성
웹 콘솔에서 버킷을 생성하거나, S3 클라이언트를 사용하여 생성할 수 있습니다:

```bash
aws s3 mb s3://my-bucket --endpoint-url http://localhost:9000
```

## 보안 고려사항

1. **기본 비밀번호 변경**: 프로덕션 환경에서는 반드시 기본 비밀번호를 변경하세요.
2. **네트워크 보안**: 필요한 경우 방화벽을 설정하여 접근을 제한하세요.
3. **SSL/TLS**: 프로덕션 환경에서는 HTTPS를 사용하세요.

## 문제 해결

### 서비스가 시작되지 않는 경우
```bash
# 로그 확인
docker-compose logs minio

# 컨테이너 상태 확인
docker-compose ps
```

### 포트 충돌이 발생하는 경우
`docker-compose.yaml` 파일에서 포트 매핑을 수정하세요:
```yaml
ports:
  - "9002:9000"  # 다른 포트 사용
  - "9003:9001"  # 다른 포트 사용
```

## 참고 자료

- [MinIO 공식 문서](https://docs.min.io/)
- [MinIO Docker Hub](https://hub.docker.com/r/minio/minio) 