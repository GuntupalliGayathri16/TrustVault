# PROMPTS.md — AI-Assisted Development Record

**Project:** TrustVault — Secure Document Sharing with a Real Audit Trail  
**Developer:** Guntupalli Gayathri  
**Challenge:** Snovasys Fresher Hiring Challenge 2026  
**AI Assistant:** ChatGPT  
**Development Period:** 19–22 October 2026

## 1. Purpose and Approach

This document records how AI assistance was used during the development of TrustVault. It covers the engineering questions explored, recommendations evaluated, problems identified, implementation decisions, and verification activities.

AI-generated suggestions were treated as proposals rather than authoritative solutions. I reviewed recommendations against the application implementation and AWS configuration, particularly where authentication, authorization, document access, and auditability were involved.

A successful user workflow was not treated as sufficient evidence of security. Security claims were evaluated separately against the relevant implementation and test results.

## 2. Application Architecture and AWS Integration

**Date:** 19 October 2026

**Engineering question:** How should a Flutter web application securely support authenticated document storage using Amazon Cognito, Amazon API Gateway, AWS Lambda, Amazon S3, and DynamoDB?

**AI-assisted work:** Explored the responsibilities of the frontend, authentication layer, API endpoints, backend document operations, and storage layer. Reviewed the flow of authenticated requests between these components.

**Critical assessment:** Authentication establishes a caller's identity, but it does not automatically authorize access to every requested document. Frontend checks alone cannot enforce document ownership.

**Development decision:** Implemented the application around authenticated API requests and backend document operations, with authorization treated as a separate security responsibility.

**Verification:** Exercised the document-management workflow and evaluated security controls separately from ordinary functional behavior.

**Evidence:** [TrustVault repository history](https://github.com/GuntupalliGayathri16/TrustVault/commits/master)

## 3. Cognito Authentication and Deployment Configuration

**Date:** 20 October 2026

**Engineering question:** How can Cognito authentication work consistently in local development and in the deployed Flutter web application?

**AI-assisted work:** Investigated authentication redirects, Cognito callback URLs, logout redirects, and the use of a consistent local development port.

**Problem identified:** The redirect URI used by the application must match an allowed URI in the Cognito app client configuration. Local and deployed URLs must be configured appropriately for their respective environments.

**Development decision:** Configured the deployed application to use its hosted URL and maintained a consistent local development port for local testing.

**Verification:** Tested hosted registration and email verification and exercised the authenticated application workflow.

**Security consideration:** Successful authentication confirms that a user can sign in; backend authorization must still independently control access to documents.

**Evidence:** [TrustVault repository history](https://github.com/GuntupalliGayathri16/TrustVault/commits/master)

## 4. Document Upload, Listing, and Download Troubleshooting

**Date:** 21 October 2026

**Engineering question:** How can upload, listing, download, and file opening work reliably across Flutter and the AWS backend?

**AI-assisted work:** Investigated API action handling, Lambda responses, frontend request construction, and browser-side file operations.

**Problems encountered:** During development, requests returned an unknown-action error, and document listing encountered a backend error. These failures demonstrated the need to validate both frontend requests and backend behavior.

**Corrective approach:** Investigated the request and response flow, corrected integration issues, and retested the affected operations.

**Verification:** Upload, document listing, download, and opening were tested and reported working in the application.

**Critical assessment:** Successful upload alone does not establish that listing, downloading, error handling, or access control works correctly. These operations require separate verification.

**Evidence:** [TrustVault repository history](https://github.com/GuntupalliGayathri16/TrustVault/commits/master)

## 5. Authorization and Per-User Document Isolation

**Date:** 21 October 2026

**Engineering question:** Can one authenticated user access another user's documents by manipulating document identifiers, request parameters, or API requests?

**AI-assisted work:** Reviewed user-specific storage prefixes, identity-derived authorization, and the difference between frontend filtering and backend access control.

**Critical assessment:** Frontend filtering is not an authorization boundary. A caller may modify requests or invoke an API directly. The backend must determine whether the authenticated caller is permitted to perform each requested operation.

**Development decision:** Tested document isolation using separate accounts and evaluated listing and download authorization as distinct security controls.

**Verification:** Per-user document-listing isolation and cross-account access controls were tested during development. The final result recorded for each test should match the actual observed outcome.

**Security considerations evaluated:**

- Whether one user can list another user's documents.
- Whether another user's document can be downloaded using a modified identifier.
- Whether unauthorized upload or overwrite operations are rejected.
- Whether direct API requests are subject to backend authorization.
- Whether unauthorized operations avoid exposing document contents or sensitive metadata.
- Whether S3 permissions and the Lambda execution role follow least-privilege principles.

**Evidence:** [TrustVault repository history](https://github.com/GuntupalliGayathri16/TrustVault/commits/master)

## 6. Audit Trail and Document-Read Verification

**Date:** 22 October 2026

**Engineering question:** What evidence is required to demonstrate that TrustVault records who accessed a document?

**AI-assisted work:** Examined the difference between provisioning audit-related AWS resources and implementing a functioning audit trail. Considered event capture, user attribution, event integrity, and the information needed for investigation.

**Critical assessment:** The existence of a DynamoDB audit table does not by itself demonstrate that document-read events are recorded correctly. Audit records must be associated with a trusted identity and protected against unauthorized modification or deletion.

**Development decision:** Evaluated auditability separately from ordinary document-management functionality and ensured that documentation distinguishes implemented behavior from assumptions.

**Verification:** Document-read event recording and user attribution were evaluated against the implemented audit behavior. The final documented result should correspond to the observed event records and the actual tests performed.

**Security considerations evaluated:**

- Whether successful document reads generate the intended audit event.
- Whether relevant failed or unauthorized attempts are recorded according to the design.
- Whether user attribution comes from a trusted server-side identity.
- Whether permissions governing audit-record creation and access are appropriately restricted.
- Whether the recorded information supports investigation of document-access activity.

**Evidence:** [README update — commit 3cb8ac4](https://github.com/GuntupalliGayathri16/TrustVault/commit/3cb8ac4)

## 7. AI-Assisted Review and Evidence-Based Documentation

**Date:** 22 October 2026

**Engineering question:** How should project documentation describe security controls without overstating what the implementation demonstrates?

**AI-assisted work:** Used AI assistance to review technical explanations, distinguish functionality from security guarantees, and identify claims requiring implementation or test evidence.

**Critical assessment:** Documentation becomes misleading when planned functionality is described as complete or when a successful ordinary workflow is treated as proof of security.

**Development decision:** Structured the project documentation around implemented components, observed behavior, security decisions, and evidence-based claims.

**Verification:** Reviewed the README and development record for consistency with the implementation and the results observed during testing.

**Evidence:** [README update — commit 3cb8ac4](https://github.com/GuntupalliGayathri16/TrustVault/commit/3cb8ac4)

## 8. Engineering Principles

The following principles guided the use of AI assistance:

- Review AI-generated recommendations against the actual source code and AWS configuration.
- Treat authentication, authorization, and auditability as separate security responsibilities.
- Enforce access control on the backend rather than relying solely on frontend restrictions.
- Evaluate negative security cases alongside successful user workflows.
- Preserve working behavior while correcting integration issues.
- Support security claims with implementation details and test evidence.
- Document limitations honestly and update them when new verification is completed.
- Maintain genuine commit history that reflects actual development activity.
- Ensure that the implementation and security decisions can be explained independently.

## 9. Developer Responsibility

AI assistance supported investigation, troubleshooting, review, and documentation. It did not replace implementation review, AWS configuration review, or security testing.

I remain responsible for the submitted application, its security decisions, the accuracy of the documentation, and the ability to explain and modify the implementation during evaluation.

This record describes AI-assisted development and the engineering reasoning applied to TrustVault. It is not a claim of independent certification or a guarantee that the application is free of vulnerabilities.
