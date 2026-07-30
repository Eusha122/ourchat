import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/posts_api.dart';
import '../state/posts_providers.dart';

class UploadPostScreen extends ConsumerStatefulWidget {
  const UploadPostScreen({super.key});

  @override
  ConsumerState<UploadPostScreen> createState() => _UploadPostScreenState();
}

class _UploadPostScreenState extends ConsumerState<UploadPostScreen> {
  final _captionController = TextEditingController();
  XFile? _pickedImage;
  bool _isPosting = false;
  String? _error;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _pickedImage = picked);
  }

  Future<void> _submit() async {
    final image = _pickedImage;
    if (image == null) {
      setState(() => _error = 'Please choose a photo first');
      return;
    }

    setState(() {
      _isPosting = true;
      _error = null;
    });
    try {
      await ref
          .read(postsApiProvider)
          .createPost(
            imagePath: image.path,
            caption: _captionController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on PostsApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New post'),
        actions: [
          TextButton(
            onPressed: _isPosting ? null : _submit,
            child: _isPosting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Share'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: _pickedImage == null
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, size: 48),
                            SizedBox(height: 8),
                            Text('Choose a photo'),
                          ],
                        ),
                      )
                    : Image.file(File(_pickedImage!.path), fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionController,
            maxLength: 2000,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Caption (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
