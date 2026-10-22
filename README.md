# TrustVault 🔐
### Secure Document Sharing with a Real Audit Trail

TrustVault is a secure, cloud-based document management application designed to protect confidential files through authenticated access, user-level document isolation, and controlled file operations using AWS services.

The project was developed for the **Snovasys Fresher Hiring Challenge 2026**.

## 🚀 Live Application

**Access TrustVault:** https://staging.d1g1njsg5owizr.amplifyapp.com/

Open the application in your browser, create an account using your email and a strong password, and complete the email verification process to access your workspace.

> The application is hosted on AWS Amplify. Evaluators can access the deployed application without running the Flutter project locally.

## 🎯 Problem Statement

Organizations frequently share confidential documents, including contracts, employee records, financial reports, and business files.

Traditional file-sharing systems can expose sensitive information when access controls are incorrectly configured or users can access files belonging to others.

TrustVault addresses these challenges through:

- Authenticated user access.
- Per-user document listing and isolation.
- Controlled document upload and download operations.
- Private Amazon S3 object storage.
- Temporary presigned URLs for file operations.
- An AWS-based architecture designed to support auditable document access.

## ✨ Key Features

### 🔑 Secure Authentication
- User registration and email verification using Amazon Cognito.
- Token-based authentication for protected API requests.
- Authenticated access to the document workspace.

### 📁 Document Management
- Upload documents to cloud storage.
- Retrieve the authenticated user's document list.
- Download and open uploaded documents.
- Display documents within the user's workspace.

### 🛡️ User-Level Isolation
- Documents are organized under user-specific storage prefixes.
- The backend uses authenticated identity information to scope document operations.
- Isolation testing confirmed that one test account could not see another account's uploaded documents.

### ☁️ Cloud-Based Architecture
- Flutter web frontend hosted on AWS Amplify.
- Amazon Cognito for authentication.
- Amazon API Gateway for API access.
- AWS Lambda for backend document operations.
- Amazon S3 for private document storage.
- Amazon DynamoDB tables provisioned for document metadata, permissions, user indexing, and audit-related records.

### 🔗 Temporary File Access
The backend generates presigned URLs for authorized file operations, avoiding the need to expose AWS access keys in the frontend.

## 🏗️ System Architecture

```text
             User / Web Browser
                     |
                     v
           Flutter Web Application
                     |
                     v
             Amazon Cognito
          Authentication / Tokens
                     |
                     v
              Amazon API Gateway
               POST /presign
                     |
                     v
              AWS Lambda
          Authentication & Validation
                     |
          +----------+----------+
          |                     |
          v                     v
      Amazon S3             Amazon DynamoDB
   Private File Storage     Metadata / Permissions
                            / User Index / Audit Data
```

**Architecture overview:** The browser provides the user interface, Cognito authenticates users, API Gateway routes requests, Lambda performs backend operations, S3 stores documents, and DynamoDB supports structured application data.

## 🧰 Technology Stack

| Component | Technology |
|---|---|
| Frontend | Flutter Web, Dart |
| Authentication | Amazon Cognito |
| API | Amazon API Gateway |
| Backend | AWS Lambda, Python |
| Object Storage | Amazon S3 |
| Database | Amazon DynamoDB |
| Hosting | AWS Amplify |
| API Authentication | Cognito JWT authorizer |

## 🔄 Application Workflow

1. **Register:** A user creates an account using an email address and password.
2. **Verify:** The user completes the email verification process.
3. **Authenticate:** The application obtains authentication tokens.
4. **Upload:** The user selects a document and initiates an upload through the backend API.
5. **Store:** The document is stored in Amazon S3 under a user-specific prefix.
6. **List:** The backend retrieves documents associated with the authenticated user.
7. **Download:** The user requests an authorized document download through the backend.
8. **Audit readiness:** DynamoDB resources are provisioned for audit-related data. Complete read-event logging and audit-trail verification should be confirmed before claiming a fully implemented audit trail.

## 🔒 Security Design

TrustVault follows several security principles:

- **Authentication first:** Users authenticate before accessing protected application functionality.
- **Server-side identity:** User identity should be derived from verified authentication claims, not trusted from a client-supplied user ID.
- **Private storage:** Documents should remain private in Amazon S3, with access controlled by IAM policies and backend authorization.
- **Least privilege:** The Lambda execution role should grant only the permissions needed for application operations.
- **Temporary access:** Presigned URLs provide time-limited access to authorized file operations.
- **Credential protection:** AWS secret access keys are not embedded in the Flutter frontend.
- **Cross-user isolation:** Backend authorization must prevent users from listing, downloading, or modifying documents belonging to other users.
- **Auditable operations:** Security-sensitive events should be recorded with the authenticated identity, document identifier, action, timestamp, and outcome.

Security depends on backend enforcement and AWS configuration; frontend controls alone are not an authorization boundary.

## 🧪 Testing and Verification

The following workflows have been tested during development:

| Test | Result |
|---|---|
| Hosted application opens | Verified |
| User registration and email verification | Verified |
| Authenticated document upload | Verified |
| Document listing | Verified |
| Document download and opening | Verified |
| Per-user document listing isolation | Initial isolation test passed |
| Full cross-account download and authorization matrix | Requires dedicated verification |
| Persistent audit records for every read event | Requires verification before claiming complete |

Testing should include two separate user accounts and attempts to access another user's document, including direct API requests rather than only UI interactions.

## 📦 Repository Contents

The repository contains the application source code and project configuration required for development.

Typical Flutter project files include:

```text
trustvault/
├── lib/
│   └── main.dart
├── web/
├── pubspec.yaml
├── analysis_options.yaml
├── .gitignore
└── README.md
```

The exact repository structure may vary depending on the files committed to the project.

## 💻 Running Locally (Optional)

A local Flutter environment is required to run the source code.

**Prerequisites**
- Flutter SDK
- Dart SDK compatible with the Flutter version
- Google Chrome or another supported browser
- Access to the configured AWS-hosted backend and Cognito authentication

**Steps**

```bash
git clone <YOUR_GITHUB_REPOSITORY_URL>
cd trustvault
flutter pub get
flutter run -d chrome --web-port 52100
```

Replace `<YOUR_GITHUB_REPOSITORY_URL>` with the HTTPS URL of this repository.

The local development command is optional. The deployed application is available at the live link above. Local authentication requires the relevant redirect URI to be configured in Amazon Cognito.

## 🌐 Deployment

The web frontend is deployed using AWS Amplify.

**Live URL:** https://staging.d1g1njsg5owizr.amplifyapp.com/

The backend uses AWS services configured separately from the Flutter frontend. Required infrastructure includes the Cognito user pool, API Gateway route and authorizer, Lambda execution role, S3 bucket, and relevant DynamoDB tables.

## 🔮 Future Enhancements

- Verified, immutable-style audit history for document access.
- Document-level sharing and permission management.
- Administrative audit-log viewer.
- Improved access-denied handling and security monitoring.
- Automated tests for cross-user authorization and document lifecycle operations.

## 🏆 Project Objective

TrustVault demonstrates how a cloud-based document platform can combine authenticated access, user-level document isolation, temporary file access, and AWS-managed infrastructure to improve the security of confidential document sharing.

The primary objective is to ensure that **only authorized users can access their documents and that sensitive access operations can be independently verified.**

## 👩‍💻 Author

**Guntupalli Gayathri**

Snovasys Fresher Hiring Challenge 2026

---

*Built with Flutter and AWS to explore secure, cloud-based document sharing.*
