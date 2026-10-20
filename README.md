# TrustVault

A cloud document vault built with Flutter and AWS.

## Features
- Amazon Cognito authentication
- Private Amazon S3 document storage
- Upload, list, and download documents
- Amazon API Gateway and AWS Lambda integration
- Presigned URLs for file transfers

## Architecture
Flutter Web -> Amazon Cognito -> API Gateway -> AWS Lambda -> Private Amazon S3

## Run locally
```bash
flutter pub get
flutter run -d web-server --web-hostname localhost --web-port 52100
```

## Build for web
```bash
flutter build web --release
```

## Security
- Keep the S3 bucket private.
- Never commit AWS secret keys, private keys, or authentication tokens.
- Verify authentication, user-specific access controls, and CORS before production deployment.
