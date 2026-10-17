import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class JobSnapshot {
  final String status;
  final String? url;
  final String? latentKey;
  const JobSnapshot(this.status, this.url, {this.latentKey});
}

class StudioJobClient {
  StudioJobClient({
    http.Client? client,
    this.statusOverride,
    this.downloadOverride,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Future<JobSnapshot> Function(String jobId)? statusOverride;
  final Future<String?> Function(String url, String name)? downloadOverride;

  static const _base = 'https://genedit.mooo.com';

  Future<JobSnapshot> status(String jobId) async {
    if (statusOverride != null) return statusOverride!(jobId);
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) return const JobSnapshot('processing', null);
    final headers = {'Authorization': 'Bearer $token'};
    final resp = await _client
        .get(Uri.parse('$_base/job_status?job_id=$jobId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return const JobSnapshot('processing', null);
    final data = jsonDecode(resp.body);
    if (data is! Map) return const JobSnapshot('processing', null);
    final status = (data['status'] ?? 'processing').toString().toLowerCase();
    if (status != 'completed') return JobSnapshot(status, null);
    final latent = data['continuation_latent_r2_key']?.toString();
    final dl = await _client
        .get(Uri.parse('$_base/download_url/$jobId'), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (dl.statusCode != 200) return const JobSnapshot('completed', null);
    var url = dl.body.trim();
    if (url.startsWith('"') && url.endsWith('"')) {
      url = url.substring(1, url.length - 1);
    }
    return JobSnapshot(
      'completed',
      url.isEmpty ? null : url,
      latentKey: (latent == null || latent.isEmpty) ? null : latent,
    );
  }

  Future<String?> download(String url, String name) async {
    if (downloadOverride != null) return downloadOverride!(url, name);
    final resp = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (resp.statusCode >= 400 || resp.bodyBytes.isEmpty) return null;
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory('${root.path}/studio_media');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${folder.path}/$safe');
    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
  }
}
