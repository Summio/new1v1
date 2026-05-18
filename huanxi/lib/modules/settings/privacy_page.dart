import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_endpoints.dart';

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});
  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  String? _content;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final data = await DioClient.instance.apiGet(ApiEndpoints.privacy);
      if (mounted) {
        setState(() {
          _content = data['data']?['content'] as String?;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('隐私政策'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _content == null
          ? const Center(child: Text('加载失败'))
          : Markdown(
              data: _content!,
              padding: const EdgeInsets.all(16),
              styleSheet: MarkdownStyleSheet(
                h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                p: const TextStyle(fontSize: 15, height: 1.8),
              ),
            ),
    );
  }
}
