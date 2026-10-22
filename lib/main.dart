
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:html' as html;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const TrustVaultApp());

const String cognitoDomain =
    'https://us-east-16bj40uxfi.auth.us-east-1.amazoncognito.com';
const String clientId = '24tonblo0hgmp5hdad6s11jesv';
const String redirectUri =
    'https://staging.d1g1njsg5owizr.amplifyapp.com/';
const String presignEndpoint =
    'https://y76x3dol83.execute-api.us-east-1.amazonaws.com/presign';

const teal = Color(0xFF087F75);
const darkTeal = Color(0xFF075E59);
const pageBg = Color(0xFFF3F7FB);
const borderColor = Color(0xFFDCE8F2);

class TrustVaultApp extends StatelessWidget {
  const TrustVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrustVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: teal),
        scaffoldBackgroundColor: pageBg,
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
  String? idToken;
  String? userEmail;
  String? userName;
  String? authMessage;
  String? documentsError;

  final List<VaultDocument> documents = [];

  @override
  void initState() {
    super.initState();

    accessToken = html.window.sessionStorage['trustvault_access_token'];
    idToken = html.window.sessionStorage['trustvault_id_token'];
    _loadProfile();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleAuthCallback();
    });
  }

  void _loadProfile() {
    try {
      final token = idToken;
      if (token == null || token.isEmpty) return;

      final parts = token.split('.');
      if (parts.length != 3) return;

      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final claims = jsonDecode(payload) as Map<String, dynamic>;
      final email = claims['email']?.toString();

      if (!mounted) return;
      setState(() {
        userEmail = email;
        userName = claims['name']?.toString() ??
            claims['preferred_username']?.toString() ??
            (email != null && email.contains('@')
                ? email.split('@').first
                : null);
      });
    } catch (_) {
      // Profile details are optional; the dashboard remains usable.
    }
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

    html.window.sessionStorage['trustvault_pkce_verifier'] = verifier;
    html.window.sessionStorage['trustvault_oauth_state'] = state;

    final loginUri = Uri.parse('$cognitoDomain/oauth2/authorize').replace(
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

    if (code == null) {
      if (accessToken != null && accessToken!.isNotEmpty) {
        _loadProfile();
        await loadDocuments(showErrors: false);
      }
      if (mounted) setState(() => authChecking = false);
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
        authMessage = 'Login verification failed. Please sign in again.';
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

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final token = result['access_token'] as String?;
      final receivedIdToken = result['id_token'] as String?;

      if (token == null || token.isEmpty) {
        throw Exception('Cognito did not return an access token.');
      }

      html.window.sessionStorage['trustvault_access_token'] = token;

      if (receivedIdToken != null && receivedIdToken.isNotEmpty) {
        html.window.sessionStorage['trustvault_id_token'] =
            receivedIdToken;
        idToken = receivedIdToken;
      }

      html.window.sessionStorage.remove('trustvault_pkce_verifier');
      html.window.sessionStorage.remove('trustvault_oauth_state');

      if (!mounted) return;
      setState(() {
        accessToken = token;
        authMessage = null;
        authChecking = false;
      });

      _loadProfile();
      showMessage('Signed in successfully.');
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
    html.window.sessionStorage.remove('trustvault_id_token');
    html.window.sessionStorage.remove('trustvault_pkce_verifier');
    html.window.sessionStorage.remove('trustvault_oauth_state');

    setState(() {
      accessToken = null;
      idToken = null;
      userEmail = null;
      userName = null;
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
        'API request failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response from the TrustVault API.');
    }
    return decoded;
  }

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

      final loaded = <VaultDocument>[];

      for (final item in rawFiles) {
        if (item is! Map) continue;

        final key = item['key']?.toString() ?? '';
        final name = item['name']?.toString() ?? 'Unnamed file';
        final rawSize = item['size'];
        final size = rawSize is num
            ? rawSize.toInt()
            : int.tryParse(rawSize?.toString() ?? '') ?? 0;
        final rawDate = item['lastModified']?.toString();
        final date = rawDate == null ? null : DateTime.tryParse(rawDate);

        if (key.isEmpty) continue;

        loaded.add(
          VaultDocument(
            name: name,
            size: size,
            s3Key: key,
            lastModified: date,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        documents
          ..clear()
          ..addAll(loaded);
        documentsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => documentsError = error.toString());
      if (showErrors) showMessage('Could not load documents: $error');
    } finally {
      if (mounted) setState(() => isLoadingDocuments = false);
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
    if (commaIndex < 0) throw Exception('Invalid file data URL.');

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

      setState(() => documents.insert(0, document));

      try {
        await uploadToS3(file, document);

        if (mounted) {
          setState(() => document.status = 'Uploaded successfully');
        }

        showMessage('${file.name} uploaded successfully.');
        await loadDocuments();
      } catch (error) {
        if (mounted) {
          setState(() => document.status = 'Upload failed');
        }
        showMessage('Upload failed: $error');
      }
    } catch (error) {
      showMessage('File selection failed: $error');
    } finally {
      picker.remove();
      if (mounted) setState(() => isBusy = false);
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

    final response = await http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'S3 upload failed with status ${response.statusCode}.',
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
        'documentId': key,
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
      if (mounted) setState(() => isBusy = false);
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
    final extension =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';

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

  Widget _statCard(
    IconData icon,
    String label,
    String value,
    double availableWidth,
  ) {
    final rawWidth = availableWidth < 500
        ? availableWidth
        : (availableWidth - 48) / 3;
    final width = rawWidth.clamp(180.0, 320.0).toDouble();

    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE0F5F0),
                child: Icon(icon, color: teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.blueGrey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard(String displayName, String email) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'User Profile',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 22),
            const CircleAvatar(
              radius: 43,
              backgroundColor: teal,
              child: Icon(
                Icons.person_rounded,
                size: 52,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              email,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.blueGrey),
            ),
            const Divider(height: 30),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.verified_user_outlined, color: teal),
              title: Text('Account'),
              subtitle: Text('Signed in with Cognito'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined, color: teal),
              title: const Text('Your documents'),
              subtitle: Text('${documents.length} saved files'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickInfoCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Info',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.shield_outlined, color: teal),
              title: Text('Secure'),
              subtitle: Text(
                'Private documents with short-lived download links.',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cloud_outlined, color: teal),
              title: Text('AWS storage'),
              subtitle: Text('Files are managed by your TrustVault backend.'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentSection() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'My Documents',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh documents',
                  onPressed: isBusy || isLoadingDocuments
                      ? null
                      : () => loadDocuments(),
                  icon: const Icon(Icons.refresh_rounded, color: teal),
                ),
                Text('${documents.length} files'),
              ],
            ),
            if (isLoadingDocuments)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              )
            else if (documentsError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Could not load documents: $documentsError',
                      style: const TextStyle(color: Colors.red),
                    ),
                    TextButton(
                      onPressed: () => loadDocuments(),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              )
            else if (documents.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 44,
                      color: Colors.blueGrey,
                    ),
                    SizedBox(height: 10),
                    Text('No saved documents found'),
                    SizedBox(height: 4),
                    Text(
                      'Your uploaded files will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ],
                ),
              )
            else
              ...documents.map((document) {
                final success =
                    document.status == 'Uploaded successfully';

                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE3EBF3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Icon(
                      getFileIcon(document.name),
                      color: teal,
                      size: 30,
                    ),
                    title: Text(
                      document.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${formatSize(document.size)}'
                      ' � ${formatDate(document.lastModified)}'
                      '\n${document.status}',
                      style: TextStyle(
                        color: success ? Colors.green.shade700 : Colors.blueGrey,
                      ),
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Download ${document.name}',
                      onPressed: isBusy || !success
                          ? null
                          : () => downloadDocument(document),
                      icon: const Icon(Icons.download_rounded, color: teal),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = accessToken != null && accessToken!.isNotEmpty;
    final displayName = userName ?? 'TrustVault User';
    final email = userEmail ?? 'Email unavailable';
    final totalBytes = documents.fold<int>(
      0,
      (total, document) => total + document.size,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: darkTeal,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.verified_user_rounded, size: 30),
            SizedBox(width: 10),
            Text(
              'TrustVault',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          if (authChecking)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
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
      body: authChecking
          ? const Center(child: CircularProgressIndicator())
          : !signedIn
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Card(
                      margin: const EdgeInsets.all(24),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircleAvatar(
                              radius: 42,
                              backgroundColor: Color(0xFFE0F5F0),
                              child: Icon(
                                Icons.lock_rounded,
                                size: 42,
                                color: teal,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Your secure document space',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF102A43),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Sign in to securely upload and manage '
                              'your personal documents.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.blueGrey),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: signIn,
                                icon: const Icon(Icons.login),
                                label: const Text('Sign in securely'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: teal,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                            ),
                            if (authMessage != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                authMessage!,
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1050;

                    final dashboard = ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Card(
                          elevation: 0,
                          color: const Color(0xFFDDF7F1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  radius: 34,
                                  backgroundColor: teal,
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 42,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Welcome, $displayName',
                                        style: const TextStyle(
                                          fontSize: 23,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF102A43),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        email,
                                        style: const TextStyle(
                                          color: Color(0xFF486581),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      const Row(
                                        children: [
                                          Icon(
                                            Icons.verified_rounded,
                                            size: 17,
                                            color: Colors.green,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Signed in',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _statCard(
                              Icons.folder_rounded,
                              'My Documents',
                              '${documents.length}',
                              constraints.maxWidth,
                            ),
                            _statCard(
                              Icons.storage_rounded,
                              'Storage Used',
                              formatSize(totalBytes),
                              constraints.maxWidth,
                            ),
                            _statCard(
                              Icons.shield_rounded,
                              'Account Status',
                              'Active',
                              constraints.maxWidth,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Card(
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: borderColor),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.cloud_upload_rounded,
                                  size: 52,
                                  color: teal,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Secure document upload',
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Choose a file to upload securely to AWS.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.blueGrey),
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: 280,
                                  child: FilledButton.icon(
                                    onPressed: isBusy
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
                                        : const Icon(Icons.attach_file),
                                    label: Text(
                                      isBusy
                                          ? 'Processing...'
                                          : 'Select File & Upload',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: teal,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.all(15),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _documentSection(),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE1F5F2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.shield_rounded, color: teal),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Security note: documents use short-lived '
                                  'presigned URLs. Keep your S3 bucket private '
                                  'and never place AWS access keys in Flutter.',
                                  style: TextStyle(height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Center(
                          child: Text(
                            'TrustVault � Secure document management',
                            style: TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    );

                    if (!wide) return dashboard;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: dashboard),
                        SizedBox(
                          width: 300,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                            children: [
                              _profileCard(displayName, email),
                              const SizedBox(height: 14),
                              _quickInfoCard(),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}
