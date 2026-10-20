
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:html' as html;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const TrustVaultApp());
}

const String cognitoDomain =
    'https://us-east-16bj40uxfi.auth.us-east-1.amazoncognito.com';
const String clientId = '24tonblo0hgmp5hdad6s11jesv';
const String redirectUri = 'http://localhost:52100/';
const String presignEndpoint =
    'https://y76x3dol83.execute-api.us-east-1.amazonaws.com/presign';

class TrustVaultApp extends StatelessWidget {
  const TrustVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrustVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
        ),
        useMaterial3: true,
      ),
      home: const TrustVaultHome(),
    );
  }
}

class VaultDocument {
  VaultDocument({
    required this.name,
    required this.size,
    this.status = 'Uploaded successfully',
    this.s3Key,
    this.lastModified,
  });

  final String name;
  final int size;
  String status;
  String? s3Key;
  DateTime? lastModified;
}

class TrustVaultHome extends StatefulWidget {
  const TrustVaultHome({super.key});

  @override
  State<TrustVaultHome> createState() => _TrustVaultHomeState();
}

class _TrustVaultHomeState extends State<TrustVaultHome> {
  bool isBusy = false;
  bool authChecking = true;
  bool isLoadingDocuments = false;

  String? accessToken;
  String? authMessage;
  String? documentsError;

  final List<VaultDocument> documents = [];

  @override
  void initState() {
    super.initState();

    accessToken =
        html.window.sessionStorage['trustvault_access_token'];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleAuthCallback();
    });
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String randomUrlSafe(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(
      byteCount,
      (_) => random.nextInt(256),
    );

    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> signIn() async {
    final verifier = randomUrlSafe(32);
    final state = randomUrlSafe(24);

    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');

    html.window.sessionStorage['trustvault_pkce_verifier'] =
        verifier;
    html.window.sessionStorage['trustvault_oauth_state'] = state;

    final loginUri =
        Uri.parse('$cognitoDomain/oauth2/authorize').replace(
      queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'scope': 'openid email',
        'redirect_uri': redirectUri,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
      },
    );

    html.window.location.href = loginUri.toString();
  }

  Future<void> _handleAuthCallback() async {
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    final returnedState = uri.queryParameters['state'];
    final authError = uri.queryParameters['error'];

    if (authError != null) {
      if (!mounted) return;

      setState(() {
        authMessage =
            uri.queryParameters['error_description'] ?? authError;
        authChecking = false;
      });
      return;
    }

    // No OAuth callback: use the session already stored in this tab.
    if (code == null) {
      if (accessToken != null && accessToken!.isNotEmpty) {
        await loadDocuments(showErrors: false);
      }

      if (mounted) {
        setState(() => authChecking = false);
      }
      return;
    }

    final expectedState =
        html.window.sessionStorage['trustvault_oauth_state'];
    final verifier =
        html.window.sessionStorage['trustvault_pkce_verifier'];

    html.window.history.replaceState(
      null,
      '',
      html.window.location.pathname,
    );

    if (expectedState == null ||
        returnedState == null ||
        returnedState != expectedState ||
        verifier == null) {
      if (!mounted) return;

      setState(() {
        authMessage =
            'Login verification failed. Please sign in again.';
        authChecking = false;
      });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$cognitoDomain/oauth2/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'code': code,
          'redirect_uri': redirectUri,
          'code_verifier': verifier,
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Cognito token request failed (${response.statusCode}).',
        );
      }

      final result =
          jsonDecode(response.body) as Map<String, dynamic>;
      final token = result['access_token'] as String?;

      if (token == null || token.isEmpty) {
        throw Exception('Cognito did not return an access token.');
      }

      html.window.sessionStorage['trustvault_access_token'] = token;
      html.window.sessionStorage.remove('trustvault_pkce_verifier');
      html.window.sessionStorage.remove('trustvault_oauth_state');

      if (!mounted) return;

      setState(() {
        accessToken = token;
        authMessage = null;
        authChecking = false;
      });

      showMessage('Signed in successfully.');

      // Load existing S3 files after login.
      await loadDocuments();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        authMessage = error.toString();
        authChecking = false;
      });
    }
  }

  void signOut() {
    html.window.sessionStorage.remove('trustvault_access_token');
    html.window.sessionStorage.remove('trustvault_pkce_verifier');
    html.window.sessionStorage.remove('trustvault_oauth_state');

    setState(() {
      accessToken = null;
      documents.clear();
      documentsError = null;
    });

    final logoutUri = Uri.parse('$cognitoDomain/logout').replace(
      queryParameters: {
        'client_id': clientId,
        'logout_uri': redirectUri,
      },
    );

    html.window.location.href = logoutUri.toString();
  }

  Future<Map<String, dynamic>> callVaultApi(
    Map<String, dynamic> body,
  ) async {
    final token = accessToken;

    if (token == null || token.isEmpty) {
      throw Exception('Please sign in again.');
    }

    final response = await http.post(
      Uri.parse(presignEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'API request failed (${response.statusCode}): '
        '${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response from the TrustVault API.');
    }

    return decoded;
  }

  // Fetch the current user's saved documents from S3 through Lambda.
  Future<void> loadDocuments({bool showErrors = true}) async {
    if (accessToken == null || accessToken!.isEmpty) return;
    if (isLoadingDocuments) return;

    if (mounted) {
      setState(() {
        isLoadingDocuments = true;
        documentsError = null;
      });
    }

    try {
      final data = await callVaultApi({'action': 'list'});
      final rawFiles = data['files'];

      if (rawFiles is! List) {
        throw Exception('The API response does not contain a file list.');
      }

      final loadedDocuments = <VaultDocument>[];

      for (final item in rawFiles) {
        if (item is! Map) continue;

        final key = item['key']?.toString() ?? '';
        final name = item['name']?.toString() ?? 'Unnamed file';

        final rawSize = item['size'];
        final size = rawSize is num
            ? rawSize.toInt()
            : int.tryParse(rawSize?.toString() ?? '') ?? 0;

        final rawDate = item['lastModified']?.toString();
        final modifiedDate =
            rawDate == null ? null : DateTime.tryParse(rawDate);

        if (key.isEmpty) continue;

        loadedDocuments.add(
          VaultDocument(
            name: name,
            size: size,
            s3Key: key,
            lastModified: modifiedDate,
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        documents
          ..clear()
          ..addAll(loadedDocuments);
        documentsError = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        documentsError = error.toString();
      });

      if (showErrors) {
        showMessage('Could not load documents: $error');
      }
    } finally {
      if (mounted) {
        setState(() => isLoadingDocuments = false);
      }
    }
  }

  Future<Uint8List> readFileBytes(html.File file) async {
    final reader = html.FileReader();
    final completed = reader.onLoad.first;

    reader.readAsDataUrl(file);
    await completed;

    if (reader.error != null) {
      throw Exception('Browser file read failed: ${reader.error}');
    }

    final result = reader.result;

    if (result is! String) {
      throw Exception('Unexpected file data type: ${result.runtimeType}');
    }

    final commaIndex = result.indexOf(',');

    if (commaIndex < 0) {
      throw Exception('Invalid file data URL.');
    }

    try {
      return Uint8List.fromList(
        base64.decode(result.substring(commaIndex + 1)),
      );
    } on FormatException catch (error) {
      throw Exception('Base64 decoding failed: $error');
    }
  }

  Future<void> selectAndUpload() async {
    if (isBusy) return;

    if (accessToken == null) {
      showMessage('Please sign in before uploading documents.');
      return;
    }

    final picker = html.FileUploadInputElement()
      ..accept = '*/*'
      ..multiple = false
      ..style.display = 'none';

    html.document.body?.append(picker);
    final selection = picker.onChange.first;

    try {
      picker.click();
      await selection;

      final selected = picker.files;
      if (selected == null || selected.isEmpty) return;

      final file = selected.first;

      if (!mounted) return;
      setState(() => isBusy = true);

      final document = VaultDocument(
        name: file.name,
        size: file.size,
        status: 'Uploading...',
      );

      setState(() {
        documents.insert(0, document);
      });

      try {
        await uploadToS3(file, document);

        if (mounted) {
          setState(() {
            document.status = 'Uploaded successfully';
          });
        }

        showMessage('${file.name} uploaded successfully.');

        // Refresh from S3 so the list reflects saved files.
        await loadDocuments();
      } catch (error) {
        if (mounted) {
          setState(() {
            document.status = 'Upload failed';
          });
        }

        showMessage('Upload failed: $error');
      }
    } catch (error) {
      showMessage('File selection failed: $error');
    } finally {
      picker.remove();

      if (mounted) {
        setState(() => isBusy = false);
      }
    }
  }

  Future<void> uploadToS3(
    html.File file,
    VaultDocument document,
  ) async {
    final bytes = await readFileBytes(file);

    const allowedTypes = {
      'application/pdf',
      'image/jpeg',
      'image/png',
      'text/plain',
      'application/octet-stream',
    };

    final browserType = file.type.toLowerCase();
    final contentType = allowedTypes.contains(browserType)
        ? browserType
        : 'application/octet-stream';

    final data = await callVaultApi({
      'fileName': file.name,
      'contentType': contentType,
    });

    final uploadUrl = data['uploadUrl'] as String?;
    final key = data['key'] as String?;

    if (uploadUrl == null ||
        uploadUrl.isEmpty ||
        key == null ||
        key.isEmpty) {
      throw Exception('The API response is missing uploadUrl or key.');
    }

    final uploadResponse = await http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );

    if (uploadResponse.statusCode != 200 &&
        uploadResponse.statusCode != 204) {
      throw Exception(
        'S3 upload failed with status ${uploadResponse.statusCode}.',
      );
    }

    document.s3Key = key;
  }

  Future<void> downloadDocument(VaultDocument document) async {
    if (isBusy) return;

    final key = document.s3Key;

    if (accessToken == null || accessToken!.isEmpty) {
      showMessage('Please sign in again before downloading.');
      return;
    }

    if (key == null || key.isEmpty) {
      showMessage('File key is missing. Refresh your documents.');
      return;
    }

    setState(() => isBusy = true);

    try {
      final data = await callVaultApi({
        'action': 'download',
        'key': key,
      });

      final downloadUrl = data['downloadUrl'] as String?;

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('The API did not return a download URL.');
      }

      html.window.open(downloadUrl, '_blank');
      showMessage('Download started for ${document.name}.');
    } catch (error) {
      showMessage('Download failed: $error');
    } finally {
      if (mounted) {
        setState(() => isBusy = false);
      }
    }
  }

  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String formatDate(DateTime? date) {
    if (date == null) return 'Date unavailable';

    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');

    return '$day/$month/${local.year}';
  }

  IconData getFileIcon(String name) {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';

    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return Icons.image_rounded;
      case 'doc':
      case 'docx':
      case 'txt':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'zip':
      case 'rar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = accessToken != null && accessToken!.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, size: 28),
            SizedBox(width: 10),
            Text(
              'TrustVault',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ],
        ),
        actions: [
          if (authChecking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: signedIn ? signOut : signIn,
                icon: Icon(
                  signedIn ? Icons.logout : Icons.login,
                  color: Colors.white,
                ),
                label: Text(
                  signedIn ? 'Sign out' : 'Sign in',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Your secure document space',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF163344),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Keep your important documents organised in one place.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 24),
              if (authMessage != null)
                Card(
                  color: const Color(0xFFFFF0F0),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Authentication message: $authMessage',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFFE0E7EF)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F5F2),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.cloud_upload_rounded,
                          size: 48,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Add documents to TrustVault',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF163344),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        signedIn
                            ? 'Choose a document to upload securely to AWS.'
                            : 'Sign in to upload documents securely.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: 240,
                        child: FilledButton.icon(
                          onPressed: isBusy || authChecking || !signedIn
                              ? null
                              : selectAndUpload,
                          icon: isBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.attach_file_rounded),
                          label: Text(
                            isBusy ? 'Processing...' : 'Select File & Upload',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        signedIn ? 'Signed in' : 'Not signed in',
                        style: TextStyle(
                          color: signedIn
                              ? Colors.green.shade700
                              : Colors.blueGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'My Documents',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF163344),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh documents',
                    onPressed: signedIn &&
                            !isLoadingDocuments &&
                            !isBusy
                        ? () => loadDocuments()
                        : null,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  Chip(
                    avatar: const Icon(Icons.folder_rounded, size: 18),
                    label: Text('${documents.length} files'),
                  ),
                ],
              ),
              if (isLoadingDocuments)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (documentsError != null)
                Card(
                  color: const Color(0xFFFFF0F0),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Could not load saved files.',
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(documentsError!),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: isLoadingDocuments
                                ? null
                                : () => loadDocuments(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (!isLoadingDocuments && documents.isEmpty)
                Card(
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 38,
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.folder_open_rounded,
                          size: 54,
                          color: Colors.blueGrey,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          signedIn
                              ? 'No saved documents found'
                              : 'Sign in to view your documents',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Your saved files will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...documents.map((document) {
                  final success =
                      document.status == 'Uploaded successfully';
                  final failed = document.status == 'Upload failed';

                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Icon(
                        getFileIcon(document.name),
                        color: const Color(0xFF0F766E),
                        size: 30,
                      ),
                      title: Text(
                        document.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${formatSize(document.size)}'
                        ' • ${formatDate(document.lastModified)}'
                        ' • ${document.status}',
                        style: TextStyle(
                          color: success
                              ? Colors.green.shade700
                              : failed
                                  ? Colors.red
                                  : Colors.blueGrey,
                        ),
                      ),
                      trailing: success
                          ? IconButton(
                              tooltip: 'Download ${document.name}',
                              onPressed: isBusy
                                  ? null
                                  : () => downloadDocument(document),
                              icon: const Icon(
                                Icons.download_rounded,
                                color: Color(0xFF0F766E),
                              ),
                            )
                          : Icon(
                              failed ? Icons.error : Icons.cloud_upload,
                              color: failed ? Colors.red : Colors.blueGrey,
                            ),
                    ),
                  );
                }),
              const SizedBox(height: 16),
              const Card(
                color: Color(0xFFFFF7E8),
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Security note: documents use short-lived presigned '
                    'URLs. Keep your S3 bucket private and never place '
                    'AWS access keys in Flutter.',
                    style: TextStyle(
                      height: 1.5,
                      color: Color(0xFF78350F),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'TrustVault • Secure document management',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.blueGrey,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
