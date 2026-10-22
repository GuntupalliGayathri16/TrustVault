# THREATS.md — TrustVault Security Threat Model

**Project:** TrustVault — Secure Document Sharing with a Real Audit Trail  
**Challenge:** Snovasys Fresher Hiring Challenge 2026  
**Developer:** Guntupalli Gayathri  
**Assessment focus:** Document confidentiality, authorization, auditability, and security testing  
**Last reviewed:** 22 October 2026

---

## 1. Purpose

TrustVault is a secure document-sharing application designed to ensure that authenticated users can access only documents they are authorized to use, while providing evidence of document-access activity.

This threat model identifies important security risks, describes the controls intended to reduce those risks, and defines tests for evaluating the deployed application.

The primary security objectives are:

- **Confidentiality:** Prevent unauthorized users from viewing or downloading private documents.
- **Authorization:** Enforce document-level access decisions on the backend.
- **Integrity:** Prevent unauthorized document modification or replacement.
- **Auditability:** Record relevant document-access events with reliable user attribution.
- **Account isolation:** Keep one user's documents separate from another user's documents.
- **Least privilege:** Restrict backend and storage permissions to the operations required by the application.

A feature is not considered secure merely because the normal user workflow succeeds. Security controls must also withstand unauthorized requests.

## 2. System Architecture and Trust Boundaries

The application uses the following components:

| Component | Responsibility | Security consideration |
|---|---|---|
| Flutter Web | User interface and document operations | Must not be trusted to enforce authorization by itself |
| Amazon Cognito | User authentication | Tokens must be validated before protected operations |
| Amazon API Gateway | API entry point and JWT authorization | Requests must be authenticated and routed correctly |
| AWS Lambda | Backend document-operation logic | Must enforce authorization for each requested resource |
| Amazon S3 | Document object storage | Objects must remain private unless access is explicitly authorized |
| Amazon DynamoDB | Document metadata, permissions, and audit-related records | Access policies must protect sensitive records and enforce appropriate restrictions |
| AWS IAM | Permissions between AWS services | Policies should follow least-privilege principles |
| Presigned URLs | Time-limited document access | URLs act as bearer credentials and must be protected |

### Trust boundaries

1. **Browser to API:** Client input is untrusted, even when it originates from the application interface.
2. **Identity to authorization:** A valid authenticated identity does not automatically grant permission to every document.
3. **Backend to S3:** The backend must ensure that the requested object belongs to, or is shared with, the caller.
4. **Backend to DynamoDB:** Metadata, permission records, and audit events must be handled using appropriately restricted permissions.
5. **Audit generation to audit storage:** Event identity and details should originate from trusted server-side processing rather than arbitrary client claims.

## 3. Threat Assessment

### T1 — Unauthorized Cross-Account Document Access

**Threat:** An authenticated user attempts to view or download a document belonging to another user.

**Potential impact:** Disclosure of confidential contracts, personal information, employment documents, or other private files.

**Intended controls:**

- Derive the authenticated identity from a validated token.
- Enforce document ownership or an explicitly granted permission on the backend.
- Do not rely exclusively on frontend filtering or user-supplied ownership fields.
- Keep S3 objects private and avoid unrestricted object access.

**Verification approach:**

1. Create or use two separate test accounts.
2. Upload a distinct document under Account A.
3. Sign in as Account B.
4. Attempt to list and download Account A's document.
5. Record the actual API response and verify that document contents are not disclosed.

**Expected result:** Account B cannot access Account A's document without an explicit authorization grant.

**Actual result:** Record the observed result for each test separately.

### T2 — Document Identifier Manipulation

**Threat:** A user modifies a document ID, object key, filename, or request parameter to target another user's file.

**Potential impact:** Unauthorized document disclosure or access to sensitive metadata.

**Intended controls:**

- Treat client-provided document identifiers as untrusted input.
- Resolve the requested document against trusted server-side metadata.
- Check the caller's permission before issuing a download URL or performing a document operation.
- Avoid accepting arbitrary S3 object keys as sufficient proof of authorization.

**Verification approach:**

1. Authenticate as Account A.
2. Obtain a document identifier for a separate test account's document.
3. Submit a download request using the modified identifier.
4. Inspect the API response and confirm that no usable unauthorized download URL or document content is returned.

**Expected result:** The backend denies access when the caller is not authorized for the requested document.

**Actual result:** Record the observed response and whether the test passed.

### T3 — Unauthorized Upload or Document Replacement

**Threat:** A user attempts to upload a file into another user's namespace or replace a document without permission.

**Potential impact:** Data loss, document tampering, or unauthorized content injection.

**Intended controls:**

- Determine the user's identity from validated authentication information.
- Construct storage locations using trusted backend logic.
- Validate the requested operation and relevant metadata.
- Enforce ownership and sharing permissions before modifying existing documents.
- Restrict the Lambda execution role to the S3 and other AWS resources required by the application.

**Verification approach:**

1. Use separate test accounts and documents.
2. Attempt to submit a modified target identifier or object key.
3. Check whether the backend rejects unauthorized operations.
4. Confirm that the original document remains unchanged.

**Expected result:** A user cannot overwrite or replace another user's document without explicit authorization.

**Actual result:** Record the actual outcome.

### T4 — Missing, Invalid, or Expired Authentication

**Threat:** A caller attempts to invoke a protected API without a valid access token, with a modified token, or with an expired token.

**Potential impact:** Unauthorized access to document operations.

**Intended controls:**

- Configure API Gateway to validate JWTs for protected routes.
- Reject requests with missing, invalid, or expired credentials.
- Avoid treating frontend navigation or a visible signed-in state as proof of backend authorization.
- Ensure backend identity decisions use trusted authentication claims.

**Verification approach:**

1. Call a protected API without an authorization token.
2. Repeat with an invalid token.
3. Where practical, test an expired token.
4. Confirm that the requests are rejected without disclosing protected information.

**Expected result:** Invalid or missing credentials cannot access protected document operations.

**Actual result:** Record each result separately.

### T5 — Presigned URL Exposure or Reuse

**Threat:** A user shares a presigned URL, or another person obtains it before it expires.

**Potential impact:** A person holding the URL may access the associated object while the URL remains valid.

**Intended controls:**

- Keep the S3 bucket private.
- Generate presigned URLs only after server-side authorization.
- Use short expiration periods appropriate to the operation.
- Avoid logging full presigned URLs or exposing them unnecessarily.
- Treat presigned URLs as sensitive bearer credentials.

**Verification approach:**

1. Confirm that direct unauthenticated object access is blocked when no valid presigned URL is provided.
2. Check the configured expiration period.
3. Verify that the backend does not issue download URLs to unauthorized callers.
4. Confirm the limitations of URL reuse during its validity period.

**Expected result:** Direct access to private objects is restricted, and presigned URLs are issued only for authorized operations.

**Actual result:** Record the observed behavior.

**Residual risk:** Anyone who obtains a valid presigned URL may be able to use it until it expires. Short expiry limits this exposure but does not eliminate it.

### T6 — Audit Event Missing or Incorrectly Attributed

**Threat:** A document read occurs without the expected audit event, or the event records an incorrect user identity.

**Potential impact:** Investigators cannot reliably determine who accessed a document.

**Intended controls:**

- Generate audit events through trusted backend processing.
- Derive user attribution from validated authentication claims.
- Associate events with relevant document identifiers and timestamps.
- Define which successful and failed access attempts must be recorded.
- Restrict access to audit records.

**Verification approach:**

1. Perform a document-read operation as a test user.
2. Inspect the corresponding audit record.
3. Verify the recorded user identity, document reference, event type, and timestamp.
4. Where required by the design, attempt an unauthorized read and inspect whether it is recorded.

**Expected result:** Required document-access events are recorded with accurate server-derived attribution.

**Actual result:** Record the observed event and the fields verified.

### T7 — Audit Record Tampering or Unauthorized Access

**Threat:** A user or compromised application component attempts to alter, delete, or access audit records without permission.

**Potential impact:** Loss of accountability and unreliable investigation evidence.

**Intended controls:**

- Restrict DynamoDB permissions to the operations each component requires.
- Avoid granting ordinary users direct access to audit storage.
- Separate audit-record creation from unnecessary modification or deletion capabilities where feasible.
- Review IAM policies and application endpoints for unauthorized audit operations.

**Verification approach:**

1. Review the Lambda execution role and relevant DynamoDB permissions.
2. Attempt unauthorized access through available application interfaces and APIs.
3. Confirm that the application does not expose audit-management operations to ordinary users without permission.

**Expected result:** Unauthorized users cannot read or modify protected audit records through the application's exposed operations.

**Actual result:** Record the observed result and the permissions reviewed.

### T8 — Excessive AWS Permissions

**Threat:** An overly permissive IAM policy allows a compromised Lambda function or unauthorized operation to access unrelated resources.

**Potential impact:** Broader data exposure, document tampering, or audit-record compromise.

**Intended controls:**

- Scope S3 access to the required bucket and object prefixes.
- Restrict DynamoDB permissions to required tables and operations.
- Avoid unnecessary wildcard permissions.
- Review API Gateway authorization and Lambda resource permissions.
- Keep credentials and sensitive configuration out of frontend code.

**Verification approach:**

1. Inspect the Lambda execution role.
2. Check the resources and actions allowed by each policy.
3. Confirm that permissions match the application's actual operations.
4. Document any excessive permissions discovered and corrected.

**Expected result:** AWS permissions are limited to the resources and actions necessary for the application.

**Actual result:** Record the policy review findings.

## 4. Security Test Record

Use this table to document the results of tests actually performed against the application.

| Test | Expected outcome | Actual outcome |
|---|---|---|
| Separate-account document listing | Users see only documents they are authorized to access | Record observed result |
| Cross-account download attempt | Unauthorized download is denied | Record observed result |
| Modified document identifier | Backend denies unauthorized access | Record observed result |
| Unauthorized upload or overwrite | Operation is denied and existing content is protected | Record observed result |
| Missing or invalid JWT | Protected request is rejected | Record observed result |
| Private S3 object access | Direct access without valid authorization is denied | Record observed result |
| Document-read audit event | Required event is recorded with trusted user attribution | Record observed result |
| Audit-record access | Unauthorized access or modification is denied | Record observed result |
| IAM least-privilege review | Permissions match required application operations | Record review findings |

**Reporting rule:** Mark each test `PASS`, `FAIL`, or `NOT TESTED` based on actual evidence. Do not treat a test as passed merely because the corresponding security feature was intended or implemented.

## 5. Residual Risks and Limitations

Security controls reduce risk but do not automatically eliminate it. The following considerations remain relevant to a document-sharing application:

- A valid presigned URL may be reused by anyone who obtains it until it expires.
- Compromise of a user's credentials may allow actions that the user is authorized to perform.
- Incorrect IAM policies may undermine application-level controls.
- Missing audit events can reduce the reliability of investigations.
- Audit records are only as trustworthy as their event-generation and access-control mechanisms.
- Security testing of selected scenarios does not establish the absence of every vulnerability.

Residual risks should be evaluated against the actual deployed configuration and test evidence.

## 6. Security Principles

TrustVault's security approach follows these principles:

1. **Least privilege:** Grant only the access required for each operation.
2. **Backend enforcement:** Treat client requests as untrusted and enforce authorization server-side.
3. **Default denial:** Reject requests when identity or permission checks fail.
4. **Identity-derived authorization:** Use validated authentication claims rather than trusting client-supplied identities.
5. **Private storage:** Keep confidential objects inaccessible through unrestricted public access.
6. **Auditable operations:** Record required security events with reliable attribution.
7. **Evidence-based claims:** Distinguish implementation, testing, and verified outcomes.
8. **Defense in depth:** Use authentication, authorization, storage restrictions, IAM controls, and auditability together.

## 7. Conclusion

TrustVault is designed to protect confidential documents through authenticated access, backend authorization, restricted object storage, and auditable document operations.

The security of the application depends on the correct implementation and verification of these controls. This threat model provides a structured basis for reviewing risks, testing security boundaries, and documenting the results honestly.

It is a project-level threat assessment, not an independent penetration-test certification or a guarantee that the system is free from vulnerabilities.
